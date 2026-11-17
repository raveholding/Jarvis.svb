# Integraciones (webhooks y eventos)

Jarvis funciona 100 % autónomo. Cuando quieras conectarlo a un ERP, CRM, n8n, Make, Zapier o a un sistema propio de Vincular Business, cargá una URL `https://` en **Ajustes → Integraciones**.

## Eventos

| Evento | Cuándo | `data` |
|---|---|---|
| `onTaskDetected` | Se detecta un compromiso o tarea | `task_id, decision_id, title, due, owner` |
| `onAlertRaised` | Interrupción por riesgo, error, compromiso o recordatorio | `decision_id, category, priority, confidence, headline, message, delivery, suggested_actions` |
| `onOpportunityDetected` | Oportunidad de negocio | igual que `onAlertRaised` |
| `onSummaryGenerated` | Resumen diario listo | `date, headline, key_points, risks, tasks, advice, ...` |
| `onMemoryStored` | Se guarda un recuerdo de largo plazo | `memory_id, fact, importance` |

## Sobre (envelope) v1

```json
{
  "id": "b2c1…",
  "type": "onTaskDetected",
  "version": "1.0",
  "source": "jarvis.svb",
  "occurred_at": "2026-11-17T13:42:20.000Z",
  "data": { "title": "Enviar cotización 40 uniformes", "due": "2026-11-20T10:00:00.000", "owner": "me" }
}
```

## Encabezados y firma

```
X-Jarvis-Event:      onTaskDetected
X-Jarvis-Delivery:   <id del evento, usalo para idempotencia>
X-Jarvis-Timestamp:  1763386940
X-Jarvis-Signature:  sha256=<HMAC_SHA256(secreto, timestamp + "." + body)>
```

Verificación en Node.js:

```js
import crypto from 'node:crypto';
const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(`${ts}.${rawBody}`).digest('hex');
const ok = crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(req.headers['x-jarvis-signature']));
```

## Garantías de entrega

- Patrón **outbox**: el evento se guarda cifrado en el teléfono antes de enviarse.
- Reintentos exponenciales: 30 s, 1, 2, 4, 8 y 16 min; después pasa a `dead`.
- Entrega **al menos una vez**: deduplicá por `X-Jarvis-Delivery`.
- Con el respaldo en Firebase activado, los eventos también se copian a `users/{uid}/events` en Firestore (base para un panel web o para entregarlos desde Cloud Functions).

## Destino personalizado en código

```dart
class MiErpSink implements IntegrationSink {
  @override String get id => 'mi_erp';
  @override bool get enabled => true;
  @override Future<void> deliver(IntegrationEvent e) async { /* llamar a tu API */ }
}
ref.read(integrationsProvider).registerSink(MiErpSink());
```
