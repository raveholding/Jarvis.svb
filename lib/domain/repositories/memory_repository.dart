/// Memoria a largo plazo (local cifrada, con búsqueda semántica en el teléfono).
abstract interface class MemoryRepository {
  Future<String> remember(String content, {String kind = 'fact', double importance = 0.5});

  /// Devuelve los recuerdos más relevantes para [query].
  Future<List<String>> recall(String query, {int k = 5});

  /// Calcula los embeddings que falten. Devuelve cuántos recuerdos indexó.
  Future<int> indexPending({int limit = 20});
}
