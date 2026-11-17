# Guía de despliegue rápido

Hay dos caminos. El **A** te deja probar en el celular hoy mismo, sin instalar nada en la PC.

---

## Camino A · Instalar el APK ya compilado (5 minutos, desde el celular)

1. En el celular abrí **github.com/raveholding/Jarvis.svb → Releases** y descargá `app-release.apk` de la última versión.
2. Abrí el archivo. Android te va a pedir permitir "Instalar apps desconocidas" para el navegador: aceptá.
3. Si aparece Play Protect, elegí "Instalar de todos modos" (la app no está en Play Store todavía).
4. Abrí **Jarvis SVB → Ajustes (ícono arriba a la derecha)**:
   - Cargá tu nombre, a qué te dedicás y tus objetivos.
   - Pegá tu **Gemini API key** (ver más abajo) y tocá **Probar conexión**.
   - Con Wi-Fi, tocá **Descargar modelo ahora** (142 MB, una sola vez).
   - Tocá **GUARDAR**.
5. **Probalo:**
   - Tocá el orbe y preguntale: *"¿Qué tengo pendiente hoy?"*
   - Mantené apretado el orbe (o el chip "Escucha apagada") para activar la **escucha ambiente**. Aceptá el aviso de privacidad y los permisos.
   - Decí en voz alta: *"Dale, el jueves sin falta te mando el presupuesto de los 40 uniformes."* En unos segundos te tendría que llegar una alerta.
6. Si usás un Xiaomi, Samsung o Motorola: **Ajustes del teléfono → Batería → Jarvis SVB → Sin restricciones**. Si no, el sistema puede cortar la escucha con la pantalla apagada.

Cada vez que se sube código a `main`, GitHub compila un APK nuevo y lo publica en Releases.

---

## Camino B · Entorno de desarrollo en Windows

### 1. Instalar herramientas (una sola vez)

1. **Git**: https://git-scm.com/download/win
2. **Android Studio**: https://developer.android.com/studio. Al abrirlo, en *More Actions → SDK Manager*:
   - SDK Platforms: **Android 15 (API 35)** o el más nuevo.
   - SDK Tools: **Android SDK Command-line Tools**, **NDK (Side by side)**, **CMake**.
3. **Flutter**: https://docs.flutter.dev/get-started/install/windows/mobile. Descomprimí en `C:\src\flutter` y agregá `C:\src\flutter\bin` al **PATH** (Inicio → "variables de entorno").
4. En PowerShell:
   ```powershell
   flutter doctor --android-licenses   # aceptá todo con "y"
   flutter doctor                      # todo en verde salvo Visual Studio (no hace falta)
   ```

### 2. Bajar y preparar el proyecto

```powershell
cd $HOME\Documents
git clone https://github.com/raveholding/Jarvis.svb.git
cd Jarvis.svb
flutter pub get
```

Si la carpeta `android/` todavía no existe en el repo (la genera el CI en la primera compilación):

```powershell
flutter create --platforms=android --org com.vincularbusiness --project-name jarvis_svb .
del test\widget_test.dart
dart run tool/setup_android.dart
```

### 3. Conectar el celular

1. En el celular: **Ajustes → Acerca del teléfono → tocá 7 veces "Número de compilación"**.
2. **Ajustes → Sistema → Opciones de desarrollador → Depuración USB: activada**.
3. Conectalo por USB y aceptá "Permitir depuración".
4. `flutter devices` tiene que listar tu teléfono.

### 4. Ejecutar

```powershell
flutter run --release        # recomendado: Whisper es mucho más lento en modo debug
```

Para generar el APK: `flutter build apk --release --target-platform android-arm64` → queda en `build\app\outputs\flutter-apk\app-release.apk`.

---

## Claves gratuitas

### Gemini (obligatoria para el cerebro)
1. Entrá a https://aistudio.google.com con tu cuenta de Google.
2. **Get API key → Create API key**. Copiala y pegala en Ajustes.
3. La capa gratuita alcanza de sobra para uso personal. El motor solo llama a la IA cuando el pre-filtro local detecta algo relevante.

### Groq (opcional, respaldo)
1. https://console.groq.com → registrate (sin tarjeta).
2. **API Keys → Create API Key** → pegala en Ajustes.
3. Si Gemini falla o se queda sin cuota, Jarvis usa Llama en Groq automáticamente.

---

## Firebase (opcional: respaldo en la nube)

La memoria y la búsqueda semántica funcionan en el teléfono. Firebase solo guarda una copia.

**Ya está configurado**: proyecto `jarvis-svb` (plan Spark, gratis), app Android `com.vincularbusiness.jarvis_svb`,
Authentication con proveedor **Anónimo** y Cloud Firestore en `southamerica-east1` (São Paulo).

- Para usarlo: **Ajustes → Respaldo en la nube → Respaldar en Firebase**. No hay que pegar ninguna clave.
- Qué sube: texto anonimizado, decisiones, tareas, memorias (con embedding) y resúmenes, bajo `users/{uid}/...`. Nunca audio.
- **Borrar mi copia en la nube** elimina todo lo que subió ese teléfono.
- Las reglas viven en `firestore.rules`. Si las cambiás: `firebase deploy --only firestore:rules` (o pegalas en la consola → Firestore → Reglas).
- La configuración de `lib/firebase_options.dart` identifica al proyecto y no es secreta; la seguridad la dan las reglas.

> El usuario es anónimo: si desinstalás la app, la copia en la nube queda huérfana (no se puede recuperar desde otro teléfono).
> Para restaurar entre dispositivos hay que sumar inicio de sesión con Google (pendiente en el roadmap).
> Nunca pongas una clave de cuenta de servicio de Firebase en la app ni en el repo.

---

## Firma del APK

Los APK se firman con `android/app/dev-signing.jks`, una clave de **desarrollo** incluida en el repo para que cada versión nueva se instale encima de la anterior sin perder datos.
Como el repo es público, **antes de publicar en Play Store** generá una clave privada (`keytool -genkey ...`), guardala fuera del repo y configurala en `android/key.properties`.

---

## Problemas comunes

| Síntoma | Solución |
|---|---|
| "No pude descargar el modelo de voz" | Conectate a Wi-Fi; el modelo base pesa 142 MB. Probá con *Tiny* en Ajustes. |
| La escucha se corta con la pantalla apagada | Batería → Sin restricciones para Jarvis SVB. |
| "Probar conexión" da 400/403 | La API key está mal copiada o no está habilitada. Generá otra. |
| "Probar conexión" da 404 | El modelo fue retirado: Jarvis prueba los alternativos solo; podés cambiarlo en *Modelos avanzados*. |
| 429 | Llegaste al límite gratuito por minuto; cargá Groq como respaldo. |
| Transcribe mal | Subí la sensibilidad o pasá al modelo *Small* (más lento). Hablá a menos de un metro. |
| Habla en otro acento | Ajustes del teléfono → Texto a voz → instalá la voz "Español (Estados Unidos)" o "Español (España)". |
