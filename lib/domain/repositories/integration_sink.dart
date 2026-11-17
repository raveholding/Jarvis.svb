import '../entities/integration_event.dart';

/// Destino "plug & play" de eventos. Agregar un ERP/CRM = implementar esta interfaz.
abstract interface class IntegrationSink {
  String get id;
  bool get enabled;
  Future<void> deliver(IntegrationEvent event);
}
