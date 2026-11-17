import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/app_settings.dart';

/// Persistencia cifrada (Android Keystore) de preferencias y API keys.
class SettingsStore {
  SettingsStore(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'jarvis_settings_v1';

  Future<AppSettings> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      JLog.e('settings', e, st);
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));
}
