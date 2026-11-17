import '../../core/config/app_config.dart';
import '../../domain/entities/agent_decision.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/context_snapshot.dart';

/// Capa determinística que tiene la última palabra sobre el LLM.
/// El modelo PROPONE; esta política DISPONE (confianza, cooldown, contexto, duplicados).
class InterruptionPolicy {
  const InterruptionPolicy();

  AgentDecision apply(
    AgentDecision d, {
    required ContextSnapshot ctx,
    required AppSettings settings,
    required List<AgentDecision> recent,
    DateTime? lastInterruptionAt,
  }) {
    if (d.action == DecisionAction.silence || d.message.trim().isEmpty) {
      return d.copyWith(action: DecisionAction.silence, delivery: Delivery.none);
    }

    final critical = d.priority == DecisionPriority.critical;
    final high = d.priority.index >= DecisionPriority.high.index;

    // 1) Umbral de confianza según el nivel de proactividad elegido.
    final minConfidence = 0.80 - 0.25 * settings.proactivity; // 0.55 .. 0.80
    if (d.confidence < minConfidence && !critical) {
      return d.copyWith(delivery: Delivery.none, rationale: '${d.rationale} [policy: confianza baja]');
    }

    // 2) Anti-repetición.
    final now = ctx.now;
    for (final r in recent) {
      if (now.difference(r.createdAt) > AppConfig.dedupeWindow) continue;
      if (r.category == d.category && _similar(r.headline + r.message, d.headline + d.message) > 0.5) {
        return d.copyWith(delivery: Delivery.none, rationale: '${d.rationale} [policy: duplicado]');
      }
    }

    var delivery = d.action == DecisionAction.speak ? Delivery.voice : Delivery.push;

    // 3) Cooldown entre interrupciones por voz.
    final inCooldown = lastInterruptionAt != null && now.difference(lastInterruptionAt) < AppConfig.interruptionCooldown;
    if (inCooldown && delivery == Delivery.voice && !critical) delivery = Delivery.push;

    // 4) Reunión → nada de voz salvo crítico.
    if (ctx.inMeeting && delivery == Delivery.voice && !critical) delivery = Delivery.push;

    // 5) Manejando → voz para lo importante, lo menor queda en el feed.
    if (ctx.isDriving) {
      if (high) {
        delivery = Delivery.voice;
      } else {
        delivery = Delivery.feed;
      }
    }

    // 6) Horario silencioso → solo críticos interrumpen.
    if (settings.isQuietHour(now) && !critical) {
      delivery = high ? Delivery.push : Delivery.feed;
    }

    // 7) Voz desactivada por el usuario.
    if (!settings.voiceEnabled && delivery == Delivery.voice) delivery = Delivery.push;

    // 8) Prioridad baja nunca interrumpe.
    if (d.priority == DecisionPriority.low) delivery = Delivery.feed;

    return d.copyWith(delivery: delivery);
  }

  /// Similitud de Jaccard sobre palabras significativas.
  static double _similar(String a, String b) {
    Set<String> words(String s) => s
        .toLowerCase()
        .split(RegExp(r'[^a-záéíóúñü0-9]+'))
        .where((w) => w.length > 3)
        .toSet();
    final wa = words(a), wb = words(b);
    if (wa.isEmpty || wb.isEmpty) return 0;
    return wa.intersection(wb).length / wa.union(wb).length;
  }
}
