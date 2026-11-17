# Arquitectura · Jarvis SVB

## 1. Diagrama de flujo completo

```
┌──────────────────────────────── TELÉFONO (Edge · privado) ────────────────────────────────┐
│                                                                                            │
│  🎙 Micrófono ──PCM16 16kHz──▶ ListeningService ──frames 30ms──▶ AdaptiveEnergyVad          │
│  (record + Foreground Service "microphone")          │                 (RMS + ZCR + piso   │
│                                                      │                  de ruido adaptativo)│
│                                         ¿voz? ──no──▶ descarta (0 CPU extra, 0 red)         │
│                                                      │ sí                                   │
│                                                      ▼                                      │
│                                   SpeechSegment (RAM, pre-roll 300ms, corte por silencio)   │
│                                                      │                                      │
│                                                      ▼                                      │
│                                  WhisperSttEngine (whisper.cpp GGML, 100% local)            │
│                                      │  WAV temporal → sobrescrito con ceros → borrado      │
│                                      │  buffer.wipe()  ◀── el AUDIO MUERE ACÁ               │
│                                      ▼                                                      │
│                                 PiiRedactor  (TEL, DNI, CUIT, CBU, TARJETA, EMAIL, CLAVE)    │
│                                      │                                                      │
│      📍 GPS (geolocator) ┐           ▼                                                      │
│      📳 Acelerómetro ────┼──▶ ContextCollector ──▶ ContextSnapshot {hora, agenda, movimiento}│
│      📅 Agenda (device)  ┘           │                                                      │
│                                      ▼                                                      │
│                    ┌──────── DecisionEngine ──────────────────────────────┐                 │
│                    │ Etapa 1 · Pre-filtro local (gatillos + reglas +      │                 │
│                    │           ventana de 6 min + throttle) ── no ─▶ calla│                 │
│                    │ Etapa 2 · LLM rápido + SYSTEM PROMPT del motor ──────┼──▶ ☁ Gemini     │
│                    │           (JSON estricto)                ◀───────────┼──   Flash-Lite  │
│                    │                                          (fallback)  │    ☁ Groq Llama │
│                    │ Etapa 3 · InterruptionPolicy determinística          │                 │
│                    │   confianza · duplicados · cooldown · reunión ·      │                 │
│                    │   manejando · horario silencioso                     │                 │
│                    └───────────────┬──────────────────────────────────────┘                 │
│                                    │                                                        │
│        ┌───────────────┬───────────┼────────────────┬──────────────────────┐                │
│        ▼               ▼           ▼                ▼                      ▼                │
│   🔊 TTS nativo   🔔 Push accion. 🗂 Feed UI    📌 Tareas / 🧠 Memoria   📡 IntegrationsService│
│   (voz ≤20 pal.)  (👍/👎 feedback)              (SQLCipher AES-256)     (bus + OUTBOX local) │
│                                                     │                         │             │
└─────────────────────────────────────────────────────┼─────────────────────────┼─────────────┘
                                                      │ HTTPS + JWT (anónimo)   │ HTTPS + HMAC
                                                      ▼                         ▼
                              ┌────────── SUPABASE (capa gratuita) ──────────┐  ERP / CRM / n8n
                              │ context_logs · decisions · tasks             │  (webhooks
                              │ memories (pgvector HNSW) ◀── match_memories()│   onTaskDetected,
                              │ daily_summaries · proactivity_rules          │   onSummaryGenerated…)
                              │ webhook_queue ──(pg_net opcional)──▶ destinos│
                              └──────────────────────────────────────────────┘

  Orbe (UI) ──tap──▶ captura 1 frase ──▶ Whisper ──▶ AnswerQuery (contexto del día + memoria
                                                     vectorial + tareas) ──▶ LLM ──▶ TTS
  Resumen diario (21 h o a pedido) ──▶ GenerateDailySummary ──▶ LLM "smart" ──▶ patrones → memoria
```

## 2. Capas (Clean Architecture)

| Capa | Carpeta | Responsabilidad | Depende de |
|---|---|---|---|
| Dominio | `lib/domain` | Entidades puras y contratos (`LlmRepository`, `MemoryRepository`, `IntegrationSink`) | nada |
| Datos | `lib/data` | SQLCipher, Secure Storage, Gemini, Groq, Supabase | dominio |
| Servicios | `lib/services` | Audio/VAD, Whisper, sensores, motor de decisión, TTS, notificaciones, integraciones | dominio, datos |
| Aplicación | `lib/application` | Orquestador y casos de uso (resumen, consulta) | todo lo anterior |
| Presentación | `lib/presentation` | Pantallas y widgets (Riverpod) | aplicación |

El dominio no conoce Flutter, Supabase ni Gemini. Cambiar de proveedor = nueva implementación del contrato.

## 3. Decisiones de diseño clave

- **Silencio por defecto, en tres capas.** El pre-filtro local evita ~80 % de las llamadas al LLM (batería, cuota gratuita, latencia). El LLM propone; la política determinística decide. Así una alucinación del modelo nunca te habla en medio de una reunión.
- **Privacidad por diseño.** El audio solo existe en RAM y en un WAV temporal que se sobrescribe con ceros. A la nube va texto anonimizado. "Modo privado" corta toda salida a internet.
- **Offline-first.** Todo se guarda primero en SQLCipher. La sincronización con Supabase y los webhooks usan colas con reintentos exponenciales.
- **Event-driven.** Cada hecho relevante es un evento versionado (`jarvis.svb` · `v1.0`). Ver `INTEGRACIONES.md`.
- **Fallback de modelos.** Si un modelo de Gemini se retira (404), el router prueba la siguiente opción de la cadena y, si falla la cuota, cae a Groq.

## 4. Mejoras previstas (roadmap)

1. **Silero VAD (ONNX)**: reemplazar `AdaptiveEnergyVad` implementando `VoiceActivityDetector`. Mejor en ambientes ruidosos (comercio, calle).
2. **Reconocimiento del hablante** ("solo mi voz"): embeddings de voz locales para no procesar conversaciones de terceros.
3. **Transcripción en streaming** con `transcribeLive` de whisper_ggml para bajar latencia de consultas.
4. **Isolate dedicado** para el pipeline, para que siga vivo aunque se cierre la app desde recientes.
5. **Panel web** (Supabase + Next.js) para editar reglas y ver métricas de `decision_quality`.
6. **Aprendizaje por feedback**: usar 👍/👎 para ajustar umbrales por categoría.
