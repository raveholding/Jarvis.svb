/// Anonimiza datos sensibles ANTES de que cualquier texto salga del teléfono.
///
/// Orden importante: primero los números largos (tarjetas, CBU) para que
/// los patrones cortos (DNI, teléfono) no los partan.
class PiiRedactor {
  PiiRedactor._();

  static final List<(RegExp, String)> _rules = [
    // Emails
    (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+', caseSensitive: false), '[EMAIL]'),
    // CBU / CVU (22 dígitos)
    (RegExp(r'\b\d{22}\b'), '[CBU]'),
    // Tarjetas (13 a 19 dígitos, con espacios o guiones)
    (RegExp(r'\b(?:\d[ -]?){12,18}\d\b'), '[TARJETA]'),
    // CUIT / CUIL: 20-12345678-9
    (RegExp(r'\b(?:20|23|24|27|30|33|34)-?\d{8}-?\d\b'), '[CUIT]'),
    // Teléfonos argentinos e internacionales
    (RegExp(r'(?:\+?54\s?9?\s?)?(?:\(?\d{2,4}\)?[\s-]?)\d{3,4}[\s-]?\d{4}\b'), '[TEL]'),
    // DNI solo con palabra clave (para no confundir con montos: "1.500.000")
    (
      RegExp(r'\b(dni|documento)( n[uú]mero)?:?\s*\d{1,2}\.?\d{3}\.?\d{3}\b', caseSensitive: false),
      '[DNI]'
    ),
    // Claves dictadas: "la clave es 1234", "el código es 556677"
    (
      RegExp(r'\b(clave|contraseña|pin|c[oó]digo)( de [\wáéíóú]+)?( es| :)?\s+\S+', caseSensitive: false),
      r'[CLAVE]'
    ),
  ];

  static String redact(String input) {
    var out = input;
    for (final (pattern, replacement) in _rules) {
      out = out.replaceAll(pattern, replacement);
    }
    return out;
  }
}
