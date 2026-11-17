import 'dart:math' as math;
import 'dart:typed_data';

/// Un recuerdo con su embedding, listo para comparar.
class EmbeddedMemory {
  const EmbeddedMemory({required this.content, required this.importance, required this.vector});

  final String content;
  final double importance;
  final Float32List vector;
}

/// Búsqueda vectorial en el teléfono (similitud coseno, fuerza bruta).
/// Para una memoria personal (miles de recuerdos) tarda milisegundos y
/// funciona sin conexión una vez calculados los embeddings.
class VectorMath {
  VectorMath._();

  /// Serializa un vector como float32 little-endian (4 bytes por dimensión).
  static Uint8List encode(List<double> vector) {
    final data = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat32(i * 4, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Float32List decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.lengthInBytes ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getFloat32(i * 4, Endian.little);
    }
    return out;
  }

  /// Similitud coseno en [-1, 1]. Devuelve 0 si las dimensiones no coinciden
  /// o alguno de los vectores es nulo.
  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      dot += x * y;
      na += x * x;
      nb += y * y;
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Los [k] recuerdos más parecidos a [query] con similitud >= [minSimilarity].
  static List<String> topK(
    List<double> query,
    List<EmbeddedMemory> memories, {
    int k = 5,
    double minSimilarity = 0.55,
  }) {
    final scored = <(double, EmbeddedMemory)>[];
    for (final m in memories) {
      final s = cosine(query, m.vector);
      if (s >= minSimilarity) scored.add((s, m));
    }
    scored.sort((x, y) {
      final bySim = y.$1.compareTo(x.$1);
      return bySim != 0 ? bySim : y.$2.importance.compareTo(x.$2.importance);
    });
    return scored.take(k).map((e) => e.$2.content).toList();
  }
}
