import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/di/providers.dart';
import '../core/utils/logger.dart';
import '../core/utils/pii_redactor.dart';
import '../data/local/local_database.dart';
import '../domain/entities/agent_decision.dart';
import '../domain/entities/app_settings.dart';
import '../domain/entities/daily_summary.dart';
import '../domain/entities/feed_item.dart';
import '../domain/entities/integration_event.dart';
import '../domain/entities/proactivity_rule.dart';
import '../services/audio/listening_service.dart';
import '../services/background/foreground_service.dart';
import '../services/decision/decision_engine.dart';
import '../services/stt/stt_engine.dart';
import 'usecases/answer_query.dart';
import 'usecases/generate_daily_summary.dart';

enum AgentPhase { idle, ambient, capturing, transcribing, thinking, speaking }

class AgentState {
  const AgentState({
    this.phase = AgentPhase.idle,
    this.ambientOn = false,
    this.pausedUntil,
    this.feed = const [],
    this.lastTranscript,
    this.status = 'Tocá el orbe para hablarme',
    this.modelReady = false,
    this.modelDownloading = false,
    this.error,
  });

  final AgentPhase phase;
  final bool ambientOn;
  final DateTime? pausedUntil;
  final List<FeedItem> feed;
  final String? lastTranscript;
  final String status;
  final bool modelReady;
  final bool modelDownloading;
  final String? error;

  bool get isPaused => pausedUntil != null && pausedUntil!.isAfter(DateTime.now());

  static const _keep = Object();

