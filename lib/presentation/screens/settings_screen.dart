import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/agent_orchestrator.dart';
import '../../core/config/app_config.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/proactivity_rule.dart';
import '../../domain/repositories/llm_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AppSettings _draft;
  final Map<String, TextEditingController> _c = {};
  List<ProactivityRule> _rules = const [];
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(settingsProvider);
    final s = _draft;
    for (final e in {
      'userName': s.userName,
      'userRole': s.userRole,
      'userGoals': s.userGoals,
      'geminiApiKey': s.geminiApiKey,
      'groqApiKey': s.groqApiKey,
      'geminiFastModel': s.geminiFastModel,
      'geminiSmartModel': s.geminiSmartModel,
      'supabaseUrl': s.supabaseUrl,
      'supabaseAnonKey': s.supabaseAnonKey,
      'webhookUrl': s.webhookUrl,
      'webhookSecret': s.webhookSecret,
    }.entries) {
      _c[e.key] = TextEditingController(text: e.value);
    }
    ref.read(agentProvider.notifier).rules().then((r) {
      if (mounted) setState(() => _rules = r);
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings _collect() => _draft.copyWith(
        userName: _c['userName']!.text.trim(),
        userRole: _c['userRole']!.text.trim(),
        userGoals: _c['userGoals']!.text.trim(),
        geminiApiKey: _c['geminiApiKey']!.text.trim(),
        groqApiKey: _c['groqApiKey']!.text.trim(),
        geminiFastModel: _orDefault(_c['geminiFastModel']!.text, AppConfig.defaultGeminiFast),
        geminiSmartModel: _orDefault(_c['geminiSmartModel']!.text, AppConfig.defaultGeminiSmart),
        supabaseUrl: _c['supabaseUrl']!.text.trim(),
        supabaseAnonKey: _c['supabaseAnonKey']!.text.trim(),
        webhookUrl: _c['webhookUrl']!.text.trim(),
        webhookSecret: _c['webhookSecret']!.text.trim(),
      );

  static String _orDefault(String v, String d) => v.trim().isEmpty ? d : v.trim();

  Future<void> _save() async {
    final before = ref.read(settingsProvider);
    final next = _collect();
    await ref.read(settingsProvider.notifier).save(next);
    await ref.read(agentProvider.notifier).onSettingsChanged();
    if (!mounted) return;
    final supabaseChanged = before.supabaseUrl != next.supabaseUrl && before.supabaseUrl.isNotEmpty;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(supabaseChanged ? 'Guardado. Reiniciá la app para aplicar la nueva URL de Supabase.' : 'Ajustes guardados.'),
    ));
    Navigator.of(context).pop();
  }

  Future<void> _testLlm() async {
    setState(() => _testing = true);
    await ref.read(settingsProvider.notifier).save(_collect());
    String msg;
    try {
      final out = await ref.read(llmProvider).complete(
            system: 'Respondé solo con JSON {"ok": true, "saludo": "<saludo breve en español rioplatense>"}',
            user: 'Probando conexión de Jarvis.',
            tier: LlmTier.fast,
          );
      msg = '✅ Conexión OK: ${out.length > 80 ? out.substring(0, 80) : out}';
    } catch (e) {
      msg = '❌ $e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar todos los datos locales?'),
        content: const Text('Se eliminan transcripciones, decisiones, tareas, memoria y resúmenes de este teléfono. '
            'Los datos ya sincronizados en tu Supabase se borran desde su panel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: JColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(agentProvider.notifier).wipeAllData();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos borrados.')));
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(agentProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [TextButton(onPressed: _save, child: const Text('GUARDAR'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const _Header('Tu perfil', 'Jarvis usa esto para saber qué es importante para vos.'),
          _field('userName', 'Tu nombre'),
          _field('userRole', 'A qué te dedicás', hint: 'Ej: dueño de un almacén y desarrollador de software', lines: 2),
          _field('userGoals', 'Tus objetivos', hint: 'Ej: cerrar más ventas, no olvidar compromisos, cuidar la caja', lines: 3),

          const _Header('Cerebro (IA en la nube)', 'Gratis: aistudio.google.com → "Get API key". Groq es respaldo opcional.'),
          _field('geminiApiKey', 'Gemini API key', secret: true),
          _field('groqApiKey', 'Groq API key (opcional)', secret: true),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Modelos avanzados'),
            children: [
              _field('geminiFastModel', 'Modelo rápido (decisiones)'),
              _field('geminiSmartModel', 'Modelo inteligente (resúmenes)'),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _testLlm,
              icon: _testing
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bolt_rounded),
              label: const Text('Probar conexión'),
            ),
          ),

          const _Header('Escucha y voz', 'Todo el audio se procesa en el teléfono.'),
          DropdownButtonFormField<String>(
            initialValue: _draft.whisperModel,
            decoration: const InputDecoration(labelText: 'Modelo de transcripción (Whisper)'),
            items: const [
              DropdownMenuItem(value: 'tiny', child: Text('Tiny · 75 MB · más rápido, menos preciso')),
              DropdownMenuItem(value: 'base', child: Text('Base · 142 MB · recomendado')),
              DropdownMenuItem(value: 'small', child: Text('Small · 466 MB · más preciso, más lento')),
            ],
            onChanged: (v) => setState(() => _draft = _draft.copyWith(whisperModel: v)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: agent.modelDownloading
                ? null
                : () async {
                    await ref.read(settingsProvider.notifier).save(_collect());
                    await ref.read(agentProvider.notifier).ensureModel();
                  },
            icon: const Icon(Icons.download_rounded),
            label: Text(agent.modelDownloading
                ? 'Descargando…'
                : agent.modelReady
                    ? 'Modelo listo ✓'
                    : 'Descargar modelo ahora (usá Wi-Fi)'),
          ),
          _slider('Sensibilidad del micrófono', _draft.vadSensitivity,
              (v) => setState(() => _draft = _draft.copyWith(vadSensitivity: v)), 'Solo voces cercanas', 'Capta todo'),
          _slider('Proactividad', _draft.proactivity, (v) => setState(() => _draft = _draft.copyWith(proactivity: v)),
              'Solo lo crítico', 'Me avisa de todo'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Alertas por voz'),
            subtitle: const Text('Si lo apagás, solo recibís notificaciones'),
            value: _draft.voiceEnabled,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(voiceEnabled: v)),
          ),
          _hourRow('Horario silencioso', _draft.quietStartHour, _draft.quietEndHour,
              (a) => setState(() => _draft = _draft.copyWith(quietStartHour: a)),
              (b) => setState(() => _draft = _draft.copyWith(quietEndHour: b))),
          _hourPicker('Resumen automático a las', _draft.summaryHour,
              (h) => setState(() => _draft = _draft.copyWith(summaryHour: h))),

          const _Header('Reglas de proactividad', 'Qué situaciones merecen que Jarvis te interrumpa.'),
          for (final r in _rules)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.name),
              subtitle: Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
              value: r.enabled,
              onChanged: (v) async {
                await ref.read(agentProvider.notifier).setRuleEnabled(r.id, v);
                final rules = await ref.read(agentProvider.notifier).rules();
                if (mounted) setState(() => _rules = rules);
              },
            ),

          const _Header('Memoria en la nube (opcional)', 'Supabase + pgvector. Ver docs/DESPLIEGUE.md.'),
          _field('supabaseUrl', 'Supabase URL', hint: 'https://xxxx.supabase.co'),
          _field('supabaseAnonKey', 'Supabase anon key', secret: true),

          const _Header('Integraciones (webhooks)', 'Jarvis envía eventos JSON firmados (HMAC-SHA256) a tu ERP/CRM.'),
          _field('webhookUrl', 'URL del webhook (https://)'),
          _field('webhookSecret', 'Secreto para firmar', secret: true),

          const _Header('Privacidad', ''),
          DropdownButtonFormField<int>(
            initialValue: _draft.retentionDays,
            decoration: const InputDecoration(labelText: 'Borrar transcripciones locales después de'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 día')),
              DropdownMenuItem(value: 7, child: Text('7 días')),
              DropdownMenuItem(value: 14, child: Text('14 días')),
              DropdownMenuItem(value: 30, child: Text('30 días')),
            ],
            onChanged: (v) => setState(() => _draft = _draft.copyWith(retentionDays: v)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: JColors.red),
            onPressed: _wipe,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Borrar todos mis datos locales'),
          ),

          const _Header('Acerca de', ''),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('${AppConfig.appName} v${AppConfig.appVersion}', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Desarrollado por ${AppConfig.developerName}'),
                  const SizedBox(height: 10),
                  _copyRow(context, Icons.chat_rounded, 'WhatsApp ${AppConfig.developerWhatsapp}', AppConfig.developerWhatsappLink),
                  _copyRow(context, Icons.email_outlined, AppConfig.developerEmail, AppConfig.developerEmail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String key, String label, {String? hint, bool secret = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[key],
          obscureText: secret,
          enableSuggestions: !secret,
          autocorrect: !secret,
          minLines: secret ? 1 : lines,
          maxLines: secret ? 1 : lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _slider(String title, double value, ValueChanged<double> onChanged, String min, String max) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Slider(value: value, onChanged: onChanged, divisions: 10),
            Row(children: [
              Text(min, style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(max, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ],
        ),
      );

  Widget _hourPicker(String label, int value, ValueChanged<int> onChanged) => Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<int>(
            value: value,
            items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      );

  Widget _hourRow(String label, int start, int end, ValueChanged<int> onStart, ValueChanged<int> onEnd) => Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<int>(
            value: start,
            items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
            onChanged: (v) {
              if (v != null) onStart(v);
            },
          ),
          const Text('  a  '),
          DropdownButton<int>(
            value: end,
            items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
            onChanged: (v) {
              if (v != null) onEnd(v);
            },
          ),
        ],
      );

  Widget _copyRow(BuildContext context, IconData icon, String label, String value) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado')));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 18, color: JColors.cyan),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            const Icon(Icons.copy_rounded, size: 16, color: JColors.textSecondary),
          ]),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(color: JColors.cyan, letterSpacing: 1.6, fontSize: 12, fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      );
}
