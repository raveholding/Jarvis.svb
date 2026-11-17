enum FeedKind { alert, opportunity, task, summary, answer, info }

/// Tarjeta del feed proactivo de la pantalla principal.
class FeedItem {
  const FeedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.priority = 'medium',
    this.refId,
    this.feedback,
  });

  final String id;
  final FeedKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String priority;
  final String? refId;

  /// useful | not_useful
  final String? feedback;

  FeedItem copyWith({String? feedback}) => FeedItem(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        priority: priority,
        refId: refId,
        feedback: feedback ?? this.feedback,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        'priority': priority,
        'ref_id': refId,
        'feedback': feedback,
        'created_at': createdAt.millisecondsSinceEpoch,
        'dismissed': 0,
      };

  factory FeedItem.fromRow(Map<String, Object?> r) => FeedItem(
        id: r['id'] as String,
        kind: FeedKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => FeedKind.info),
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        priority: (r['priority'] as String?) ?? 'medium',
        refId: r['ref_id'] as String?,
        feedback: r['feedback'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );
}