  AgentState copyWith({
    AgentPhase? phase,
    bool? ambientOn,
    Object? pausedUntil = _keep,
    List<FeedItem>? feed,
    Object? lastTranscript = _keep,
    String? status,
    bool? modelReady,
    bool? modelDownloading,
    Object? error = _keep,
  }) {
    return AgentState(
      phase: phase ?? this.phase,
      ambientOn: ambientOn ?? this.ambientOn,
      pausedUntil: identical(pausedUntil, _keep) ? this.pausedUntil : pausedUntil as DateTime?,
      feed: feed ?? this.feed,
      lastTranscript: identical(lastTranscript, _keep) ? this.lastTranscript : lastTranscript as String?,
      status: status ?? this.status,
      modelReady: modelReady ?? this.modelReady,
      modelDownloading: modelDownloading ?? this.modelDownloading,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

/// Capa de aplicación: une escucha → transcripción → contexto → decisión → salida.
class AgentOrchestrator extends Notifier<AgentState> {
  static const _uuid = Uuid();

  StreamSubscription<SpeechSegment>? _segmentSub;
  Timer? _maintenanceTimer;
  Timer? _queryTimeout;
  Timer? _pauseTimer;

  final List<SpeechSegment> _queue = [];
  bool _processing = false;
  bool _queryPending = false;
  bool _micForQueryOnly = false;
  bool _resumeAmbientAfterPause = false;
  bool _batteryAsked = false;
  List<ProactivityRule> _rules = const [];

  // ---- Dependencias ----
  AppSettings get _settings => ref.read(settingsProvider);
  LocalDatabase get _db => ref.read(localDatabaseProvider);
  SttEngine get _stt => ref.read(sttEngineProvider);

  AgentPhase get _restingPhase => state.ambientOn ? AgentPhase.ambient : AgentPhase.idle;
  String get _restingStatus => state.ambientOn
      ? 'Escuchando el ambiente'
      : state.isPaused
          ? 'En pausa hasta las ${DateFormat('HH:mm').format(state.pausedUntil!)}'
          : 'Tocá el orbe para hablarme';

  @override
  AgentState build() {
    ref.onDispose(_dispose);
    Future.microtask(_init);
    return const AgentState();
  }

  Future<void> _init() async {
    try {
      _rules = await _db.rules();
      final feed = await _db.recentFeed();
      state = state.copyWith(feed: feed, modelReady: ref.read(sttEngineProvider).isReady);

      final tts = ref.read(ttsProvider);
      tts.onStart = () {
        ref.read(listeningServiceProvider).suspended = true;
        state = state.copyWith(phase: AgentPhase.speaking, status: 'Hablando… (tocá para interrumpir)');
      };
      tts.onDone = () {
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          ref.read(listeningServiceProvider).suspended = false;
        });
        state = state.copyWith(phase: _restingPhase, status: _restingStatus);
      };
      await tts.init();

      final notifications = ref.read(notificationServiceProvider);
      notifications.onAction = (String decisionId, String action) {
        if (action == 'useful' || action == 'not_useful') feedback(decisionId, action);
      };
      await notifications.init();

      _segmentSub = ref.read(listeningServiceProvider).segments.listen(_onSegment);
      _maintenanceTimer = Timer.periodic(const Duration(minutes: 5), (_) => _runMaintenance());
      unawaited(_db.purgeOlderThan(_settings.retentionDays));
    } catch (e, st) {
      JLog.e('agent', e, st);
      state = state.copyWith(error: 'Error al iniciar: $e');
    }
  }

  void _dispose() {
    _segmentSub?.cancel();
    _maintenanceTimer?.cancel();
    _queryTimeout?.cancel();
    _pauseTimer?.cancel();
  }

  // =====================================================================
  //  Permisos y modelo
  // =====================================================================

  Future<bool> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      state = state.copyWith(error: 'Necesito permiso de micrófono para escucharte.');
      return false;
    }
    await Permission.notification.request();
    final loc = await Permission.locationWhenInUse.request();
    final cal = await Permission.calendarFullAccess.request();
    final ctx = ref.read(contextCollectorProvider);
    ctx.locationEnabled = loc.isGranted;
    ctx.calendarEnabled = cal.isGranted;
    return true;
  }

  Future<bool> ensureModel() async {
    final stt = ref.read(sttEngineProvider);
    if (stt.isReady) {
      if (!state.modelReady) state = state.copyWith(modelReady: true);
      return true;
    }
    if (state.modelDownloading) return false;
    state = state.copyWith(modelDownloading: true, status: 'Descargando modelo de voz (solo la primera vez)…', error: null);
    try {
      await stt.warmUp();
      state = state.copyWith(modelReady: true, modelDownloading: false, status: _restingStatus);
      return true;
    } catch (e, st) {
      JLog.e('agent', e, st);
      state = state.copyWith(
        modelDownloading: false,
        status: _restingStatus,
        error: 'No pude descargar el modelo de voz. Conectate a Wi-Fi y probá de nuevo.',
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);

  // =====================================================================
  //  Escucha ambiente / pausa
  // =====================================================================

  Future<void> setAmbient(bool on) async {
    final listening = ref.read(listeningServiceProvider);
    final ctx = ref.read(contextCollectorProvider);
    if (on) {
      if (!_settings.consentAccepted) {
        state = state.copyWith(error: 'Primero aceptá el aviso de privacidad.');
        return;
      }
      if (!await _ensurePermissions()) return;
      if (!await ensureModel()) return;

      _pauseTimer?.cancel();
      _resumeAmbientAfterPause = false;
      await ForegroundServiceController.start(withLocation: ctx.locationEnabled);
      listening.vad.sensitivity = _settings.vadSensitivity;
      listening.profile = ListeningProfile.ambient;
      final ok = await listening.start();
      if (!ok) {
        await ForegroundServiceController.stop();
        state = state.copyWith(error: 'No pude abrir el micrófono.');
        return;
      }
      ctx.startSensors();
      _micForQueryOnly = false;
      state = state.copyWith(ambientOn: true, pausedUntil: null, phase: AgentPhase.ambient, status: 'Escuchando el ambiente', error: null);
      if (!_batteryAsked) {
        _batteryAsked = true;
        unawaited(ForegroundServiceController.requestBatteryExemption());
      }
    } else {
      await listening.stop();
      await ctx.stopSensors();
      await ForegroundServiceController.stop();
      ref.read(decisionEngineProvider).clear();
      for (final s in _queue) {
        s.wipe();
      }
      _queue.clear();
      state = state.copyWith(ambientOn: false, phase: AgentPhase.idle);
      state = state.copyWith(status: _restingStatus);
    }
  }

  /// Corta el micrófono de verdad (no solo silencia) durante [duration].
  Future<void> pauseFor(Duration duration) async {
    final wasOn = state.ambientOn;
    await setAmbient(false);
    _resumeAmbientAfterPause = wasOn;
    final until = DateTime.now().add(duration);
    state = state.copyWith(pausedUntil: until);
    state = state.copyWith(status: _restingStatus);
    _pauseTimer?.cancel();
    _pauseTimer = Timer(duration, resumeFromPause);
  }

  Future<void> resumeFromPause() async {
    _pauseTimer?.cancel();
    state = state.copyWith(pausedUntil: null);
    if (_resumeAmbientAfterPause) {
      _resumeAmbientAfterPause = false;
      await setAmbient(true);
    } else {
      state = state.copyWith(status: _restingStatus);
    }
  }

  // =====================================================================
  //  Orbe: consulta conversacional
  // =====================================================================

  Future<void> onOrbTap() async {
    HapticFeedback.mediumImpact();
    final tts = ref.read(ttsProvider);
    if (tts.isSpeaking) {
      await tts.stop(); // interrumpir al asistente
      return;
    }
    if (_queryPending) {
      await _endQuery('Consulta cancelada.');
      return;
    }
    if (!await _ensurePermissions()) return;
    if (!await ensureModel()) return;

    final listening = ref.read(listeningServiceProvider);
    listening.profile = ListeningProfile.query;
    listening.suspended = false;
    if (!listening.isRunning) {
      final ok = await listening.start();
      if (!ok) {
        state = state.copyWith(error: 'No pude abrir el micrófono.');
        return;
      }
      _micForQueryOnly = true;
    }
    _queryPending = true;
    state = state.copyWith(phase: AgentPhase.capturing, status: 'Te escucho…', error: null);
    _queryTimeout?.cancel();
    _queryTimeout = Timer(const Duration(seconds: 12), () {
      if (_queryPending) _endQuery('No te escuché. Tocá el orbe y hablame.');
    });
  }

  Future<void> _endQuery(String message) async {
    _queryPending = false;
    _queryTimeout?.cancel();
    await _releaseQueryMic();
    state = state.copyWith(phase: _restingPhase, status: message);
  }

  Future<void> _releaseQueryMic() async {
    final listening = ref.read(listeningServiceProvider);
    listening.profile = ListeningProfile.ambient;
    if (_micForQueryOnly && !state.ambientOn) {
      await listening.stop();
    }
    _micForQueryOnly = false;
  }

  // =====================================================================
  //  Pipeline de segmentos
  // =====================================================================

  void _onSegment(SpeechSegment segment) {
    if (_queryPending) {
      _queryPending = false;
      _queryTimeout?.cancel();
      unawaited(_handleQuery(segment));
      return;
    }
    if (!state.ambientOn) {
      segment.wipe();
      return;
    }
    // Protegemos batería y latencia: si se acumulan, se descartan los más viejos.
    if (_queue.length >= 4) _queue.removeAt(0).wipe();
    _queue.add(segment);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        await _processAmbient(_queue.removeAt(0));
      }
    } finally {
      _processing = false;
    }
  }

  static final _directAddress = RegExp(r'^\s*(oye |hey |che |ey )?jarvis[\s,.:!¿?]+', caseSensitive: false);

  Future<void> _processAmbient(SpeechSegment segment) async {
    try {
      final startedAt = segment.startedAt;
      final text = await _stt.transcribe(segment); // destruye el audio
      if (text.split(' ').where((w) => w.isNotEmpty).length < 3) return;
      final redacted = PiiRedactor.redact(text);

      if (_directAddress.hasMatch(redacted)) {
        await _answer(redacted.replaceFirst(_directAddress, ''));
        return;
      }

      final ctx = await ref.read(contextCollectorProvider).snapshot();
      final id = _uuid.v4();
      await _db.insertContextEvent(
        id: id,
        at: startedAt,
        transcript: redacted,
        context: {
          'motion': ctx.motion,
          if (ctx.currentEvent != null) 'event': ctx.currentEvent!.title,
        },
      );
      state = state.copyWith(lastTranscript: redacted);

      final decision = await ref.read(decisionEngineProvider).evaluate(
            line: TranscriptLine(id: id, at: startedAt, text: redacted),
            ctx: ctx,
            settings: _settings,
            rules: _rules,
            recall: (q) => ref.read(memoryRepositoryProvider).recall(q, k: 4),
          );
      if (decision == null) return;
      await _db.insertDecision(decision);
      await _sideEffects(decision);
      await _deliver(decision);
    } catch (e, st) {
      JLog.e('agent', e, st);
    }
  }

  Future<void> _sideEffects(AgentDecision d) async {
    final integrations = ref.read(integrationsProvider);
    for (final t in d.tasks) {
      final taskId = _uuid.v4();
      await _db.insertTask(id: taskId, title: t.title, due: t.due, owner: t.owner, decisionId: d.id);
      await integrations.emit(JarvisEventType.taskDetected, {'task_id': taskId, 'decision_id': d.id, ...t.toJson()});
    }
    final mem = d.memory;
    if (mem != null) {
      final memoryId = await ref.read(memoryRepositoryProvider).remember(mem.fact, importance: mem.importance);
      await integrations.emit(JarvisEventType.memoryStored, {'memory_id': memoryId, 'fact': mem.fact, 'importance': mem.importance});
    }
    if (d.delivery != Delivery.none) {
      await integrations.emit(
        d.category == 'opportunity' ? JarvisEventType.opportunityDetected : JarvisEventType.alertRaised,
        {
          'decision_id': d.id,
          'category': d.category,
          'priority': d.priority.name,
          'confidence': d.confidence,
          'headline': d.headline,
          'message': d.message,
          'delivery': d.delivery.name,
          'suggested_actions': d.suggestedActions,
        },
      );
    }
  }

  Future<void> _deliver(AgentDecision d) async {
    if (d.delivery == Delivery.none) return;
    await _addFeed(FeedItem(
      id: _uuid.v4(),
      kind: _kindFor(d.category),
      title: d.headline.isEmpty ? 'Jarvis' : d.headline,
      body: d.message,
      createdAt: DateTime.now(),
      priority: d.priority.name,
      refId: d.id,
    ));
    final critical = d.priority == DecisionPriority.critical;
    switch (d.delivery) {
      case Delivery.voice:
        HapticFeedback.heavyImpact();
        // Notificación silenciosa como registro + voz inmediata.
        await ref.read(notificationServiceProvider).show(
              title: '${_emoji(d.category)} ${d.headline}',
              body: d.message,
              decisionId: d.id,
              critical: critical,
              silent: true,
            );
        await ref.read(ttsProvider).speak(d.message);
      case Delivery.push:
        await ref.read(notificationServiceProvider).show(
              title: '${_emoji(d.category)} ${d.headline}',
              body: d.message,
              decisionId: d.id,
              critical: critical,
            );
      case Delivery.feed:
      case Delivery.none:
        break;
    }
  }

  // =====================================================================
  //  Consultas
  // =====================================================================

  Future<void> _handleQuery(SpeechSegment segment) async {
    state = state.copyWith(phase: AgentPhase.transcribing, status: 'Procesando…');
    final raw = await _stt.transcribe(segment);
    await _releaseQueryMic();
    if (raw.trim().isEmpty) {
      state = state.copyWith(phase: _restingPhase, status: 'No te entendí. Probá de nuevo.');
      return;
    }
    await _answer(PiiRedactor.redact(raw));
  }

  static final _intentSummary = RegExp(r'(resumen|resumí|resumime|cómo me fue|como me fue)', caseSensitive: false);
  static final _intentPause = RegExp(r'(silencio|callate|pausa|dejá de escuchar|deja de escuchar)', caseSensitive: false);

  Future<void> _answer(String question) async {
    final tts = ref.read(ttsProvider);
    state = state.copyWith(phase: AgentPhase.thinking, status: 'Pensando…', lastTranscript: '“$question”');
    try {
      if (_intentPause.hasMatch(question)) {
        await pauseFor(const Duration(hours: 1));
        await tts.speak('Listo, dejo de escuchar por una hora.');
        return;
      }
      if (!ref.read(llmProvider).isConfigured) {
        await _speakOrShow(_settings.cloudEnabled
            ? 'Todavía no tengo cerebro en la nube. Cargá tu API key de Gemini en Ajustes.'
            : 'Estás en modo privado: no puedo consultar la nube.');
        return;
      }
      if (_intentSummary.hasMatch(question)) {
        await generateSummary(speak: true);
        return;
      }
      final ctx = await ref.read(contextCollectorProvider).snapshot();
      final answer = await AnswerQuery(
        db: _db,
        llm: ref.read(llmProvider),
        memory: ref.read(memoryRepositoryProvider),
      ).call(question, _settings, ctx);
      await _addFeed(FeedItem(
        id: _uuid.v4(),
        kind: FeedKind.answer,
        title: question.length > 60 ? '${question.substring(0, 57)}…' : question,
        body: answer,
        createdAt: DateTime.now(),
        priority: 'low',
      ));
      await _speakOrShow(answer);
    } catch (e, st) {
      JLog.e('agent', e, st);
      await _speakOrShow('No pude conectarme. Revisá internet o tu API key.');
    } finally {
      if (!tts.isSpeaking) state = state.copyWith(phase: _restingPhase, status: _restingStatus);
    }
  }

  Future<void> _speakOrShow(String text) async {
    state = state.copyWith(status: text.length > 90 ? '${text.substring(0, 87)}…' : text);
    if (_settings.voiceEnabled) await ref.read(ttsProvider).speak(text);
  }

  // =====================================================================
  //  Resúmenes, feedback y mantenimiento
  // =====================================================================

  Future<DailySummary?> generateSummary({bool speak = false}) async {
    if (!ref.read(llmProvider).isConfigured) {
      state = state.copyWith(error: 'Configurá una API key (Gemini o Groq) en Ajustes para generar resúmenes.');
      return null;
    }
    final prevPhase = state.phase;
    state = state.copyWith(phase: AgentPhase.thinking, status: 'Generando tu resumen ejecutivo…');
    try {
      final summary = await GenerateDailySummary(
        db: _db,
        llm: ref.read(llmProvider),
        memory: ref.read(memoryRepositoryProvider),
      ).call(_settings);
      await _addFeed(FeedItem(
        id: _uuid.v4(),
        kind: FeedKind.summary,
        title: 'Resumen del día',
        body: summary.headline,
        createdAt: DateTime.now(),
        priority: 'medium',
        refId: summary.date,
      ));
      await ref.read(integrationsProvider).emit(JarvisEventType.summaryGenerated, {'date': summary.date, ...summary.content});
      ref.invalidate(latestSummaryProvider);
      unawaited(_syncCloud());
      state = state.copyWith(phase: prevPhase == AgentPhase.thinking ? _restingPhase : prevPhase, status: _restingStatus);
      if (speak && _settings.voiceEnabled) await ref.read(ttsProvider).speak(summary.spokenBrief);
      return summary;
    } catch (e, st) {
      JLog.e('agent', e, st);
      state = state.copyWith(phase: _restingPhase, status: _restingStatus, error: 'No pude generar el resumen: revisá la conexión o la API key.');
      return null;
    }
  }

  Future<void> feedback(String decisionId, String value) async {
    await _db.setDecisionFeedback(decisionId, value);
    final feed = [
      for (final f in state.feed) f.refId == decisionId ? f.copyWith(feedback: value) : f,
    ];
    for (final f in feed.where((f) => f.refId == decisionId)) {
      await _db.setFeedFeedback(f.id, value);
    }
    state = state.copyWith(feed: feed);
  }

  Future<void> dismiss(String feedId) async {
    await _db.dismissFeed(feedId);
    state = state.copyWith(feed: state.feed.where((f) => f.id != feedId).toList());
  }

  Future<List<ProactivityRule>> rules() async => _rules = await _db.rules();

  Future<void> setRuleEnabled(String id, bool enabled) async {
    await _db.setRuleEnabled(id, enabled);
    _rules = await _db.rules();
  }

  Future<void> onSettingsChanged() async {
    ref.read(listeningServiceProvider).vad.sensitivity = _settings.vadSensitivity;
  }

  /// Calcula embeddings pendientes y después sube lo pendiente a Firebase (si está activo).
  Future<void> _syncCloud() async {
    await ref.read(memoryRepositoryProvider).indexPending();
    await ref.read(cloudSyncProvider).pushPending();
  }

  /// Borra la copia en Firebase. Lo local queda marcado como pendiente de subir.
  Future<bool> wipeCloudData() async {
    final ok = await ref.read(cloudSyncProvider).wipeRemote();
    if (ok) await _db.markAllUnsynced();
    return ok;
  }

  Future<void> wipeAllData() async {
    await _db.wipeAll();
    ref.read(decisionEngineProvider).clear();
    state = state.copyWith(feed: const [], lastTranscript: null);
    ref.invalidate(latestSummaryProvider);
  }

  Future<void> _runMaintenance() async {
    try {
      unawaited(ref.read(integrationsProvider).dispatchPending());
      unawaited(_syncCloud());

      final now = DateTime.now();
      final s = _settings;
      if (now.hour >= s.summaryHour && ref.read(llmProvider).isConfigured) {
        final today = DateFormat('yyyy-MM-dd').format(now);
        final existing = await _db.summaryFor(today);
        final events = await _db.contextEventsSince(DateTime(now.year, now.month, now.day), limit: 5);
        if (existing == null && events.length >= 3) {
          final summary = await generateSummary();
          if (summary != null) {
            await ref.read(notificationServiceProvider).show(
                  title: '📋 Tu resumen del día está listo',
                  body: summary.headline,
                  decisionId: 'summary:${summary.date}',
                );
          }
        }
      }
    } catch (e, st) {
      JLog.e('agent', e, st);
    }
  }

  Future<void> _addFeed(FeedItem item) async {
    await _db.insertFeed(item);
    state = state.copyWith(feed: [item, ...state.feed].take(80).toList());
  }

  static FeedKind _kindFor(String category) => switch (category) {
        'opportunity' => FeedKind.opportunity,
        'task' || 'commitment' || 'reminder' => FeedKind.task,
        'query' => FeedKind.answer,
        'insight' => FeedKind.info,
        _ => FeedKind.alert,
      };

  static String _emoji(String category) => switch (category) {
        'opportunity' => '💼',
        'risk' => '⚠️',
        'error' => '⛔',
        'task' || 'commitment' => '📌',
        'reminder' => '⏰',
        _ => '🤖',
      };
}

final agentProvider = NotifierProvider<AgentOrchestrator, AgentState>(AgentOrchestrator.new);
