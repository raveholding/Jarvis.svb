import 'dart:convert';

class JsonUtils {
  JsonUtils._();

  /// Extrae el primer objeto JSON de la respuesta de un LLM, tolerando
  /// bloques ```json y texto alrededor.
  static Map<String, dynamic> decodeObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'```\s*$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('La respuesta no contiene JSON');
    }
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('El JSON no es un objeto');
    }
    return decoded;
  }

  static List<String> stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e is Map ? (e['text'] ?? e['title'] ?? e.toString()).toString() : e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  static double toDouble(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static DateTime? toDate(dynamic value) {
    if (value is String && value.isNotEmpty && value != 'null') {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
