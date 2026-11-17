# Motor de decisión

El System Prompt vive en código: [`lib/services/decision/decision_prompts.dart`](../lib/services/decision/decision_prompts.dart) → `DecisionPrompts.decisionSystem()`.
Se arma en cada llamada con el nombre, el rol y los objetivos que el usuario cargó en Ajustes.

## Qué recibe el LLM (mensaje de usuario, JSON)

```json
{
  "schema": "jarvis.decision.v1",
  "contexto": {
    "fecha_hora": "2026-11-17 10:42",
    "dia_semana": "martes",
    "movimiento": "quieto",
    "en_reunion": false,
    "agenda_proxima": [{"title": "Proveedor bebidas", "start": "12:00"}],
    "horario_silencioso": false
  },
  "reglas_activas": [{"regla": "Oportunidad de venta", "descripcion": "...", "prioridad": "high"}],
  "reglas_gatilladas": ["Oportunidad de venta"],
  "interrupciones_recientes": [{"hora": "10:15", "titulo": "Cotización uniformes", "categoria": "commitment"}],
  "memoria_relevante": ["Cliente Carlos compra al por mayor los viernes."],
  "conversacion_reciente": ["[10:41:50] ...", "[10:42:03] ..."],
  "fragmento_nuevo": "[10:42:20] ¿cuánto me sale la caja de 12 si me llevo cinco?"
}
```

## Qué devuelve (contrato estricto)

```json
{
  "decision": "notify",
  "priority": "high",
  "category": "opportunity",
  "confidence": 0.82,
  "headline": "Venta mayorista: 5 cajas",
  "message": "Te piden precio por 5 cajas de 12. Ofrecé el precio mayorista.",
  "rationale": "Intención clara de compra por volumen.",
  "detected_tasks": [],
  "memory": {"store": true, "fact": "Cliente consultó por 5 cajas de 12.", "importance": 0.5},
  "suggested_actions": ["Pasar precio mayorista"]
}
```

## Política determinística (después del LLM)

| Regla | Efecto |
|---|---|
| Confianza < 0.80 − 0.25 × proactividad (y no crítica) | No interrumpe |
| Misma categoría + texto similar en los últimos 20 min | No repite |
| Menos de 4 min desde la última voz (no crítica) | Voz → notificación |
| Evento de agenda en curso (no crítica) | Voz → notificación |
| Manejando | Alta/crítica → voz corta; el resto → solo feed |
| Horario silencioso (no crítica) | Alta → notificación; el resto → feed |
| Voz desactivada | Voz → notificación |
| Prioridad baja | Solo feed |

Probado en `test/core_test.dart`.

## Cómo afinarlo

1. Ajustá **Proactividad** en Ajustes (mueve el umbral de confianza).
2. Activá o desactivá **reglas** según tu negocio.
3. Marcá 👍/👎 en las tarjetas; en Supabase la vista `decision_quality` te muestra el % de alertas útiles por categoría.
4. Editá las secciones "CUÁNDO INTERRUMPIR" y los ejemplos del prompt para tu rubro.
