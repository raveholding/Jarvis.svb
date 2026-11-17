import 'package:uuid/uuid.dart';

import '../../domain/repositories/memory_repository.dart';
import '../local/local_database.dart';
import '../remote/supabase_sync.dart';

/// Memoria híbrida: escribe local (offline-first) y busca primero en pgvector,
/// con búsqueda léxica local como respaldo.
class MemoryRepositoryImpl implements MemoryRepository {
  MemoryRepositoryImpl(this._db, this._sync);

  final LocalDatabase _db;
  final SupabaseSync _sync;
  static const _uuid = Uuid();

  @override
  Future<String> remember(String content, {String kind = 'fact', double importance = 0.5}) async {
    final id = _uuid.v4();
    await _db.insertMemory(id: id, kind: kind, content: content.trim(), importance: importance.clamp(0, 1));
    return id;
  }

  @override
  Future<List<String>> recall(String query, {int k = 5}) async {
    final remote = await _sync.semanticRecall(query, k: k);
    if (remote.isNotEmpty) return remote;
    return _db.searchMemoriesLocal(query, k: k);
  }
}
