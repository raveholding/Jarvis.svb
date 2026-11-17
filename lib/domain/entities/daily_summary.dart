import '../../core/utils/json_utils.dart';

class SummaryRisk {
  const SummaryRisk({required this.risk, required this.severity, required this.mitigation});
  final String risk;
  final String severity;
  final String mitigation;
}

/// Resumen ejecutivo diario estructurado.
class DailySummary {
  const DailySummary({required this.date, required this.createdAt, required this.content});

  /// yyyy-MM-dd
  final String date;
  final DateTime createdAt;
  final Map<String, dynamic> content;

  String get headline => (content['headline'] ?? 'Resumen del día').toString();
  List<String> get keyPoints => JsonUtils.stringList(content['key_points']);
  List<String> get decisions => JsonUtils.stringList(content['decisions']);
  List<String> get opportunities => JsonUtils.stringList(content['opportunities']);
  List<String> get advice => JsonUtils.stringList(content['advice']);
  List<String> get tomorrowFocus => JsonUtils.stringList(content['tomorrow_focus']);
  List<String> get tasks => JsonUtils.stringList(content['tasks']);
  int? get focusScore => (content['focus_score'] as num?)?.toInt();
  String get spokenBrief => (content['spoken_brief'] ?? headline).toString();

  List<SummaryRisk> get risks {
    final raw = content['risks'];
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is Map) {
        return SummaryRisk(
          risk: (e['risk'] ?? '').toString(),
          severity: (e['severity'] ?? 'media').toString(),
          mitigation: (e['mitigation'] ?? '').toString(),
        );
      }
      return SummaryRisk(risk: e.toString(), severity: 'media', mitigation: '');
    }).where((r) => r.risk.isNotEmpty).toList();
  }
}
