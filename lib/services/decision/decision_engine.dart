import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/agent_decision.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/context_snapshot.dart';
import '../../domain/entities/proactivity_rule.dart';
import '../../domain/repositories/llm_repository.dart';
import 'decision_prompts.dart';
import 'interruption_policy.dart';

class TranscriptLine {
  const TranscriptLine({required this.id, required this.at, required this.text});
  final String id;
  final DateTime at;
  final String text;
}

/// Motor de decisión en 3 etapas:
///  1. Pre-filtro local (gratis, instantáneo): ¿vale la pena gastar una llamada al LLM?
///  2. LLM rápido con el System Prompt del motor (JSON estricto).
///  3. Política determinística de interrupción.
class DecisionEngine {
  DecisionEngine({required LlmRepository llm, InterruptionPolicy policy = const InterruptionPolicy()})
      : _llm = llm,
        _policy = policy;

  final LlmRepository _llm;
  final InterruptionPolicy _policy;
  static const _uuid = Uuid();

  final List<TranscriptLine> _window = [];
  final List<AgentDecision> _recentInterruptions = [];
  DateTime? _lastLlmCall;
  DateTime? _lastInterruptionAt;
  int _wordsSinceEval = 0;
  bool _busy = false;

  /// Gatillos genéricos (además de las palabras de cada regla).
  static final _globalTriggers = RegExp(
    r'(jarvis|urgente|importante|no te olvides|acordate|recordame|prometo|te prometo|sin falta|problema|estafa)',
    caseSensitive: false,
  );

  List<TranscriptLine> get window => List.unmodifiable(_window);

  Future<AgentDecision?> evaluate({
    required TranscriptLine line,
    required ContextSnapshot ctx,
    required AppSettings settings,
    required List<ProactivityRule> rules,
    required Future<List<String>> Function(String query) recall,
  }) async {
    _window.add(line);
    _window.removeWhere((l) => ctx.now.difference(l.at) > AppConfig.transcriptWindow);
    _wordsSinceEval += line.text.split(' ').length;

    if (!_llm.isConfigured || _busy) return null;

    // ---------- Etapa 1: pre-filtro local ----------
    final lower = line.text.toLowerCase();
    final activeRules = rules.where((r) => r.enabled).toList();
    final matched = activeRules.where((r) => r.matches(lower)).toList();
    final triggered = matched.isNotEmpty || _globalTriggers.hasMatch(lower);
    final sinceLast = _lastLlmCall == null ? const Duration(days: 1) : ctx.now.difference(_lastLlmCall!);

    final shouldEval = triggered
        ? sinceLast >= AppConfig.triggerEvalInterval
        : (sinceLast >= AppConfig.minEvalInterval && _wordsSinceEval >= 25);
    if (!shouldEval) return null;

    _busy = true;
    _lastLlmCall = ctx.now;
    _wordsSinceEval = 0;
    try {
      final memories = await recall(line.text);
      final fmt = DateFormat('HH:mm:ss');
      final payload = {
        'schema': DecisionPrompts.schemaVersion,
        'contexto': {
          ...ctx.toPromptJson(),
          'horario_silencioso': settings.isQuietHour(ctx.now),
        },
        'reglas_activas': activeRules.map((r) => {'regla': r.name, 'descripcion': r.description, 'prioridad': r.priority}).toList(),
        'reglas_gatilladas': matched.map((r) => r.name).toList(),
        'interrupciones_recientes': _recentInterruptions
            .take(5)
            .map((d) => {'hora': DateFormat('HH:mm').format(d.createdAt), 'titulo': d.headline, 'categoria': d.category})
            .toList(),
        'memoria_relevante': memories,
        'conversacion_reciente': _window
            .where((l) => l.id != line.id)
            .toList()
            .reversed
            .take(12)
            .toList()
            .reversed
            .map((l) => '[${fmt.format(l.at)}] ${l.text}')
            .toList(),
        'fragmento_nuevo': '[${fmt.format(line.at)}] ${line.text}',
      };

      final json = await _llm.completeJson(
        system: DecisionPrompts.decisionSystem(settings),
        user: jsonEncode(payload),
        tier: LlmTier.fast,
      );
      final proposed = AgentDecision.fromLlmJson(json, id: _uuid.v4(), contextEventId: line.id);

      // ---------- Etapa 3: política ----------
      final finalDecision = _policy.apply(
        proposed,
        ctx: ctx,
        settings: settings,
        recent: _recentInterruptions,
        lastInterruptionAt: _lastInterruptionAt,
      );
      if (finalDecision.delivery != Delivery.none && finalDecision.delivery != Delivery.feed) {
        _lastInterruptionAt = ctx.now;
      }
      if (finalDecision.delivery != Delivery.none) {
        _recentInterruptions.insert(0, finalDecision);
        if (_recentInterruptions.length > 10) _recentInterruptions.removeLast();
      }
      return finalDecision;
    } catch (e, st) {
      JLog.e('decision', e, st);
      return null;
    } finally {
      _busy = false;
    }
  }

  void clear() {
    _window.clear();
    _wordsSinceEval = 0;
  }
}
