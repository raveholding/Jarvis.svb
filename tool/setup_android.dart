// Prepara la carpeta android/ generada por `flutter create` con los permisos,
// el servicio en primer plano y la configuración que necesita Jarvis.
// Es idempotente: se puede correr las veces que quieras.
//
// Uso (desde la raíz del proyecto):  dart run tool/setup_android.dart
import 'dart:io';

void main() {
  _patchManifest();
  _patchGradle();
  _writeProguard();
  stdout.writeln('✔ Android listo para Jarvis SVB');
}

const _permissions = [
  'android.permission.INTERNET',
  'android.permission.RECORD_AUDIO',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_MICROPHONE',
  'android.permission.FOREGROUND_SERVICE_LOCATION',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.WAKE_LOCK',
  'android.permission.VIBRATE',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.READ_CALENDAR',
  'android.permission.WRITE_CALENDAR',
  'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
];

void _patchManifest() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    stderr.writeln('No existe ${file.path}. Corré antes: flutter create --platforms=android .');
    exit(1);
  }
  var m = file.readAsStringSync();

  final missing = _permissions.where((p) => !m.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final lines = missing.map((p) => '    <uses-permission android:name="$p"/>').join('\n');
    m = m.replaceFirstMapped(RegExp(r'<manifest[^>]*>'), (match) => '${match[0]}\n$lines');
  }

  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Jarvis SVB"');

  if (!m.contains('flutter_foreground_task.service.ForegroundService')) {
    m = m.replaceFirst(
      '</application>',
      '''
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="microphone|location"
            android:exported="false" />
    </application>''',
    );
  }

  if (!m.contains('android.intent.action.TTS_SERVICE')) {
    const tts = '''
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>''';
    if (m.contains('<queries>')) {
      m = m.replaceFirst('<queries>', '<queries>$tts');
    } else {
      m = m.replaceFirst('</manifest>', '    <queries>$tts\n    </queries>\n</manifest>');
    }
  }

  file.writeAsStringSync(m);
  stdout.writeln('  · AndroidManifest.xml');
}

void _patchGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : groovy;
  if (!file.existsSync()) {
    stderr.writeln('No se encontró android/app/build.gradle(.kts)');
    exit(1);
  }
  final isKts = file.path.endsWith('.kts');
  var g = file.readAsStringSync();

  // minSdk 26 (Android 8): requerido por whisper.cpp, servicio de micrófono y SQLCipher.
  g = g.replaceAll(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = 26');
  g = g.replaceAll(RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'), 'minSdkVersion 26');

  // Lint "vital" de release falla dentro de plugins de terceros (bug conocido de AGP).
  if (!g.contains('checkReleaseBuilds')) {
    g = g.replaceFirst(
      RegExp(r'android\s*\{'),
      isKts
          ? 'android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }'
          : 'android {\n    lint {\n        checkReleaseBuilds false\n        abortOnError false\n    }',
    );
  }

  // Core library desugaring (requerido por flutter_local_notifications).
  if (!g.contains('CoreLibraryDesugaringEnabled')) {
    g = g.replaceFirst(
      RegExp(r'compileOptions\s*\{'),
      isKts ? 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true' : 'compileOptions {\n        coreLibraryDesugaringEnabled true',
    );
  }
  if (!g.contains('desugar_jdk_libs')) {
    g += isKts
        ? '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'
        : "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'\n}\n";
  }

  file.writeAsStringSync(g);
  stdout.writeln('  · ${file.path}');
}

void _writeProguard() {
  final file = File('android/app/proguard-rules.pro');
  const rules = '''
# Jarvis SVB — reglas R8
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class com.dexterous.** { *; }
-dontwarn net.sqlcipher.**
-dontwarn net.zetetic.**
''';
  if (!file.existsSync() || !file.readAsStringSync().contains('Jarvis SVB')) {
    file.writeAsStringSync(rules);
    stdout.writeln('  · proguard-rules.pro');
  }
}
