import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import 'vad.dart';

enum ListeningProfile {
  /// Escucha ambiente: cortes rápidos (0,7 s de silencio).
  ambient,

  /// Consulta al orbe: espera pausas más largas (1,2 s) para no cortarte.
  query,
}

/// Fragmento de voz detectado. El dueño DEBE llamar a [wipe] al terminar.
class SpeechSegment {
  SpeechSegment(this.samples, this.startedAt, this.profile);

  final Int16List samples;
  final DateTime startedAt;
  final ListeningProfile profile;

  Duration get duration => Duration(milliseconds: samples.length * 1000 ~/ AppConfig.sampleRate);

  /// Privacidad por diseño: sobrescribe el buffer con ceros.
  void wipe() => samples.fillRange(0, samples.length, 0);
}

/// Micrófono → frames de 30 ms → VAD → segmentos de voz.
/// El audio crudo nunca se guarda ni se envía: vive en RAM hasta transcribirse.
class ListeningService {
  ListeningService({VoiceActivityDetector? vad}) : vad = vad ?? AdaptiveEnergyVad();

  final VoiceActivityDetector vad;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  final _segments = StreamController<SpeechSegment>.broadcast();
  final _levels = StreamController<double>.broadcast();

  ListeningProfile profile = ListeningProfile.ambient;

  /// true mientras Jarvis habla (evita que se escuche a sí mismo).
  bool suspended = false;

  Stream<SpeechSegment> get segments => _segments.stream;
  Stream<double> get levels => _levels.stream;
  bool get isRunning => _sub != null;

  // ---- Estado de segmentación ----
  final Int16List _frame = Int16List(AppConfig.frameSamples);
  int _frameFill = 0;
  int? _carryByte;
  final ListQueue<Int16List> _preRoll = ListQueue<Int16List>();
  final List<int> _recent = <int>[];
  List<int>? _active;
  DateTime? _activeStart;
  int _silentFrames = 0;
  int _levelTick = 0;

  static const _preRollFrames = 10; // 300 ms antes de la voz
  static const _maxFrames = 25000 ~/ AppConfig.frameMs; // corte forzado a los 25 s
  static const _minSpeechFrames = 17; // ~0,5 s de voz real

  int get _hangoverFrames => profile == ListeningProfile.query ? 40 : 24;

  Future<bool> hasPermission() async {
    final r = AudioRecorder();
    try {
      return await r.hasPermission();
    } finally {
      await r.dispose();
    }
  }

  Future<bool> start() async {
    if (isRunning) return true;
    final rec = AudioRecorder();
    if (!await rec.hasPermission()) {
      await rec.dispose();
      return false;
    }
    try {
      final stream = await rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConfig.sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ));
      _recorder = rec;
      vad.reset();
      _resetSegmentation();
      _sub = stream.listen(
        _onBytes,
        onError: (Object e, StackTrace st) => JLog.e('audio', e, st),
        cancelOnError: false,
      );
      JLog.i('audio', 'Micrófono activo (16 kHz PCM16 mono)');
      return true;
    } catch (e, st) {
      JLog.e('audio', e, st);
      await rec.dispose();
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    await _recorder?.dispose();
    _recorder = null;
    _resetSegmentation();
    if (!_levels.isClosed) _levels.add(0);
  }

  Future<void> dispose() async {
    await stop();
    await _segments.close();
    await _levels.close();
  }

  // ---------------- Pipeline ----------------

  void _onBytes(Uint8List bytes) {
    var i = 0;
    final carry = _carryByte;
    if (carry != null && bytes.isNotEmpty) {
      _pushSample(_toInt16(carry, bytes[0]));
      _carryByte = null;
      i = 1;
    }
    for (; i + 1 < bytes.length; i += 2) {
      _pushSample(_toInt16(bytes[i], bytes[i + 1]));
    }
    if (i < bytes.length) _carryByte = bytes[i];
  }

  static int _toInt16(int lo, int hi) {
    final v = (hi << 8) | lo;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  void _pushSample(int s) {
    _frame[_frameFill++] = s;
    if (_frameFill == _frame.length) {
      _frameFill = 0;
      _processFrame();
    }
  }

  void _processFrame() {
    if (suspended) {
      _discardActive();
      _frame.fillRange(0, _frame.length, 0);
      if (++_levelTick % 3 == 0) _levels.add(0);
      return;
    }

    final frame = Int16List.fromList(_frame);
    final speech = vad.isSpeech(frame);
    if (++_levelTick % 3 == 0) _levels.add(speech ? vad.lastLevel : vad.lastLevel * 0.4);

    _recent.add(speech ? 1 : 0);
    if (_recent.length > 5) _recent.removeAt(0);

    final active = _active;
    if (active == null) {
      _preRoll.addLast(frame);
      if (_preRoll.length > _preRollFrames) {
        _preRoll.removeFirst().fillRange(0, AppConfig.frameSamples, 0);
      }
      // Arranque: 3 de los últimos 5 frames con voz.
      if (_recent.fold<int>(0, (a, b) => a + b) >= 3) {
        final buf = <int>[];
        for (final f in _preRoll) {
          buf.addAll(f);
        }
        _activeStart = DateTime.now().subtract(Duration(milliseconds: _preRoll.length * AppConfig.frameMs));
        _wipePreRoll();
        _active = buf;
        _silentFrames = 0;
      }
    } else {
      active.addAll(frame);
      frame.fillRange(0, frame.length, 0);
      _silentFrames = speech ? 0 : _silentFrames + 1;
      final frames = active.length ~/ AppConfig.frameSamples;
      if (_silentFrames >= _hangoverFrames || frames >= _maxFrames) {
        _closeActive();
      }
    }
  }

  void _closeActive() {
    final data = _active;
    if (data == null) return;
    final frames = data.length ~/ AppConfig.frameSamples;
    final speechFrames = frames - _silentFrames - _preRollFrames;
    if (speechFrames >= _minSpeechFrames && !_segments.isClosed) {
      _segments.add(SpeechSegment(Int16List.fromList(data), _activeStart ?? DateTime.now(), profile));
    }
    data.fillRange(0, data.length, 0);
    _active = null;
    _silentFrames = 0;
    _recent.clear();
  }

  void _discardActive() {
    _active?.fillRange(0, _active!.length, 0);
    _active = null;
    _silentFrames = 0;
    _recent.clear();
    _wipePreRoll();
  }

  void _wipePreRoll() {
    for (final f in _preRoll) {
      f.fillRange(0, f.length, 0);
    }
    _preRoll.clear();
  }

  void _resetSegmentation() {
    _discardActive();
    _frameFill = 0;
    _carryByte = null;
    _frame.fillRange(0, _frame.length, 0);
  }
}
