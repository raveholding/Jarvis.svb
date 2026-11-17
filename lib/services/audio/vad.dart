import 'dart:math' as math;
import 'dart:typed_data';

/// Contrato del detector de voz. Permite cambiar a Silero (ONNX) sin tocar
/// el resto del pipeline (ver docs/ARQUITECTURA.md → "Mejoras").
abstract interface class VoiceActivityDetector {
  /// true si el frame de 30 ms contiene voz humana.
  bool isSpeech(Int16List frame);

  /// Nivel 0..1 del último frame (para animar el orbe).
  double get lastLevel;

  set sensitivity(double value);

  void reset();
}

/// VAD adaptativo estilo WebRTC, en Dart puro y O(n) por frame:
/// - Energía RMS contra un piso de ruido que se adapta al ambiente.
/// - Tasa de cruces por cero (ZCR) para descartar golpes y ruido blanco.
/// Consume < 1 % de CPU: el modelo pesado (Whisper) solo corre cuando esto dice "voz".
class AdaptiveEnergyVad implements VoiceActivityDetector {
  AdaptiveEnergyVad({double sensitivity = 0.5}) : _sensitivity = sensitivity.clamp(0.0, 1.0);

  double _sensitivity;
  double _noiseFloor = 250;
  double _level = 0;

  static const _minRms = 120.0;

  @override
  set sensitivity(double value) => _sensitivity = value.clamp(0.0, 1.0);

  @override
  double get lastLevel => _level;

  @override
  void reset() {
    _noiseFloor = 250;
    _level = 0;
  }

  @override
  bool isSpeech(Int16List frame) {
    if (frame.isEmpty) return false;
    var sum = 0.0;
    var crossings = 0;
    var prev = frame[0];
    for (var i = 0; i < frame.length; i++) {
      final s = frame[i];
      sum += s * s;
      if (i > 0 && (prev >= 0) != (s >= 0)) crossings++;
      prev = s;
    }
    final rms = math.sqrt(sum / frame.length);
    final zcr = crossings / frame.length;

    // Nivel perceptual (log) para la animación.
    _level = (math.log(1 + rms) / math.log(1 + 6000)).clamp(0.0, 1.0);

    // Más sensibilidad = umbral más cercano al ruido de fondo.
    final factor = 3.2 - 1.8 * _sensitivity; // 1.4 .. 3.2
    final threshold = math.max(_noiseFloor * factor, _minRms);
    final voicedZcr = zcr > 0.01 && zcr < 0.40;
    final speech = rms > threshold && voicedZcr;

    // El piso de ruido se adapta rápido al silencio y muy lento durante la voz.
    final alpha = speech ? 0.001 : 0.05;
    _noiseFloor = (_noiseFloor * (1 - alpha) + rms * alpha).clamp(40.0, 4000.0);
    return speech;
  }
}
