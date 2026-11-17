import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../../data/local/local_database.dart';
import '../../data/remote/supabase_sync.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/integration_event.dart';
import '../../domain/repositories/integration_sink.dart';

/// Capa Event-Driven "plug & play".
///
/// 1. Todo evento se publica en un bus interno ([events]).
/// 2. Se persiste en un OUTBOX local por cada destino habilitado (patrón Transactional Outbox).
/// 3. Un despachador entrega con reintentos exponenciales; nada se pierde sin conexión.
///
/// Hoy funciona 100 % autónomo (sin destinos). Para conectar un ERP/CRM:
/// configurá un webhook en Ajustes o implementá [IntegrationSink].
class IntegrationsService {
  IntegrationsService({
    required LocalDatabase db,
    required AppSettings Function() settings,
    required SupabaseSync supabase,
    http.Client? client,
  })  : _db = db,
        _settings = settings {
    final c = client ?? http.Client();
    _sinks = [
      WebhookSink(settings: settings, client: c),
      SupabaseQueueSink(settings: settings, supabase: supabase),
    ];
  }

  final LocalDatabase _db;
  final AppSettings Function() _settings;
  late final List<IntegrationSink> _sinks;
  final _bus = StreamController<IntegrationEvent>.broadcast();
  static const _uuid = Uuid();
  static const _maxAttempts = 6;
  bool _dispatching = false;

  /// Suscribite acá desde cualquier módulo interno.
  Stream<IntegrationEvent> get events => _bus.stream;

  /// Para registrar destinos personalizados (ERP, CRM, Google Sheets, etc.).
  void registerSink(IntegrationSink sink) => _sinks.add(sink);

  Future<IntegrationEvent> emit(JarvisEventType type, Map<String, dynamic> data) async {
    final event = IntegrationEvent(id: _uuid.v4(), type: type, occurredAt: DateTime.now(), data: data);
    _bus.add(event);
    final payload = jsonEncode(event.toJson());
    for (final sink in _sinks.where((s) => s.enabled)) {
      await _db.enqueueOutbox(id: '${event.id}:${sink.id}', sink: sink.id, eventType: type.wireName, payload: payload);
    }
    unawaited(dispatchPending());
    return event;
  }

  Future<void> dispatchPending() async {
    if (_dispatching || !_settings().cloudEnabled) return;
    _dispatching = true;
    try {
      final due = await _db.dueOutbox();
      for (final row in due) {
        final id = row['id'] as String;
        final sinkId = row['sink'] as String;
        final attempts = (row['attempts'] as int) + 1;
        final sink = _sinks.where((s) => s.id == sinkId).firstOrNull;
        if (sink == null || !sink.enabled) continue;
        try {
          final json = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final event = IntegrationEvent(
            id: json['id'] as String,
            type: JarvisEventType.values.firstWhere((t) => t.wireName == json['type']),
            occurredAt: DateTime.parse(json['occurred_at'] as String),
            data: Map<String, dynamic>.from(json['data'] as Map),
          );
          await sink.deliver(event);
          await _db.markOutboxDelivered(id);
        } catch (e) {
          final backoff = Duration(seconds: 30 * math.pow(2, attempts - 1).toInt());
          await _db.markOutboxFailed(
            id,
            attempts: attempts,
            next: DateTime.now().add(backoff),
            error: e.toString(),
            dead: attempts >= _maxAttempts,
          );
          JLog.e('integrations', 'Fallo entregando a $sinkId (intento $attempts): $e');
        }
      }
    } finally {
      _dispatching = false;
    }
  }
}

/// Entrega HTTP firmada con HMAC-SHA256 (mismo esquema que Stripe/GitHub).
class WebhookSink implements IntegrationSink {
  WebhookSink({required AppSettings Function() settings, required http.Client client})
      : _settings = settings,
        _client = client;

  final AppSettings Function() _settings;
  final http.Client _client;

  @override
  String get id => 'webhook';

  @override
  bool get enabled => _settings().hasWebhook;

  @override
  Future<void> deliver(IntegrationEvent event) async {
    final s = _settings();
    final body = jsonEncode(event.toJson());
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'JarvisSVB/1.0',
      'X-Jarvis-Event': event.type.wireName,
      'X-Jarvis-Delivery': event.id,
      'X-Jarvis-Timestamp': timestamp,
    };
    if (s.webhookSecret.isNotEmpty) {
      final mac = Hmac(sha256, utf8.encode(s.webhookSecret)).convert(utf8.encode('$timestamp.$body'));
      headers['X-Jarvis-Signature'] = 'sha256=$mac';
    }
    final res = await _client
        .post(Uri.parse(s.webhookUrl.trim()), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}

/// Espeja el evento en la tabla `webhook_queue` de Supabase para fan-out server-side.
class SupabaseQueueSink implements IntegrationSink {
  SupabaseQueueSink({required AppSettings Function() settings, required SupabaseSync supabase})
      : _settings = settings,
        _supabase = supabase;

  final AppSettings Function() _settings;
  final SupabaseSync _supabase;

  @override
  String get id => 'supabase_queue';

  @override
  bool get enabled => _settings().hasSupabase;

  @override
  Future<void> deliver(IntegrationEvent event) => _supabase.enqueueRemoteEvent(event.toJson());
}
