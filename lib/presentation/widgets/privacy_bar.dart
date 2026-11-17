import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Controles rápidos de privacidad: escucha ambiente, pausa y modo privado.
class PrivacyBar extends StatelessWidget {
  const PrivacyBar({
    super.key,
    required this.ambientOn,
    required this.paused,
    required this.privateMode,
    required this.onAmbientChanged,
    required this.onPauseTap,
    required this.onPrivateChanged,
  });

  final bool ambientOn;
  final bool paused;
  final bool privateMode;
  final ValueChanged<bool> onAmbientChanged;
  final VoidCallback onPauseTap;
  final ValueChanged<bool> onPrivateChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          avatar: Icon(ambientOn ? Icons.hearing_rounded : Icons.hearing_disabled_rounded, size: 18,
              color: ambientOn ? JColors.cyan : JColors.textSecondary),
          label: Text(ambientOn ? 'Escucha activa' : 'Escucha apagada'),
          selected: ambientOn,
          showCheckmark: false,
          onSelected: onAmbientChanged,
        ),
        FilterChip(
          avatar: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18,
              color: paused ? JColors.amber : JColors.textSecondary),
          label: Text(paused ? 'Reanudar' : 'Pausa 1 h'),
          selected: paused,
          showCheckmark: false,
          onSelected: (_) => onPauseTap(),
        ),
        FilterChip(
          avatar: Icon(privateMode ? Icons.shield_rounded : Icons.cloud_outlined, size: 18,
              color: privateMode ? JColors.green : JColors.textSecondary),
          label: Text(privateMode ? 'Modo privado' : 'Nube activa'),
          selected: privateMode,
          showCheckmark: false,
          onSelected: onPrivateChanged,
        ),
      ],
    );
  }
}
