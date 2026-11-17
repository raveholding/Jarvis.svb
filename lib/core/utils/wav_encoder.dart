import 'dart:typed_data';

/// Codifica PCM16 mono en un contenedor WAV (requerido por whisper.cpp).
class WavEncoder {
  WavEncoder._();

  static Uint8List encodePcm16(
    Int16List samples, {
    int sampleRate = 16000,
    int channels = 1,
  }) {
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);

    void writeTag(int offset, String tag) {
      for (var i = 0; i < 4; i++) {
        bytes.setUint8(offset + i, tag.codeUnitAt(i));
      }
    }

    writeTag(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    writeTag(8, 'WAVE');
    writeTag(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // tamaño del chunk fmt
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeTag(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
