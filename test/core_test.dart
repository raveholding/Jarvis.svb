import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_svb/core/utils/json_utils.dart';
import 'package:jarvis_svb/core/utils/pii_redactor.dart';
import 'package:jarvis_svb/core/utils/wav_encoder.dart';
import 'package:jarvis_svb/domain/entities/agent_decision.dart';
import 'package:jarvis_svb/domain/entities/app_settings.dart';
import 'package:jarvis_svb/domain/entities/context_snapshot.dart';
import 'package:jarvis_svb/services/audio/vad.dart';
import 'package:jarvis_svb/services/decision/interruption_policy.dart';

void main() {
  group('PiiRedactor', () {
    test('anonimiza datos sensibles argentinos', () {
      final out = PiiRedactor.redact(
        'Mi CUIT es 20-12345678-9, escribime a juan@mail.com o al 387 448 4132. '
        'Mi DNI 30.123.456. La clave es 4455.',
      );
      expect(out, contains('[CUIT]'));
      expect(out, contains('[EMAIL]'));
      expect(out, contains('[TEL]'));
      expect(out, contains('[DNI]'));
      expect(out, contains('[CLAVE]'));
      expect(out, isNot(contains('4132')));
    });

    test('no rompe montos de dinero', () {
      expect(PiiRedactor.redact('Son 1.500.000 pesos'), 'Son 1.500.000 pesos');
    });
  });

  test('WavEncoder genera cabecera RIFF válida', () {
    final wav = WavEncoder.encodePcm16(Int16List.fromList([0, 100, -100]));
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + 6);
  });

  test('JsonUtils extrae JSON envuelto en markdown', () {
    final j = JsonUtils.decodeObject('```json\n{"decision":"silence"}\n```');
    expect(j['decision'], 'silence');
  });

  test('VAD distingue silencio de voz sintética', () {
    final vad = AdaptiveEnergyVad();
    final silence = Int16List(480);
    for (var i = 0; i < 30; i++) {
      expect(vad.isSpeech(silence), isFalse);
    }
    final voice = Int16List.fromList(List.generate(480, (i) => (6000 * math.sin(2 * math.pi * 220 * i / 16000)).round()));
    expect(vad.isSpeech(voice), isTrue);
  });

  group('InterruptionPolicy', () {
    const policy = InterruptionPolicy();
    AgentDecision d({DecisionAction a = DecisionAction.speak, DecisionPriority p = DecisionPriority.high, double c = 0.9}) =>
        AgentDecision(
          id: '1',
          createdAt: DateTime(2026, 1, 1, 12),
          action: a,
          priority: p,
          category: 'commitment',
          confidence: c,
          headline: 'Presupuesto',
          message: 'Prometiste el presupuesto para mañana.',
        );

    test('baja confianza → no interrumpe', () {
      final out = policy.apply(d(c: 0.3), ctx: ContextSnapshot(now: DateTime(2026, 1, 1, 12)), settings: const AppSettings(), recent: const []);
      expect(out.delivery, Delivery.none);
    });

    test('en reunión la voz pasa a notificación', () {
      final now = DateTime(2026, 1, 1, 12);
      final ctx = ContextSnapshot(now: now, upcoming: [CalendarItem(title: 'Reunión', start: now.subtract(const Duration(minutes: 10)), end: now.add(const Duration(minutes: 30)))]);
      final out = policy.apply(d(), ctx: ctx, settings: const AppSettings(), recent: const []);
      expect(out.delivery, Delivery.push);
    });

    test('horario silencioso solo deja pasar críticos', () {
      final night = ContextSnapshot(now: DateTime(2026, 1, 1, 23));
      expect(policy.apply(d(), ctx: night, settings: const AppSettings(), recent: const []).delivery, Delivery.push);
      expect(policy.apply(d(p: DecisionPriority.critical), ctx: night, settings: const AppSettings(), recent: const []).delivery,
          Delivery.voice);
    });

    test('no repite la misma alerta', () {
      final first = d();
      final out = policy.apply(d(), ctx: ContextSnapshot(now: DateTime(2026, 1, 1, 12, 5)), settings: const AppSettings(), recent: [first]);
      expect(out.delivery, Delivery.none);
    });
  });
}
