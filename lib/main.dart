import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'core/di/providers.dart';
import 'data/local/local_database.dart';
import 'data/local/settings_store.dart';
import 'services/background/foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Canal entre el servicio en primer plano y la UI.
  FlutterForegroundTask.initCommunicationPort();
  ForegroundServiceController.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF05070D),
    statusBarIconBrightness: Brightness.light,
  ));

  const storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final settings = await SettingsStore(storage).load();
  final db = LocalDatabase(storage);
  await db.open();

  runApp(ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      localDatabaseProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(settings),
    ],
    child: const JarvisApp(),
  ));
}
