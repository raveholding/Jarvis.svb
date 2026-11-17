/// Regla de proactividad: palabras gatillo + pista para el LLM.
class ProactivityRule {
  const ProactivityRule({
    required this.id,
    required this.name,
    required this.description,
    required this.keywords,
    this.priority = 'medium',
    this.enabled = true,
  });

  final String id;
  final String name;

  /// Se envía al LLM como pista de lo que importa.
  final String description;
  final List<String> keywords;
  final String priority;
  final bool enabled;

  bool matches(String lowerText) => keywords.any((k) => lowerText.contains(k));

  ProactivityRule copyWith({bool? enabled}) => ProactivityRule(
        id: id,
        name: name,
        description: description,
        keywords: keywords,
        priority: priority,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'description': description,
        'keywords': keywords.join('|'),
        'priority': priority,
        'enabled': enabled ? 1 : 0,
      };

  factory ProactivityRule.fromRow(Map<String, Object?> r) => ProactivityRule(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        keywords: ((r['keywords'] as String?) ?? '').split('|').where((k) => k.isNotEmpty).toList(),
        priority: (r['priority'] as String?) ?? 'medium',
        enabled: (r['enabled'] as int? ?? 1) == 1,
      );

  /// Reglas iniciales pensadas para un comercio / emprendedor.
  static const defaults = <ProactivityRule>[
    ProactivityRule(
      id: 'commitment',
      name: 'Compromisos con fecha',
      description: 'El usuario promete algo con plazo ("te lo mando mañana", "el lunes te paso").',
      keywords: ['mañana', 'te paso', 'te mando', 'te llamo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'semana que viene'],
      priority: 'high',
    ),
    ProactivityRule(
      id: 'sales',
      name: 'Oportunidad de venta',
      description: 'Un cliente pregunta precio, stock, presupuesto o muestra intención de compra.',
      keywords: ['presupuesto', 'cotiz', 'precio', 'cuánto sale', 'cuanto sale', 'cuánto cuesta', 'stock', 'pedido', 'seña'],
      priority: 'high',
    ),
    ProactivityRule(
      id: 'money',
      name: 'Plata y vencimientos',
      description: 'Deudas, cobros pendientes, vencimientos, facturas, aumentos de proveedores.',
      keywords: ['deuda', 'debe', 'vence', 'vencimiento', 'factura', 'cobrar', 'pagar', 'transferencia', 'aumento'],
      priority: 'high',
    ),
    ProactivityRule(
      id: 'fraud',
      name: 'Riesgo de estafa',
      description: 'Pedido de códigos, claves, transferencias urgentes a cuentas nuevas, presión para pagar ya.',
      keywords: ['código', 'codigo', 'clave', 'contraseña', 'cbu', 'alias', 'urgente', 'ya mismo'],
      priority: 'critical',
    ),
    ProactivityRule(
      id: 'complaint',
      name: 'Reclamos y problemas',
      description: 'Cliente molesto, producto fallado, error en un pedido o cobro.',
      keywords: ['reclamo', 'problema', 'no anda', 'roto', 'error', 'me cobraste', 'devolución', 'cancel'],
      priority: 'medium',
    ),
    ProactivityRule(
      id: 'agenda',
      name: 'Agenda y reuniones',
      description: 'Turnos, reuniones o citas acordadas verbalmente que no están en la agenda.',
      keywords: ['reunión', 'reunion', 'turno', 'cita', 'nos vemos', 'paso a las'],
      priority: 'medium',
    ),
  ];
}
