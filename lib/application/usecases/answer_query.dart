import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/local/local_database.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/context_snapshot.dart';
import '../../domain/repositories/llm_repository.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../services/decision/decision_prompts.dart';

/// Caso de uso: el usuario le pregunta algo a Jarvis desde el orbe.
class AnswerQuery {
  AnswerQuery({
    required LocalDatabase db,
    required LlmRepository llm,
    required MemoryRepository memory,
  })  : _db = db,
        _llm = llm,
        _memory = memory;

  final LocalDatabase _db;
  final LlmRepository _llm;
  final MemoryRepository _memory;

  Future<String> call(String question, AppSettings settings, ContextSnapshot ctx) async {
    final now = DateTime.now();
    final events = await _db.contextEventsSince(DateTime(now.year, now.month, now.day), limit: 2000);
    final fmt = DateFormat('HH:mm');
    final today = events
        .map((e) => '[${fmt.format(DateTime.fromMillisecondsSinceEpoch(e['occurred_at'] as int))}] ${e['transcript']}')
        .toList();
    final recentToday = today.length > 80 ? today.sublist(today.length - 80) : today;
    final tasks = await _db.pendingTasks();
    final memories = await _memory.recall(question, k: 6);
    final summary = await _db.latestSummary();

    final payload = {
      'pregunta': question,
      'contexto_actual': ctx.toPromptJson(),
      'lo_que_paso_hoy': recentToday,
      'tareas_pendientes': tasks
          .map((t) => {
                'tarea': t['title'],
                if (t['due_at'] != null)
                  'vence': DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t['due_at'] as int)),
              })
          .toList(),
      'memoria': memories,
      if (summary != null) 'ultimo_resumen': {'fecha': summary.date, 'titular': summary.headline, 'foco': summary.tomorrowFocus},
    };

    final text = await _llm.complete(
      system: DecisionPrompts.querySystem(settings),
      user: jsonEncode(payload),
      tier: LlmTier.fast,
      json: false,
    );
    return text.replaceAll(RegExp(r'[*#_`]'), '').trim();
  }
}
