import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/local/local_database.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/daily_summary.dart';
import '../../domain/repositories/llm_repository.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../services/decision/decision_prompts.dart';

/// Caso de uso: resumen ejecutivo + mentoría del día.
class GenerateDailySummary {
  GenerateDailySummary({
    required LocalDatabase db,
    required LlmRepository llm,
    required MemoryRepository memory,
  })  : _db = db,
        _llm = llm,
        _memory = memory;

  final LocalDatabase _db;
  final LlmRepository _llm;
  final MemoryRepository _memory;

  static const _maxTranscriptChars = 24000;

  Future<DailySummary> call(AppSettings settings, {DateTime? day}) async {
    final d = day ?? DateTime.now();
    final start = DateTime(d.year, d.month, d.day);
    final events = await _db.contextEventsSince(start, limit: 2000);
    final decisions = await _db.decisionsSince(start, onlyInterruptions: true);
    final tasks = await _db.pendingTasks();
    final patterns = await _memory.recall('patrones hábitos prioridades del usuario', k: 8);

    final fmt = DateFormat('HH:mm');
    var lines = events
        .map((e) => '[${fmt.format(DateTime.fromMillisecondsSinceEpoch(e['occurred_at'] as int))}] ${e['transcript']}')
        .toList();
    // Si el día fue muy largo, se muestrea parejo para no perder la mañana ni la tarde.
    var total = lines.fold<int>(0, (a, l) => a + l.length);
    if (total > _maxTranscriptChars) {
      final step = (total / _maxTranscriptChars).ceil();
      lines = [for (var i = 0; i < lines.length; i += step) lines[i]];
      total = lines.fold<int>(0, (a, l) => a + l.length);
    }

    final payload = {
      'fecha': DateFormat('yyyy-MM-dd').format(d),
      'cantidad_fragmentos': events.length,
      'transcripcion_del_dia': lines,
      'alertas_dadas': decisions
          .map((x) => {'hora': fmt.format(x.createdAt), 'categoria': x.category, 'titulo': x.headline, 'mensaje': x.message})
          .toList(),
      'tareas_pendientes': tasks.map((t) => t['title']).toList(),
      'memoria_de_patrones': patterns,
    };

    final json = await _llm.completeJson(
      system: DecisionPrompts.summarySystem(settings),
      user: jsonEncode(payload),
      tier: LlmTier.smart,
    );

    final summary = DailySummary(date: DateFormat('yyyy-MM-dd').format(d), createdAt: DateTime.now(), content: json);
    await _db.upsertSummary(summary);

    // Los patrones detectados alimentan la mentoría de los próximos días.
    final newPatterns = (json['patterns'] is List) ? (json['patterns'] as List).map((e) => e.toString()) : const <String>[];
    for (final p in newPatterns.take(3)) {
      if (p.trim().length > 10) await _memory.remember(p, kind: 'pattern', importance: 0.6);
    }
    return summary;
  }
}
