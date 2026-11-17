import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/utils/logger.dart';

/// Notificaciones push locales accionables (👍 útil / descartar).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 100;

  /// (decisionId, actionId) → el orquestador registra feedback.
  void Function(String decisionId, String actionId)? onAction;

  static const _channelId = 'jarvis_alerts';

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (resp) {
          final payload = resp.payload;
          if (payload != null) onAction?.call(payload, resp.actionId ?? 'open');
        },
      );
      _ready = true;
    } catch (e, st) {
      JLog.e('notif', e, st);
    }
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> show({
    required String title,
    required String body,
    required String decisionId,
    bool critical = false,
    bool silent = false,
  }) async {
    await init();
    try {
      await _plugin.show(
        _nextId++,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Alertas de Jarvis',
            channelDescription: 'Oportunidades, riesgos y compromisos detectados',
            importance: critical ? Importance.max : Importance.high,
            priority: critical ? Priority.max : Priority.high,
            category: AndroidNotificationCategory.reminder,
            silent: silent,
            styleInformation: BigTextStyleInformation(body),
            actions: const [
              AndroidNotificationAction('useful', '👍 Útil'),
              AndroidNotificationAction('not_useful', 'No me sirvió'),
            ],
          ),
        ),
        payload: decisionId,
      );
    } catch (e, st) {
      JLog.e('notif', e, st);
    }
  }
}
