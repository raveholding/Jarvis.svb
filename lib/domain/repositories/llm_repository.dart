/// fast = motor de decisión (baja latencia) · smart = resúmenes y mentoría.
enum LlmTier { fast, smart }

class LlmException implements Exception {
  const LlmException(this.provider, this.status, this.message);
  final String provider;
  final int status;
  final String message;

  @override
  String toString() => 'LlmException($provider, $status): $message';
}

/// Contrato del "cerebro" en la nube. La implementación decide proveedor y fallback.
abstract interface class LlmRepository {
  bool get isConfigured;

  Future<String> complete({
    required String system,
    required String user,
    LlmTier tier = LlmTier.fast,
    bool json = true,
  });

  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    LlmTier tier = LlmTier.fast,
  });

  /// Vector de 768 dimensiones o null si no hay proveedor de embeddings.
  Future<List<double>?> embed(String text);
}
