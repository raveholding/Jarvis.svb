import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/agent_orchestrator.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/feed_item.dart';
import '../widgets/consent_dialog.dart';
import '../widgets/privacy_bar.dart';
import '../widgets/proactive_card.dart';
import '../widgets/voice_orb.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(agentProvider);
    final settings = ref.watch(settingsProvider);
    final level = ref.watch(audioLevelProvider).valueOrNull ?? 0;
    final controller = ref.read(agentProvider.notifier);

    ref.listen(agentProvider.select((s) => s.error), (_, error) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        controller.clearError();
      }
    });

    Future<void> toggleAmbient(bool on) async {
      if (on && !settings.consentAccepted) {
        final ok = await showConsentDialog(context);
        if (!ok) return;
        await ref.read(settingsProvider.notifier).save(settings.copyWith(consentAccepted: true));
      }
      await controller.setAmbient(on);
    }

    return WithForegroundTask(
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.55),
              radius: 1.1,
              colors: [Color(0xFF0A1424), JColors.background],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  status: agent.ambientOn ? 'EN LÍNEA' : (agent.isPaused ? 'EN PAUSA' : 'EN REPOSO'),
                  live: agent.ambientOn,
                  onSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
                if (!settings.hasLlm) const _SetupBanner(),
                const SizedBox(height: 4),
                VoiceOrb(
                  phase: agent.phase,
                  level: level,
                  paused: agent.isPaused,
                  size: MediaQuery.sizeOf(context).height < 700 ? 190 : 240,
                  onTap: controller.onOrbTap,
                  onLongPress: () => toggleAmbient(!agent.ambientOn),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          agent.modelDownloading ? 'Descargando modelo de voz…' : agent.status,
                          key: ValueKey(agent.status + agent.modelDownloading.toString()),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (agent.modelDownloading)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (agent.lastTranscript != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          agent.lastTranscript!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PrivacyBar(
                  ambientOn: agent.ambientOn,
                  paused: agent.isPaused,
                  privateMode: !settings.cloudEnabled,
                  onAmbientChanged: toggleAmbient,
                  onPauseTap: () => agent.isPaused
                      ? controller.resumeFromPause()
                      : controller.pauseFor(const Duration(hours: 1)),
                  onPrivateChanged: (private) =>
                      ref.read(settingsProvider.notifier).save(settings.copyWith(cloudEnabled: !private)),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('FEED PROACTIVO',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SummaryScreen())),
                        icon: const Icon(Icons.insights_rounded, size: 18),
                        label: const Text('Resumen del día'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: agent.feed.isEmpty
                      ? const _EmptyFeed()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: agent.feed.length,
                          itemBuilder: (context, i) {
                            final item = agent.feed[i];
                            return ProactiveCard(
                              item: item,
                              onDismiss: () => controller.dismiss(item.id),
                              onFeedback: item.refId == null ? null : (v) => controller.feedback(item.refId!, v),
                              onTap: item.kind == FeedKind.summary
                                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SummaryScreen()))
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.status, required this.live, required this.onSettings});

  final String status;
  final bool live;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Text('JARVIS', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: live ? JColors.cyan : JColors.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: live ? JColors.cyan : JColors.muted),
                ),
                const SizedBox(width: 6),
                Text(status, style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: JColors.textSecondary)),
              ],
            ),
          ),
          const Spacer(),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.tune_rounded), tooltip: 'Ajustes'),
        ],
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: JColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.key_rounded, color: JColors.amber),
                SizedBox(width: 10),
                Expanded(child: Text('Cargá tu API key gratuita de Gemini para activar el cerebro de Jarvis.')),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Acá van a aparecer oportunidades, riesgos y compromisos que Jarvis detecte.\n\n'
          'Tocá el orbe para preguntarle algo · Mantenelo apretado para activar la escucha ambiente.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
