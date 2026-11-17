import '../audio/listening_service.dart';

/// Contrato de transcripción local. Permite cambiar de motor sin tocar el resto.
abstract interface class SttEngine {
  bool get isReady;

  /// Descarga/carga el modelo (una sola vez; queda en el teléfono).
  Future<void> warmUp();

  /// Transcribe y destruye cualquier rastro del audio.
  Future<String> transcribe(SpeechSegment segment);
}
