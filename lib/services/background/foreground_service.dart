import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/utils/logger.dart';

/// El servicio en primer plano mantiene vivo el proceso (y el micrófono) con la
/// pantalla apagada. Android 14+ exige el tipo "microphone" y una notificación visible:
/// es también el indicador de privacidad permanente para el usuario.
@pragma('vm:entry-point')
void jarvisForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ForegroundServiceController {
  ForegroundServiceController._();

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'jarvis_listening',
        channelName: 'Escucha activa',
        channelDescription: 'Indica que Jarvis está escuchando. El audio nunca sale del teléfono.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> start({required bool withLocation}) async {
    try {
      if (await FlutterForegroundTask.isRunningService) return true;
      final result = await FlutterForegroundTask.startService(
        serviceId: 4132,
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          if (withLocation) ForegroundServiceTypes.location,
        ],
        notificationTitle: 'Jarvis está escuchando',
        notificationText: 'El audio se procesa en tu teléfono y se destruye al instante.',
        callback: jarvisForegroundCallback,
      );
      return result is ServiceRequestSuccess;
    } catch (e, st) {
      JLog.e('fgs', e, st);
      return false;
    }
  }

  static Future<void> update(String title, String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
    }
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> requestBatteryExemption() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}
