import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/entities/agent_decision.dart';
import '../../domain/entities/daily_summary.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/entities/proactivity_rule.dart';

/// Base de datos local cifrada con SQLCipher (AES-256).
/// La clave se genera al primer inicio y vive solo en el Android Keystore.
class LocalDatabase {
  LocalDatabase(this._secure);

  final FlutterSecureStorage _secure;
  Database? _db;

  static const _keyName = 'jarvis_db_cipher_key';

  Database get db {
    final d = _db;
    if (d == null) throw StateError('LocalDatabase no inicializada');
    return d;
  }

  Future<void> open() async {
    if (_db != null) return;
    final password = await _getOrCreateKey();
    final path = p.join(await getDatabasesPath(), 'jarvis_secure.db');
    _db = await openDatabase(
      path,
      password: password,
      version: 1,
      onCreate: _onCreate,
    );
    await _seedRules();
  }

  Future<String> _getOrCreateKey() async {
    var key = await _secure.read(key: _keyName);
    if (key == null) {
      final rnd = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await _secure.write(key: _keyName, value: key);
    }
    return key;
  }

  Future<void> _onCreate(Database db, int version) async {
    final b = db.batch();
    b.execute('''
      CREATE TABLE context_events(
        id TEXT PRIMARY KEY,
        occurred_at INTEGER NOT NULL,
        transcript TEXT NOT NULL,
        context_json TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('CREATE INDEX idx_ctx_time ON context_events(occurred_at)');
    b.execute('''
      CREATE TABLE decisions(
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        context_event_id TEXT,
        decision TEXT NOT NULL,
        priority TEXT,
        category TEXT,
        confidence REAL,
        headline TEXT,
        message TEXT,
        delivery TEXT,
        feedback TEXT,
        payload_json TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('CREATE INDEX idx_dec_time ON decisions(created_at)');
    b.execute('''
      CREATE TABLE tasks(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        due_at INTEGER,
        owner TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        decision_id TEXT,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE memories(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        importance REAL NOT NULL DEFAULT 0.5,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE summaries(
        date TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        content_json TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE rules(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        keywords TEXT,
        priority TEXT,
        enabled INTEGER NOT NULL DEFAULT 1
      )''');
    b.execute('''
      CREATE TABLE feed(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT,
        body TEXT,
        priority TEXT,
        ref_id TEXT,
        feedback TEXT,
        created_at INTEGER NOT NULL,
        dismissed INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE outbox(
        id TEXT PRIMARY KEY,
        sink TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL,
        last_error TEXT,
        created_at INTEGER NOT NULL
      )''');
    await b.commit(noResult: true);
  }

  Future<void> _seedRules() async {
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rules')) ?? 0;
    if (count > 0) return;
    final b = db.batch();
    for (final r in ProactivityRule.defaults) {
      b.insert('rules', r.toRow());
    }
    await b.commit(noResult: true);
  }

  // ---------------- Contexto ----------------

  Future<void> insertContextEvent({
    required String id,
    required DateTime at,
    required String transcript,
    Map<String, dynamic>? context,
  }) =>
      db.insert('context_events', {
        'id': id,
        'occurred_at': at.millisecondsSinceEpoch,
        'transcript': transcript,
        'context_json': context == null ? null : jsonEncode(context),
      });

  Future<List<Map<String, Object?>>> contextEventsSince(DateTime since, {int limit = 500}) => db.query(
        'context_events',
        where: 'occurred_at >= ?',
        whereArgs: [since.millisecondsSinceEpoch],
        orderBy: 'occurred_at ASC',
        limit: limit,
      );

  // ---------------- Decisiones ----------------

  Future<void> insertDecision(AgentDecision d) => db.insert(
        'decisions',
        {
          'id': d.id,
          'created_at': d.createdAt.millisecondsSinceEpoch,
          'context_event_id': d.contextEventId,
          'decision': d.action.name,
          'priority': d.priority.name,
          'category': d.category,
          'confidence': d.confidence,
          'headline': d.headline,
          'message': d.message,
          'delivery': d.delivery.name,
          'payload_json': jsonEncode(d.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<AgentDecision>> decisionsSince(DateTime since, {bool onlyInterruptions = false}) async {
    final rows = await db.query(
      'decisions',
      where: onlyInterruptions ? "created_at >= ? AND decision != 'silence'" : 'created_at >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) {
      final j = jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
      return AgentDecision.fromLlmJson(
        j,
        id: r['id'] as String,
        contextEventId: r['context_event_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );
    }).toList();
  }

  Future<void> setDecisionFeedback(String decisionId, String feedback) =>
      db.update('decisions', {'feedback': feedback, 'synced': 0}, where: 'id = ?', whereArgs: [decisionId]);

  // ---------------- Tareas ----------------

  Future<void> insertTask({
    required String id,
    required String title,
    DateTime? due,
    String owner = 'me',
    String? decisionId,
  }) =>
      db.insert('tasks', {
        'id': id,
        'title': title,
        'due_at': due?.millisecondsSinceEpoch,
        'owner': owner,
        'decision_id': decisionId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<List<Map<String, Object?>>> pendingTasks() =>
      db.query('tasks', where: "status = 'pending'", orderBy: 'COALESCE(due_at, created_at) ASC', limit: 50);

  Future<void> completeTask(String id) =>
      db.update('tasks', {'status': 'done', 'synced': 0}, where: 'id = ?', whereArgs: [id]);

  // ---------------- Memoria ----------------

  Future<void> insertMemory({
    required String id,
    required String kind,
    required String content,
    required double importance,
  }) =>
      db.insert('memories', {
        'id': id,
        'kind': kind,
        'content': content,
        'importance': importance,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// Búsqueda léxica local (fallback sin conexión de la búsqueda vectorial).
  Future<List<String>> searchMemoriesLocal(String query, {int k = 5}) async {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-záéíóúñü0-9]+'))
        .where((w) => w.length > 3)
        .toSet()
        .take(8)
        .toList();
    if (words.isEmpty) {
      final rows = await db.query('memories', orderBy: 'importance DESC, created_at DESC', limit: k);
      return rows.map((r) => r['content'] as String).toList();
    }
    final where = words.map((_) => 'LOWER(content) LIKE ?').join(' OR ');
    final rows = await db.query(
      'memories',
      where: where,
      whereArgs: words.map((w) => '%$w%').toList(),
      orderBy: 'importance DESC, created_at DESC',
      limit: k,
    );
    return rows.map((r) => r['content'] as String).toList();
  }

  // ---------------- Resúmenes ----------------

  Future<void> upsertSummary(DailySummary s) => db.insert(
        'summaries',
        {
          'date': s.date,
          'created_at': s.createdAt.millisecondsSinceEpoch,
          'content_json': jsonEncode(s.content),
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<DailySummary?> summaryFor(String date) async {
    final rows = await db.query('summaries', where: 'date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : _summaryFromRow(rows.first);
  }

  Future<DailySummary?> latestSummary() async {
    final rows = await db.query('summaries', orderBy: 'date DESC', limit: 1);
    return rows.isEmpty ? null : _summaryFromRow(rows.first);
  }

  DailySummary _summaryFromRow(Map<String, Object?> r) => DailySummary(
        date: r['date'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        content: jsonDecode(r['content_json'] as String) as Map<String, dynamic>,
      );

  // ---------------- Reglas ----------------

  Future<List<ProactivityRule>> rules() async =>
      (await db.query('rules', orderBy: 'name ASC')).map(ProactivityRule.fromRow).toList();

  Future<void> setRuleEnabled(String id, bool enabled) =>
      db.update('rules', {'enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  // ---------------- Feed ----------------

  Future<void> insertFeed(FeedItem item) =>
      db.insert('feed', item.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<FeedItem>> recentFeed({int limit = 60}) async {
    final rows = await db.query('feed', where: 'dismissed = 0', orderBy: 'created_at DESC', limit: limit);
    return rows.map(FeedItem.fromRow).toList();
  }

  Future<void> dismissFeed(String id) => db.update('feed', {'dismissed': 1}, where: 'id = ?', whereArgs: [id]);

  Future<void> setFeedFeedback(String id, String feedback) =>
      db.update('feed', {'feedback': feedback}, where: 'id = ?', whereArgs: [id]);

  // ---------------- Outbox (webhooks) ----------------

  Future<void> enqueueOutbox({
    required String id,
    required String sink,
    required String eventType,
    required String payload,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('outbox', {
      'id': id,
      'sink': sink,
      'event_type': eventType,
      'payload': payload,
      'next_attempt_at': now,
      'created_at': now,
    });
  }

  Future<List<Map<String, Object?>>> dueOutbox({int limit = 20}) => db.query(
        'outbox',
        where: "status = 'pending' AND next_attempt_at <= ?",
        whereArgs: [DateTime.now().millisecondsSinceEpoch],
        orderBy: 'created_at ASC',
        limit: limit,
      );

  Future<void> markOutboxDelivered(String id) =>
      db.update('outbox', {'status': 'delivered', 'last_error': null}, where: 'id = ?', whereArgs: [id]);

  Future<void> markOutboxFailed(String id, {required int attempts, required DateTime next, required String error, bool dead = false}) =>
      db.update(
        'outbox',
        {
          'status': dead ? 'dead' : 'pending',
          'attempts': attempts,
          'next_attempt_at': next.millisecondsSinceEpoch,
          'last_error': error.length > 300 ? error.substring(0, 300) : error,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---------------- Sincronización ----------------

  Future<List<Map<String, Object?>>> unsynced(String table, {int limit = 50}) =>
      db.query(table, where: 'synced = 0', limit: limit);

  Future<void> markSynced(String table, String keyColumn, List<Object?> keys) async {
    if (keys.isEmpty) return;
    final placeholders = List.filled(keys.length, '?').join(',');
    await db.rawUpdate('UPDATE $table SET synced = 1 WHERE $keyColumn IN ($placeholders)', keys);
  }

  // ---------------- Retención / borrado ----------------

  Future<void> purgeOlderThan(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    await db.delete('context_events', where: 'occurred_at < ?', whereArgs: [cutoff]);
    await db.delete('feed', where: 'created_at < ?', whereArgs: [cutoff]);
    await db.delete('outbox', where: "status != 'pending' AND created_at < ?", whereArgs: [cutoff]);
  }

  Future<void> wipeAll() async {
    for (final t in ['context_events', 'decisions', 'tasks', 'memories', 'summaries', 'feed', 'outbox']) {
      await db.delete(t);
    }
  }
}
