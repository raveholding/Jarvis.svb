import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../../core/utils/logger.dart';

/// Voz nativa del sistema (sin costo, sin red).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;

  void Function()? onStart;
  void Function()? onDone;

  bool get isSpeaking => _speaking;

  Future<void> init() async {
    if (_ready) return;
    try {
      for (final lang in ['es-AR', 'es-US', 'es-419', 'es-ES']) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true) {
          await _tts.setLanguage(lang);
          break;
        }
      }
      await _tts.setSpeechRate(0.52);
      await _tts.setPitch(0.95);
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() {
        _speaking = true;
        onStart?.call();
      });
      void finished() {
        _speaking = false;
        onDone?.call();
      }

      _tts.setCompletionHandler(finished);
      _tts.setCancelHandler(finished);
      _tts.setErrorHandler((_) => finished());
      _ready = true;
    } catch (e, st) {
      JLog.e('tts', e, st);
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await init();
    await _tts.stop();
    _speaking = true;
    onStart?.call();
    try {
      await _tts.speak(text);
    } finally {
      if (_speaking) {
        _speaking = false;
        onDone?.call();
      }
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    if (_speaking) {
      _speaking = false;
      onDone?.call();
    }
  }
}
