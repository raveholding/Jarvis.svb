import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/agent_orchestrator.dart';
import '../../core/theme/app_theme.dart';

/// Botón central "orbe": reacciona al volumen de la voz y cambia de color
/// según el estado del agente (reposo, escucha, pensamiento, habla).
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.phase,
    required this.level,
    required this.onTap,
    this.onLongPress,
    this.size = 240,
    this.paused = false,
  });

  final AgentPhase phase;
  final double level;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;
  final bool paused;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  double _smoothLevel = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (Color, Color) get _palette {
    if (widget.paused) return (JColors.muted, JColors.surfaceHigh);
    return switch (widget.phase) {
      AgentPhase.idle => (JColors.cyanDeep, const Color(0xFF0B1F33)),
      AgentPhase.ambient => (JColors.cyan, JColors.cyanDeep),
      AgentPhase.capturing => (Colors.white, JColors.cyan),
      AgentPhase.transcribing => (JColors.cyan, JColors.violet),
      AgentPhase.thinking => (JColors.violet, const Color(0xFF3B1E7A)),
      AgentPhase.speaking => (JColors.teal, JColors.cyanDeep),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (primary, secondary) = _palette;
    return Semantics(
      button: true,
      label: 'Orbe de voz de Jarvis. Tocá para hablar o para interrumpir.',
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final target = switch (widget.phase) {
                AgentPhase.thinking || AgentPhase.transcribing => 0.35 + 0.15 * math.sin(_controller.value * math.pi * 8),
                AgentPhase.speaking => 0.45 + 0.25 * math.sin(_controller.value * math.pi * 14).abs(),
                _ => widget.level,
              };
              _smoothLevel = _smoothLevel * 0.82 + target * 0.18;
              return CustomPaint(
                painter: _OrbPainter(
                  t: _controller.value,
                  level: _smoothLevel,
                  primary: primary,
                  secondary: secondary,
                  active: widget.phase != AgentPhase.idle && !widget.paused,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.level,
    required this.primary,
    required this.secondary,
    required this.active,
  });

  final double t;
  final double level;
  final Color primary;
  final Color secondary;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width * 0.27;
    final r = base * (1 + level * 0.18);

    // Halo
    canvas.drawCircle(
      c,
      r * 1.9,
      Paint()
        ..shader = RadialGradient(colors: [
          primary.withValues(alpha: active ? 0.22 + level * 0.2 : 0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.9)),
    );

    // Ondas
    for (var ring = 0; ring < 3; ring++) {
      final path = Path();
      final amp = (active ? 3 + level * 20 : 1.5) * (1 - ring * 0.25);
      final rr = r * (1.12 + ring * 0.16);
      final speed = (ring.isEven ? 1 : -1) * (1 + ring * 0.5);
      const steps = 120;
      for (var i = 0; i <= steps; i++) {
        final a = i / steps * math.pi * 2;
        final wobble = math.sin(a * (3 + ring) + t * math.pi * 2 * speed) * amp +
            math.sin(a * (5 + ring * 2) - t * math.pi * 2 * speed * 1.3) * amp * 0.4;
        final p = c + Offset(math.cos(a), math.sin(a)) * (rr + wobble);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 - ring * 0.35
          ..color = primary.withValues(alpha: (active ? 0.75 : 0.35) - ring * 0.18),
      );
    }

    // Núcleo
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [primary.withValues(alpha: 0.95), secondary, const Color(0xFF02040A)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Brillo interior
    canvas.drawCircle(
      c.translate(-r * 0.28, -r * 0.32),
      r * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.10 + level * 0.15),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.level != level || old.primary != primary || old.active != active;
}
