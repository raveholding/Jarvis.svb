/// Memoria a largo plazo (local + vectorial en Supabase).
abstract interface class MemoryRepository {
  Future<String> remember(String content, {String kind = 'fact', double importance = 0.5});

  /// Devuelve los recuerdos más relevantes para [query].
  Future<List<String>> recall(String query, {int k = 5});
}
