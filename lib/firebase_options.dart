import 'package:firebase_core/firebase_core.dart';

/// Configuración del proyecto Firebase `jarvis-svb` (app Android
/// `com.vincularbusiness.jarvis_svb`).
///
/// Estos valores identifican al proyecto; NO son secretos (viajan dentro de
/// cualquier APK). Lo que protege los datos son las reglas de `firestore.rules`.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDw0cdM5XhN707eZTb4HXMAfZJjGZg3NtA',
    appId: '1:285439197921:android:56b7c32156d9d1f5ededa0',
    messagingSenderId: '285439197921',
    projectId: 'jarvis-svb',
    storageBucket: 'jarvis-svb.firebasestorage.app',
  );
}
