import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/wav_encoder.dart';
import '../audio/listening_service.dart';
import 'stt_engine.dart';

/// Transcripción 100 % en el dispositivo con whisper.cpp (modelo GGML cuantizado).
class WhisperSttEngine implements SttEngine {
  WhisperSttEngine({required String Function() modelName, this.language = 'es'}) : _modelName = modelName;

  final String Function() _modelName;
  final String language;
  final WhisperController _controller = WhisperController();
  final Set<WhisperModel> _ready = {};

  WhisperModel get _model => switch (_modelName()) {
        'tiny' => WhisperModel.tiny,
        'small' => WhisperModel.small,
        _ => WhisperModel.base,
      };

  @override
  bool get isReady => _ready.contains(_model);

  @override
  Future<void> warmUp() async {
    final model = _model;
    if (_ready.contains(model)) return;
    await _controller.downloadModel(model);
    _ready.add(model);
  }

  /// Whisper "alucina" frases típicas de subtítulos cuando oye ruido.
  static final _hallucinations = RegExp(
    r'(subt[ií]tulos|gracias por ver|suscr[ií]bete|amara\.org|^\W*$)',
    caseSensitive: false,
  );

  @override
  Future<String> transcribe(SpeechSegment segment) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'seg_${DateTime.now().microsecondsSinceEpoch}.wav'));
    try {
      await warmUp();
      await file.writeAsBytes(
        WavEncoder.encodePcm16(segment.samples, sampleRate: AppConfig.sampleRate),
        flush: true,
      );
      final result = await _controller.transcribe(
        model: _model,
        audioPath: file.path,
        lang: language,
      );
      final text = (result?.transcription.text ?? '')
          .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ') // [BLANK_AUDIO], (música)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (_hallucinations.hasMatch(text)) return '';
      return text;
    } catch (e, st) {
      JLog.e('stt', e, st);
      return '';
    } finally {
      segment.wipe();
      await _secureDelete(file);
    }
  }

  /// Sobrescribe con ceros antes de borrar el WAV temporal.
  Future<void> _secureDelete(File file) async {
    try {
      if (await file.exists()) {
        final len = await file.length();
        await file.writeAsBytes(Uint8List(len), flush: true);
        await file.delete();
      }
    } catch (e) {
      JLog.e('stt', e);
    }
  }
}
