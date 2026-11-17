import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/llm_repository.dart';
import '../local/local_database.dart';

/// Sincroniza la base local cifrada con Supabase (PostgreSQL + pgvector).
/// Nunca sube audio: solo texto ya anonimizado, decisiones, memorias y resúmenes.
class SupabaseSync {
  SupabaseSync({
    required LocalDatabase db,
    required LlmRepository llm,
    required AppSettings Function() settings,
  })  : _db = db,
        _llm = llm,
        _settings = settings;

  final LocalDatabase _db;
  final LlmRepository _llm;
  final AppSettings Function() _settings;

  bool _initialized = false;
  String? _initializedUrl;
  bool _syncing = false;

  bool get needsRestart => _initialized && _initializedUrl != _settings().supabaseUrl.trim();

  SupabaseClient? get _client => _initialized ? Supabase.instance.client : null;

  Future<bool> ensureReady() async {
    final s = _settings();
    if (!s.cloudEnabled || !s.hasSupabase) return false;
    try {
      if (!_initialized) {
        await Supabase.initialize(url: s.supabaseUrl.trim(), anonKey: s.supabaseAnonKey.trim());
        _initialized = true;
        _initializedUrl = s.supabaseUrl.trim();
      }
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        // Requiere "Anonymous sign-ins" habilitado en Supabase → Authentication → Providers.
        await auth.signInAnonymously();
      }
      return true;
    } catch (e, st) {
      JLog.e('supabase', e, st);
      return false;
    }
  }

  Future<void> pushPending() async {
    if (_syncing) return;
    _syncing = true;
    try {
      if (!await ensureReady()) return;
      final client = _client!;

      // Contexto (texto anonimizado)
      final ctx = await _db.unsynced('context_events');
      if (ctx.isNotEmpty) {
        await client.from('context_logs').upsert(ctx
            .map((r) => {
                  'id': r['id'],
                  'occurred_at': DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int).toUtc().toIso8601String(),
                  'transcript_redacted': r['transcript'],
                  'context': r['context_json'] == null ? null : jsonDecode(r['context_json'] as String),
                })
            .toList());
        await _db.markSynced('context_events', 'id', ctx.map((r) => r['id']).toList());
      }

      // Decisiones
      final dec = await _db.unsynced('decisions');
      if (dec.isNotEmpty) {
        await client.from('decisions').upsert(dec
            .map((r) => {
                  'id': r['id'],
                  'context_log_id': r['context_event_id'],
                  'created_at': DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int).toUtc().toIso8601String(),
                  'decision': r['decision'],
                  'priority': r['priority'],
                  'category': r['category'],
                  'confidence': r['confidence'],
                  'headline': r['headline'],
                  'message': r['message'],
                  'delivery': r['delivery'],
                  'user_feedback': r['feedback'],
                  'payload': jsonDecode(r['payload_json'] as String),
                })
            .toList());
        await _db.markSynced('decisions', 'id', dec.map((r) => r['id']).toList());
      }

      // Tareas
      final tasks = await _db.unsynced('tasks');
      if (tasks.isNotEmpty) {
        await client.from('tasks').upsert(tasks
            .map((r) => {
                  'id': r['id'],
                  'title': r['title'],
                  'due_at': r['due_at'] == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(r['due_at'] as int).toUtc().toIso8601String(),
                  'owner': r['owner'],
                  'status': r['status'],
                  'source_decision_id': r['decision_id'],
                })
            .toList());
        await _db.markSynced('tasks', 'id', tasks.map((r) => r['id']).toList());
      }

      // Memorias con embedding (búsqueda semántica)
      final mem = await _db.unsynced('memories', limit: 20);
      for (final r in mem) {
        final content = r['content'] as String;
        final embedding = await _llm.embed(content);
        await client.from('memories').upsert({
          'id': r['id'],
          'kind': r['kind'],
          'content': content,
          'importance': r['importance'],
          'embedding': embedding,
          'source': 'jarvis.svb',
        });
        await _db.markSynced('memories', 'id', [r['id']]);
      }

      // Resúmenes
      final sums = await _db.unsynced('summaries');
      if (sums.isNotEmpty) {
        await client.from('daily_summaries').upsert(
              sums
                  .map((r) => {
                        'summary_date': r['date'],
                        'content': jsonDecode(r['content_json'] as String),
                      })
                  .toList(),
              onConflict: 'user_id,summary_date',
            );
        await _db.markSynced('summaries', 'date', sums.map((r) => r['date']).toList());
      }
    } catch (e, st) {
      JLog.e('supabase', e, st);
    } finally {
      _syncing = false;
    }
  }

  /// Búsqueda vectorial (pgvector) vía RPC `match_memories`.
  Future<List<String>> semanticRecall(String query, {int k = 5}) async {
    if (!await ensureReady()) return const [];
    final embedding = await _llm.embed(query);
    if (embedding == null) return const [];
    try {
      final res = await _client!.rpc('match_memories', params: {
        'query_embedding': embedding,
        'match_count': k,
        'min_similarity': 0.55,
      });
      if (res is! List) return const [];
      return res.whereType<Map>().map((r) => (r['content'] ?? '').toString()).where((c) => c.isNotEmpty).toList();
    } catch (e, st) {
      JLog.e('supabase', e, st);
      return const [];
    }
  }

  /// Espejo de la cola de eventos para entrega server-side (Edge Functions / pg_net).
  Future<void> enqueueRemoteEvent(Map<String, dynamic> event) async {
    if (!await ensureReady()) throw StateError('Supabase no disponible');
    await _client!.from('webhook_queue').upsert({
      'id': event['id'],
      'event_type': event['type'],
      'payload': event,
    });
  }
}
