import '../../core/utils/json_utils.dart';

/// Lo que propone el LLM.
enum DecisionAction { silence, notify, speak }

enum DecisionPriority { low, medium, high, critical }

/// Lo que finalmente se ejecuta después de la política de interrupción.
enum Delivery { none, feed, push, voice }

T _byName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString().toLowerCase().trim();
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class DetectedTask {
  const DetectedTask({required this.title, this.due, this.owner = 'me'});

  final String title;
  final DateTime? due;

  /// me | other
  final String owner;

  factory DetectedTask.fromJson(Map<String, dynamic> j) => DetectedTask(
        title: (j['title'] ?? '').toString(),
        due: JsonUtils.toDate(j['due']),
        owner: (j['owner'] ?? 'me').toString(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'due': due?.toIso8601String(),
        'owner': owner,
      };
}

class MemoryProposal {
  const MemoryProposal({required this.fact, this.importance = 0.5});

  final String fact;
  final double importance;

  static MemoryProposal? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    if (raw['store'] != true) return null;
    final fact = (raw['fact'] ?? '').toString().trim();
    if (fact.isEmpty) return null;
    return MemoryProposal(fact: fact, importance: JsonUtils.toDouble(raw['importance'], 0.5));
  }

  Map<String, dynamic> toJson() => {'store': true, 'fact': fact, 'importance': importance};
}

class AgentDecision {
  const AgentDecision({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.priority,
    required this.category,
    required this.confidence,
    required this.headline,
    required this.message,
    this.rationale = '',
    this.tasks = const [],
    this.memory,
    this.suggestedActions = const [],
    this.delivery = Delivery.none,
    this.contextEventId,
  });

  final String id;
  final DateTime createdAt;
  final DecisionAction action;
  final DecisionPriority priority;

  /// opportunity | risk | error | task | commitment | reminder | insight | query | none
  final String category;
  final double confidence;
  final String headline;
  final String message;
  final String rationale;
  final List<DetectedTask> tasks;
  final MemoryProposal? memory;
  final List<String> suggestedActions;
  final Delivery delivery;
  final String? contextEventId;

  bool get isInterruption => delivery == Delivery.voice || delivery == Delivery.push;

  factory AgentDecision.fromLlmJson(
    Map<String, dynamic> j, {
    required String id,
    String? contextEventId,
    DateTime? createdAt,
  }) {
    final tasks = (j['detected_tasks'] is List)
        ? (j['detected_tasks'] as List)
            .whereType<Map>()
            .map((e) => DetectedTask.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.title.trim().isNotEmpty)
            .toList()
        : <DetectedTask>[];
    return AgentDecision(
      id: id,
      createdAt: createdAt ?? DateTime.now(),
      action: _byName(DecisionAction.values, j['decision'], DecisionAction.silence),
      priority: _byName(DecisionPriority.values, j['priority'], DecisionPriority.low),
      category: (j['category'] ?? 'none').toString(),
      confidence: JsonUtils.toDouble(j['confidence']).clamp(0.0, 1.0),
      headline: (j['headline'] ?? '').toString(),
      message: (j['message'] ?? '').toString(),
      rationale: (j['rationale'] ?? '').toString(),
      tasks: tasks,
      memory: MemoryProposal.fromJson(j['memory']),
      suggestedActions: JsonUtils.stringList(j['suggested_actions']),
      contextEventId: contextEventId,
      delivery: _byName(Delivery.values, j['delivery'], Delivery.none),
    );
  }

  AgentDecision copyWith({DecisionAction? action, Delivery? delivery, String? rationale}) {
    return AgentDecision(
      id: id,
      createdAt: createdAt,
      action: action ?? this.action,
      priority: priority,
      category: category,
      confidence: confidence,
      headline: headline,
      message: message,
      rationale: rationale ?? this.rationale,
      tasks: tasks,
      memory: memory,
      suggestedActions: suggestedActions,
      delivery: delivery ?? this.delivery,
      contextEventId: contextEventId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'decision': action.name,
        'priority': priority.name,
        'category': category,
        'confidence': confidence,
        'headline': headline,
        'message': message,
        'rationale': rationale,
        'detected_tasks': tasks.map((t) => t.toJson()).toList(),
        'memory': memory?.toJson(),
        'suggested_actions': suggestedActions,
        'delivery': delivery.name,
        'context_event_id': contextEventId,
      };
}
