/// Eventos públicos que Jarvis emite para sistemas externos (ERP, CRM, n8n, Zapier...).
enum JarvisEventType {
  taskDetected('onTaskDetected'),
  alertRaised('onAlertRaised'),
  opportunityDetected('onOpportunityDetected'),
  summaryGenerated('onSummaryGenerated'),
  memoryStored('onMemoryStored');

  const JarvisEventType(this.wireName);
  final String wireName;
}

class IntegrationEvent {
  const IntegrationEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.data,
  });

  final String id;
  final JarvisEventType type;
  final DateTime occurredAt;
  final Map<String, dynamic> data;

  /// Contrato estable v1 (ver docs/INTEGRACIONES.md).
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wireName,
        'version': '1.0',
        'source': 'jarvis.svb',
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'data': data,
      };
}
