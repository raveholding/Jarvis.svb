import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/llm_repository.dart';
import 'gemini_client.dart';
import 'groq_client.dart';

/// Orquesta proveedores: Gemini primero (con cadena de modelos de respaldo)
/// y Groq si Gemini no responde, se queda sin cuota o no hay clave.
class LlmRouter implements LlmRepository {
  LlmRouter({required AppSettings Function() settings, http.Client? client})
      : _settings = settings,
        _http = client ?? http.Client() {
    _gemini = GeminiClient(_http);
    _groq = GroqClient(_http);
  }

  final AppSettings Function() _settings;
  final http.Client _http;
  late final GeminiClient _gemini;
  late final GroqClient _groq;

  /// Recuerda qué modelo funcionó para no reintentar 404 en cada llamada.
  final Map<LlmTier, String> _workingGeminiModel = {};

  @override
  bool get isConfigured {
    final s = _settings();
    return s.cloudEnabled && s.hasLlm;
  }

  @override
  Future<String> complete({
    required String system,
    required String user,
    LlmTier tier = LlmTier.fast,
    bool json = true,
  }) async {
    final s = _settings();
    if (!s.cloudEnabled) {
      throw const LlmException('router', 0, 'Modo privado activo: la nube está desactivada');
    }
    final fast = tier == LlmTier.fast;
    final timeout = fast ? const Duration(seconds: 8) : const Duration(seconds: 40);
    final maxTokens = fast ? 1024 : 4096;
    final errors = <String>[];

    if (s.geminiApiKey.trim().isNotEmpty) {
      final configured = fast ? s.geminiFastModel : s.geminiSmartModel;
      final chain = <String>{
        if (_workingGeminiModel[tier] != null) _workingGeminiModel[tier]!,
        configured,
        ...AppConfig.geminiFallbacks,
      }.toList();
      for (final model in chain) {
        try {
          final out = await _gemini.generate(
            apiKey: s.geminiApiKey.trim(),
            model: model,
            system: system,
            user: user,
            json: json,
            maxTokens: maxTokens,
            timeout: timeout,
          );
          _workingGeminiModel[tier] = model;
          return out;
        } on LlmException catch (e) {
          errors.add('$model→${e.status}');
          // 404 = modelo inexistente/retirado; 400 = parámetro no soportado → probar el siguiente.
          if (e.status == 404 || e.status == 400) continue;
          break; // 401/403/429/5xx → pasar a Groq
        } catch (e) {
          errors.add('$model→$e');
          break;
        }
      }
    }

    if (s.groqApiKey.trim().isNotEmpty) {
      final model = fast ? s.groqFastModel : s.groqSmartModel;
      try {
        return await _groq.chat(
          apiKey: s.groqApiKey.trim(),
          model: model,
          system: system,
          user: user,
          json: json,
          maxTokens: maxTokens,
          timeout: timeout,
        );
      } on LlmException catch (e) {
        errors.add('groq:$model→${e.status}');
      } catch (e) {
        errors.add('groq:$model→$e');
      }
    }

    if (errors.isEmpty) errors.add('No hay API key configurada');
    JLog.i('llm', 'Fallo de proveedores: ${errors.join(' | ')}');
    throw LlmException('router', 0, errors.join(' | '));
  }

  @override
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    LlmTier tier = LlmTier.fast,
  }) async {
    final raw = await complete(system: system, user: user, tier: tier, json: true);
    return JsonUtils.decodeObject(raw);
  }

  @override
  Future<List<double>?> embed(String text) async {
    final s = _settings();
    if (!s.cloudEnabled || s.geminiApiKey.trim().isEmpty) return null;
    try {
      final v = await _gemini.embed(apiKey: s.geminiApiKey.trim(), text: text);
      return v.length == AppConfig.embeddingDims ? v : null;
    } catch (e) {
      JLog.e('llm', e);
      return null;
    }
  }
}
