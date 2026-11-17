import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/agent_orchestrator.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/daily_summary.dart';

class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    await ref.read(agentProvider.notifier).generateSummary();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(latestSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen ejecutivo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _generate,
        icon: _loading
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(_loading ? 'Analizando…' : 'Generar ahora'),
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => s == null ? const _NoSummary() : _SummaryView(summary: s),
      ),
    );
  }
}

class _NoSummary extends StatelessWidget {
  const _NoSummary();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía no hay resúmenes.\nJarvis genera uno automáticamente a la noche, o tocá "Generar ahora".',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        Text(summary.date, style: t.bodySmall),
        const SizedBox(height: 6),
        Text(summary.headline, style: t.titleLarge?.copyWith(color: JColors.textPrimary, fontWeight: FontWeight.w700)),
        if (summary.focusScore != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Foco del día'),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: summary.focusScore!.clamp(0, 10) / 10,
                    minHeight: 8,
                    color: JColors.cyan,
                    backgroundColor: JColors.surfaceHigh,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${summary.focusScore}/10'),
            ],
          ),
        ],
        _Section(icon: Icons.checklist_rounded, title: 'Puntos clave', items: summary.keyPoints),
        _Section(icon: Icons.gavel_rounded, title: 'Decisiones tomadas', items: summary.decisions),
        _Section(icon: Icons.trending_up_rounded, title: 'Oportunidades', items: summary.opportunities, color: JColors.green),
        if (summary.risks.isNotEmpty)
          _Section(
            icon: Icons.warning_amber_rounded,
            title: 'Alertas de riesgo',
            color: JColors.amber,
            items: summary.risks
                .map((r) => '${r.risk} (${r.severity})${r.mitigation.isEmpty ? '' : ' → ${r.mitigation}'}')
                .toList(),
          ),
        _Section(icon: Icons.push_pin_outlined, title: 'Pendientes', items: summary.tasks),
        _Section(icon: Icons.psychology_alt_rounded, title: 'Mentoría estratégica', items: summary.advice, color: JColors.violet),
        _Section(icon: Icons.flag_rounded, title: 'Foco para mañana', items: summary.tomorrowFocus),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.items, this.color = JColors.cyan});

  final IconData icon;
  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
