import 'dart:developer' as dev;

/// Logger mínimo. Nunca loguea transcripciones completas en release.
class JLog {
  JLog._();

  static void i(String tag, String message) =>
      dev.log(message, name: 'jarvis.$tag');

  static void e(String tag, Object error, [StackTrace? stack]) =>
      dev.log('ERROR: $error', name: 'jarvis.$tag', error: error, stackTrace: stack, level: 1000);
}
