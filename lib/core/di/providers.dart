import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/local/local_database.dart';
import '../../data/local/settings_store.dart';
import '../../data/remote/llm_router.dart';
import '../../data/remote/firebase_sync.dart';
import '../../data/repositories/memory_repository_impl.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/daily_summary.dart';
import '../../domain/repositories/llm_repository.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../services/audio/listening_service.dart';
import '../../services/context/context_collector.dart';
import '../../services/decision/decision_engine.dart';
import '../../services/integrations/integrations_service.dart';
import '../../services/output/notification_service.dart';
import '../../services/output/tts_service.dart';
import '../../services/stt/stt_engine.dart';
import '../../services/stt/whisper_stt_engine.dart';

// ---------------- Infraestructura (se inyectan en main.dart) ----------------

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
);

final localDatabaseProvider = Provider<LocalDatabase>(
  (_) => throw UnimplementedError('Se inyecta en main()'),
);

final initialSettingsProvider = Provider<AppSettings>((_) => const AppSettings());

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore(ref.read(secureStorageProvider)));

// ---------------- Configuración ----------------

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> save(AppSettings next) async {
    state = next;
    await ref.read(settingsStoreProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ---------------- Datos ----------------

final llmProvider = Provider<LlmRepository>((ref) => LlmRouter(settings: () => ref.read(settingsProvider)));

final cloudSyncProvider = Provider<FirebaseSync>((ref) => FirebaseSync(
      db: ref.read(localDatabaseProvider),
      settings: () => ref.read(settingsProvider),
    ));

final memoryRepositoryProvider = Provider<MemoryRepository>(
  (ref) => MemoryRepositoryImpl(ref.read(localDatabaseProvider), ref.read(llmProvider)),
);

// ---------------- Servicios ----------------

final listeningServiceProvider = Provider<ListeningService>((ref) {
  final s = ListeningService();
  ref.onDispose(s.dispose);
  return s;
});

final sttEngineProvider = Provider<SttEngine>(
  (ref) => WhisperSttEngine(modelName: () => ref.read(settingsProvider).whisperModel),
);

final contextCollectorProvider = Provider<ContextCollector>((_) => ContextCollector());

final decisionEngineProvider = Provider<DecisionEngine>((ref) => DecisionEngine(llm: ref.read(llmProvider)));

final ttsProvider = Provider<TtsService>((_) => TtsService());

final notificationServiceProvider = Provider<NotificationService>((_) => NotificationService());

final integrationsProvider = Provider<IntegrationsService>((ref) => IntegrationsService(
      db: ref.read(localDatabaseProvider),
      settings: () => ref.read(settingsProvider),
      cloud: ref.read(cloudSyncProvider),
    ));

// ---------------- Lecturas para la UI ----------------

final latestSummaryProvider = FutureProvider.autoDispose<DailySummary?>(
  (ref) => ref.read(localDatabaseProvider).latestSummary(),
);

/// Nivel de audio para animar el orbe (separado del estado para no reconstruir toda la UI).
final audioLevelProvider = StreamProvider.autoDispose<double>(
  (ref) => ref.read(listeningServiceProvider).levels,
);
