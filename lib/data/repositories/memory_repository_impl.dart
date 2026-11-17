import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../../core/utils/vector_math.dart';
import '../../domain/repositories/llm_repository.dart';
import '../../domain/repositories/memory_repository.dart';
import '../local/local_database.dart';

/// Memoria híbrida 100 % en el teléfono: guarda en SQLCipher, busca por
/// similitud vectorial (embeddings guardados localmente) y cae a búsqueda
/// léxica si no hay embeddings o no hay conexión para vectorizar la consulta.
class MemoryRepositoryImpl implements MemoryRepository {
  MemoryRepositoryImpl(this._db, this._llm);

  final LocalDatabase _db;
  final LlmRepository _llm;
  static const _uuid = Uuid();

  List<EmbeddedMemory> _index = const [];
  String? _indexSignature;
  bool _indexing = false;

  @override
  Future<String> remember(String content, {String kind = 'fact', double importance = 0.5}) async {
    final id = _uuid.v4();
    await _db.insertMemory(id: id, kind: kind, content: content.trim(), importance: importance.clamp(0, 1));
    return id;
  }

  @override
  Future<List<String>> recall(String query, {int k = 5}) async {
    try {
      final index = await _loadIndex();
      if (index.isNotEmpty) {
        // La consulta se vectoriza en la nube; si tarda, no frenamos la decisión.
        final q = await _llm.embed(query).timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (q != null) {
          final hits = VectorMath.topK(q, index, k: k);
          if (hits.isNotEmpty) return hits;
        }
      }
    } catch (e, st) {
      JLog.e('memory', e, st);
    }
    return _db.searchMemoriesLocal(query, k: k);
  }

  @override
  Future<int> indexPending({int limit = 20}) async {
    if (_indexing) return 0;
    _indexing = true;
    var done = 0;
    try {
      final rows = await _db.memoriesWithoutEmbedding(limit: limit);
      for (final r in rows) {
        final v = await _llm.embed(r['content'] as String);
        if (v == null) break; // sin clave, modo privado o sin conexión: se reintenta luego
        await _db.setMemoryEmbedding(r['id'] as String, VectorMath.encode(v));
        done++;
      }
    } catch (e, st) {
      JLog.e('memory', e, st);
    } finally {
      _indexing = false;
    }
    return done;
  }

  Future<List<EmbeddedMemory>> _loadIndex() async {
    final signature = await _db.embeddedMemoriesSignature();
    if (signature == _indexSignature) return _index;
    final rows = await _db.embeddedMemories();
    _index = [
      for (final r in rows)
        if (r['embedding'] is Uint8List)
          EmbeddedMemory(
            content: r['content'] as String,
            importance: (r['importance'] as num).toDouble(),
            vector: VectorMath.decode(r['embedding'] as Uint8List),
          ),
    ];
    _indexSignature = signature;
    return _index;
  }
}
