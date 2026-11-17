import '../../core/config/app_config.dart';

/// Preferencias del usuario. Se guardan cifradas en Secure Storage.
class AppSettings {
  const AppSettings({
    this.userName = '',
    this.userRole = '',
    this.userGoals = '',
    this.geminiApiKey = '',
    this.groqApiKey = '',
    this.geminiFastModel = AppConfig.defaultGeminiFast,
    this.geminiSmartModel = AppConfig.defaultGeminiSmart,
    this.groqFastModel = AppConfig.defaultGroqFast,
    this.groqSmartModel = AppConfig.defaultGroqSmart,
    this.cloudBackupEnabled = false,
    this.webhookUrl = '',
    this.webhookSecret = '',
    this.whisperModel = 'base',
    this.vadSensitivity = 0.5,
    this.proactivity = 0.5,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
    this.summaryHour = 21,
    this.voiceEnabled = true,
    this.cloudEnabled = true,
    this.retentionDays = 14,
    this.consentAccepted = false,
  });

  final String userName;
  final String userRole;
  final String userGoals;

  final String geminiApiKey;
  final String groqApiKey;
  final String geminiFastModel;
  final String geminiSmartModel;
  final String groqFastModel;
  final String groqSmartModel;

  /// Respaldo opcional en Firebase (Firestore). Apagado por defecto.
  final bool cloudBackupEnabled;

  final String webhookUrl;
  final String webhookSecret;

  /// tiny | base | small
  final String whisperModel;

  /// 0 = solo voces fuertes y cercanas, 1 = capta todo.
  final double vadSensitivity;

  /// 0 = casi nunca interrumpe, 1 = interrumpe ante cualquier señal.
  final double proactivity;

  final int quietStartHour;
  final int quietEndHour;
  final int summaryHour;
  final bool voiceEnabled;

  /// false = "modo privado": ningún texto sale del teléfono.
  final bool cloudEnabled;
  final int retentionDays;
  final bool consentAccepted;

  bool get hasLlm => geminiApiKey.trim().isNotEmpty || groqApiKey.trim().isNotEmpty;
  bool get hasCloudBackup => cloudEnabled && cloudBackupEnabled;
  bool get hasWebhook => webhookUrl.trim().startsWith('https://');
  String get displayName => userName.trim().isEmpty ? 'el usuario' : userName.trim();

  bool isQuietHour(DateTime t) {
    if (quietStartHour == quietEndHour) return false;
    final h = t.hour;
    return quietStartHour > quietEndHour
        ? (h >= quietStartHour || h < quietEndHour)
        : (h >= quietStartHour && h < quietEndHour);
  }

  AppSettings copyWith({
    String? userName,
    String? userRole,
    String? userGoals,
    String? geminiApiKey,
    String? groqApiKey,
    String? geminiFastModel,
    String? geminiSmartModel,
    String? groqFastModel,
    String? groqSmartModel,
    bool? cloudBackupEnabled,
    String? webhookUrl,
    String? webhookSecret,
    String? whisperModel,
    double? vadSensitivity,
    double? proactivity,
    int? quietStartHour,
    int? quietEndHour,
    int? summaryHour,
    bool? voiceEnabled,
    bool? cloudEnabled,
    int? retentionDays,
    bool? consentAccepted,
  }) {
    return AppSettings(
      userName: userName ?? this.userName,
      userRole: userRole ?? this.userRole,
      userGoals: userGoals ?? this.userGoals,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      groqApiKey: groqApiKey ?? this.groqApiKey,
      geminiFastModel: geminiFastModel ?? this.geminiFastModel,
      geminiSmartModel: geminiSmartModel ?? this.geminiSmartModel,
      groqFastModel: groqFastModel ?? this.groqFastModel,
      groqSmartModel: groqSmartModel ?? this.groqSmartModel,
      cloudBackupEnabled: cloudBackupEnabled ?? this.cloudBackupEnabled,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      webhookSecret: webhookSecret ?? this.webhookSecret,
      whisperModel: whisperModel ?? this.whisperModel,
      vadSensitivity: vadSensitivity ?? this.vadSensitivity,
      proactivity: proactivity ?? this.proactivity,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      summaryHour: summaryHour ?? this.summaryHour,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      cloudEnabled: cloudEnabled ?? this.cloudEnabled,
      retentionDays: retentionDays ?? this.retentionDays,
      consentAccepted: consentAccepted ?? this.consentAccepted,
    );
  }

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'userRole': userRole,
        'userGoals': userGoals,
        'geminiApiKey': geminiApiKey,
        'groqApiKey': groqApiKey,
        'geminiFastModel': geminiFastModel,
        'geminiSmartModel': geminiSmartModel,
        'groqFastModel': groqFastModel,
        'groqSmartModel': groqSmartModel,
        'cloudBackupEnabled': cloudBackupEnabled,
        'webhookUrl': webhookUrl,
        'webhookSecret': webhookSecret,
        'whisperModel': whisperModel,
        'vadSensitivity': vadSensitivity,
        'proactivity': proactivity,
        'quietStartHour': quietStartHour,
        'quietEndHour': quietEndHour,
        'summaryHour': summaryHour,
        'voiceEnabled': voiceEnabled,
        'cloudEnabled': cloudEnabled,
        'retentionDays': retentionDays,
        'consentAccepted': consentAccepted,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    String s(String k, String def) => (j[k] as String?) ?? def;
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    bool b(String k, bool def) => (j[k] as bool?) ?? def;
    return AppSettings(
      userName: s('userName', d.userName),
      userRole: s('userRole', d.userRole),
      userGoals: s('userGoals', d.userGoals),
      geminiApiKey: s('geminiApiKey', d.geminiApiKey),
      groqApiKey: s('groqApiKey', d.groqApiKey),
      geminiFastModel: s('geminiFastModel', d.geminiFastModel),
      geminiSmartModel: s('geminiSmartModel', d.geminiSmartModel),
      groqFastModel: s('groqFastModel', d.groqFastModel),
      groqSmartModel: s('groqSmartModel', d.groqSmartModel),
      cloudBackupEnabled: b('cloudBackupEnabled', d.cloudBackupEnabled),
      webhookUrl: s('webhookUrl', d.webhookUrl),
      webhookSecret: s('webhookSecret', d.webhookSecret),
      whisperModel: s('whisperModel', d.whisperModel),
      vadSensitivity: n('vadSensitivity', d.vadSensitivity),
      proactivity: n('proactivity', d.proactivity),
      quietStartHour: i('quietStartHour', d.quietStartHour),
      quietEndHour: i('quietEndHour', d.quietEndHour),
      summaryHour: i('summaryHour', d.summaryHour),
      voiceEnabled: b('voiceEnabled', d.voiceEnabled),
      cloudEnabled: b('cloudEnabled', d.cloudEnabled),
      retentionDays: i('retentionDays', d.retentionDays),
      consentAccepted: b('consentAccepted', d.consentAccepted),
    );
  }
}
