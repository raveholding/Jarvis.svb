# Jarvis SVB

**Agente de IA proactivo y contextual para Android.** Escucha el ambiente, entiende lo que pasa en tu día y te interrumpe solo cuando importa: una venta que se puede escapar, un compromiso con fecha, un riesgo de estafa, una tarea olvidada. A la noche te arma un resumen ejecutivo con mentoría basada en tus propios patrones.

> Desarrollado por **Vincular Business** · WhatsApp (387) 4484132 · vincularbusiness@gmail.com

## Cómo funciona en 10 segundos

```
🎙 mic → VAD (local) → Whisper (local) → anonimización → contexto (GPS, movimiento, agenda)
      → motor de decisión (pre-filtro local + Gemini Flash + política) → 🔊 voz | 🔔 push | 🗂 feed
      → memoria cifrada local + Supabase/pgvector → eventos webhook para tu ERP/CRM
```

- **El audio nunca sale del teléfono.** Se transcribe localmente y el buffer se destruye.
- **Silencio por defecto.** Tres capas deciden si vale la pena interrumpirte.
- **Offline-first.** SQLCipher (AES-256) local; la nube es opcional.
- **Listo para integrarse.** Eventos `onTaskDetected`, `onSummaryGenerated` y más, firmados con HMAC.

## Stack (100 % gratuito o freemium)

| Pieza | Tecnología |
|---|---|
| App | Flutter 3 · Riverpod · Material 3 modo oscuro |
| Detección de voz | VAD adaptativo estilo WebRTC (Dart, < 1 % CPU) |
| Transcripción | whisper.cpp vía `whisper_ggml` (modelos tiny/base/small) |
| Cerebro | Gemini 2.5 Flash-Lite / Flash (con cadena de respaldo) · Groq Llama 3 |
| Memoria | SQLCipher local + Supabase PostgreSQL + pgvector (HNSW) |
| Voz | `flutter_tts` nativo |
| Segundo plano | Foreground Service tipo `microphone` |

## Empezar

👉 **[Guía de despliegue rápido](docs/DESPLIEGUE.md)**: instalar el APK desde el celular o armar el entorno en Windows.

## Documentación

- [Arquitectura y diagrama completo](docs/ARQUITECTURA.md)
- [Motor de decisión y System Prompt](docs/MOTOR_DE_DECISION.md)
- [Integraciones y webhooks](docs/INTEGRACIONES.md)
- [Esquema SQL de Supabase](supabase/migrations/0001_jarvis_init.sql)

## Estructura

```
lib/
├── main.dart                      # bootstrap: DB cifrada, ajustes, servicio en primer plano
├── app.dart
├── core/                          # config, tema, DI (Riverpod), utilidades (PII, WAV, JSON)
├── domain/                        # entidades y contratos puros (sin Flutter ni proveedores)
│   ├── entities/
│   └── repositories/
├── data/                          # implementaciones: SQLCipher, Secure Storage, Gemini, Groq, Supabase
│   ├── local/
│   ├── remote/
│   └── repositories/
├── services/                      # audio+VAD, Whisper, sensores, motor de decisión, TTS, push, webhooks
│   ├── audio/  stt/  context/  decision/  output/  integrations/  background/
├── application/                   # orquestador del agente + casos de uso
│   └── usecases/
└── presentation/                  # pantallas y widgets (orbe, feed, privacidad, resumen, ajustes)
supabase/migrations/               # SQL (pgvector, RLS, RPC de búsqueda semántica)
tool/setup_android.dart            # permisos y configuración de Android (idempotente)
.github/workflows/android.yml      # compila y publica el APK en cada push
test/                              # tests de privacidad, VAD y política de interrupción
```

## Uso responsable

Jarvis escucha conversaciones donde hay otras personas. Avisales que usás un asistente y no lo actives donde no corresponde. Ver el aviso dentro de la app y la Ley 25.326 de Protección de Datos Personales.
