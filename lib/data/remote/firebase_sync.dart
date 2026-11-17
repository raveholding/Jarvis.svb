import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/vector_math.dart';
import '../../domain/entities/app_settings.dart';
import '../../firebase_options.dart';
import '../local/local_database.dart';

/// Respaldo en la nube sobre Firebase (Auth anónima + Cloud Firestore).
///
/// * La fuente de verdad sigue siendo la base local cifrada (offline-first).
/// * Nunca sube audio: solo texto ya anonimizado, decisiones, tareas, memorias y resúmenes.
/// * Cada usuario escribe únicamente bajo `users/{uid}/...` (ver `firestore.rules`).
/// * Firebase se inicializa recién cuando el usuario activa el respaldo.
class FirebaseSync {
  FirebaseSync({
    required LocalDatabase db,
    required AppSettings Function() settings,
  })  : _db = db,
        _settings = settings;

  final LocalDatabase _db;
  final AppSettings Function() _settings;

  static const _timeout = Duration(seconds: 20);
  static const collections = [
    'context_logs',
    'decisions',
    'tasks',
    'memories',
    'daily_summaries',
    'events',
  ];

  bool _initialized = false;
  bool _syncing = false;

  /// El usuario activó el respaldo y no está en modo privado.
  bool get enabled {
    final s = _settings();
    return s.cloudEnabled && s.cloudBackupEnabled;
  }

  /// UID de Firebase (solo disponible después de la primera sincronización).
  String? get userId => _initialized ? FirebaseAuth.instance.currentUser?.uid : null;

  Future<bool> ensureReady() async {
    if (!enabled) return false;
    try {
      await _init();
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        // Requiere el proveedor "Anónimo" habilitado en Firebase → Authentication.
        await auth.signInAnonymously().timeout(_timeout);
      }
      return auth.currentUser != null;
    } catch (e, st) {
      JLog.e('firebase', e, st);
      return false;
    }
  }

  Future<void> _init() async {
    if (_initialized) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
    }
    // Sin caché en disco: Firestore la guardaría SIN cifrar. La copia local
    // cifrada ya es SQLCipher y la cola de pendientes vive ahí.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    _initialized = true;
  }

  CollectionReference<Map<String, dynamic>> _col(String name) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection(name);
  }

  static Timestamp _ts(Object? millis) => Timestamp.fromMillisecondsSinceEpoch(millis as int);

  Future<void> pushPending() async {
    if (_syncing) return;
    _syncing = true;
    try {
      if (!await ensureReady()) return;
      final fs = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await fs.collection('users').doc(uid).set({
        'app': 'jarvis.svb',
        'app_version': AppConfig.appVersion,
        'last_sync_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(_timeout);

      // Contexto (texto anonimizado)
      await _pushTable(
        table: 'context_events',
        key: 'id',
        collection: 'context_logs',
        map: (r) => {
          'occurred_at': _ts(r['occurred_at']),
          'transcript_redacted': r['transcript'],
          'context': r['context_json'] == null ? null : _decode(r['context_json']),
        },
      );

      // Decisiones
      await _pushTable(
        table: 'decisions',
        key: 'id',
        collection: 'decisions',
        map: (r) => {
          'context_log_id': r['context_event_id'],
          'created_at': _ts(r['created_at']),
          'decision': r['decision'],
          'priority': r['priority'],
          'category': r['category'],
          'confidence': r['confidence'],
          'headline': r['headline'],
          'message': r['message'],
          'delivery': r['delivery'],
          'user_feedback': r['feedback'],
          'payload': _decode(r['payload_json']),
        },
      );

      // Tareas
      await _pushTable(
        table: 'tasks',
        key: 'id',
        collection: 'tasks',
        map: (r) => {
          'title': r['title'],
          'due_at': r['due_at'] == null ? null : _ts(r['due_at']),
          'owner': r['owner'],
          'status': r['status'],
          'source_decision_id': r['decision_id'],
          'created_at': _ts(r['created_at']),
        },
      );

      // Memorias (con su embedding si ya fue calculado en el teléfono)
      await _pushTable(
        table: 'memories',
        key: 'id',
        collection: 'memories',
        limit: 20,
        map: (r) {
          final emb = r['embedding'];
          return {
            'kind': r['kind'],
            'content': r['content'],
            'importance': r['importance'],
            'embedding': emb is Uint8List ? VectorMath.decode(emb).toList() : null,
            'source': 'jarvis.svb',
            'created_at': _ts(r['created_at']),
          };
        },
      );

      // Resúmenes diarios (id del documento = fecha)
      await _pushTable(
        table: 'summaries',
        key: 'date',
        collection: 'daily_summaries',
        map: (r) => {
          'summary_date': r['date'],
          'content': _decode(r['content_json']),
          'created_at': _ts(r['created_at']),
        },
      );
    } catch (e, st) {
      JLog.e('firebase', e, st);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushTable({
    required String table,
    required String key,
    required String collection,
    required Map<String, dynamic> Function(Map<String, Object?> row) map,
    int limit = 50,
  }) async {
    final rows = await _db.unsynced(table, limit: limit);
    if (rows.isEmpty) return;
    final col = _col(collection);
    final batch = FirebaseFirestore.instance.batch();
    for (final r in rows) {
      batch.set(col.doc(r[key].toString()), map(r), SetOptions(merge: true));
    }
    await batch.commit().timeout(_timeout);
    await _db.markSynced(table, key, rows.map((r) => r[key]).toList());
  }

  /// Espejo de la cola de eventos (para un panel web o Cloud Functions a futuro).
  Future<void> enqueueRemoteEvent(Map<String, dynamic> event) async {
    if (!await ensureReady()) throw StateError('Firebase no disponible');
    await _col('events').doc(event['id'].toString()).set({
      'event_type': event['type'],
      'payload': firestoreSafe(event),
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  /// Borra todo lo que este usuario subió a Firestore. Devuelve false si no
  /// se pudo completar (sin conexión, respaldo apagado, etc.).
  Future<bool> wipeRemote() async {
    if (!await ensureReady()) return false;
    try {
      final fs = FirebaseFirestore.instance;
      for (final name in collections) {
        final col = _col(name);
        while (true) {
          final snap = await col.limit(300).get().timeout(_timeout);
          if (snap.docs.isEmpty) break;
          final batch = fs.batch();
          for (final d in snap.docs) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(_timeout);
        }
      }
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await fs.collection('users').doc(uid).delete().timeout(_timeout);
      return true;
    } catch (e, st) {
      JLog.e('firebase', e, st);
      return false;
    }
  }

  static Object? _decode(Object? json) => firestoreSafe(jsonDecode(json as String));

  /// Firestore no admite listas dentro de listas: las anidadas se guardan como texto JSON.
  static Object? firestoreSafe(Object? value, {bool insideList = false}) {
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): firestoreSafe(e.value)};
    }
    if (value is List) {
      if (insideList) return jsonEncode(value);
      return [for (final v in value) firestoreSafe(v, insideList: true)];
    }
    return value;
  }
}
