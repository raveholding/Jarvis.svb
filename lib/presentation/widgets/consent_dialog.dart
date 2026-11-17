import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Aviso de privacidad obligatorio antes de activar la escucha ambiente.
Future<bool> showConsentDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: JColors.surface,
      title: const Text('Antes de escuchar el ambiente'),
      content: const SingleChildScrollView(
        child: Text(
          'Cómo protege Jarvis tu privacidad:\n\n'
          '• El audio se transcribe en tu teléfono y se destruye al instante. Nunca se sube a internet.\n'
          '• Antes de usar la nube se borran teléfonos, DNI, CUIT, CBU, tarjetas, emails y claves.\n'
          '• Mientras escucha, verás siempre una notificación fija. Podés pausar o apagar con un toque.\n'
          '• Los datos locales están cifrados (AES-256) y se borran solos después del plazo que elijas.\n\n'
          'Tu responsabilidad:\n\n'
          'Las conversaciones incluyen a otras personas. Avisá a clientes, empleados o familiares que '
          'usás un asistente que escucha, y no lo actives donde no corresponde (consultas médicas, '
          'reuniones confidenciales, lugares donde está prohibido grabar). La ley argentina de protección '
          'de datos personales (Ley 25.326) protege a terceros.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Entiendo y acepto')),
      ],
    ),
  );
  return result ?? false;
}
