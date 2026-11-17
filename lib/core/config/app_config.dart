/// Constantes globales de Jarvis SVB.
class AppConfig {
  AppConfig._();

  static const appName = 'Jarvis SVB';
  static const appVersion = '0.1.0';

  // ---------------- Audio ----------------
  static const sampleRate = 16000;

  /// 30 ms a 16 kHz.
  static const frameSamples = 480;
  static const frameMs = 30;

  // ---------------- LLM ----------------
  /// Modelo rápido para el motor de decisión (milisegundos).
  static const defaultGeminiFast = 'gemini-2.5-flash-lite';

  /// Modelo "inteligente" para resúmenes y mentoría.
  static const defaultGeminiSmart = 'gemini-2.5-flash';

  /// Si el modelo configurado no existe (404) se prueban estos en orden.
  static const geminiFallbacks = <String>[
    'gemini-3.5-flash-lite',
    'gemini-flash-lite-latest',
    'gemini-flash-latest',
  ];

  static const defaultGroqFast = 'llama-3.1-8b-instant';
  static const defaultGroqSmart = 'llama-3.3-70b-versatile';

  static const embeddingModel = 'gemini-embedding-001';
  static const embeddingDims = 768;

  // ---------------- Proactividad ----------------
  static const minEvalInterval = Duration(seconds: 20);
  static const triggerEvalInterval = Duration(seconds: 5);
  static const interruptionCooldown = Duration(minutes: 4);
  static const transcriptWindow = Duration(minutes: 6);
  static const dedupeWindow = Duration(minutes: 20);

  // ---------------- Desarrollador ----------------
  static const developerName = 'Vincular Business';
  static const developerWhatsapp = '(387) 4484132';
  static const developerWhatsappLink = 'https://wa.me/543874484132';
  static const developerEmail = 'vincularbusiness@gmail.com';
}
