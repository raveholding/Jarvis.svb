import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../domain/repositories/llm_repository.dart';

/// Cliente REST mínimo de la Gemini API (Google AI Studio, capa gratuita).
class GeminiClient {
  GeminiClient(this._http);

  final http.Client _http;
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  Future<String> generate({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    bool json = true,
    int maxTokens = 1024,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user}
          ]
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
        if (json) 'responseMimeType': 'application/json',
        // La familia 2.5 "piensa" por defecto: lo apagamos para bajar latencia.
        if (model.startsWith('gemini-2.5-flash')) 'thinkingConfig': {'thinkingBudget': 0},
      },
    };

    final res = await _http
        .post(
          Uri.parse('$_base/models/$model:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw LlmException('gemini:$model', res.statusCode, _errorMessage(res.body));
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      throw LlmException('gemini:$model', 200, 'Respuesta vacía o bloqueada');
    }
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = (content?['parts'] as List?) ?? const [];
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => (p['text'] ?? '').toString())
        .join();
    if (text.trim().isEmpty) {
      throw LlmException('gemini:$model', 200, 'Sin texto en la respuesta');
    }
    return text;
  }

  Future<List<double>> embed({required String apiKey, required String text}) async {
    final res = await _http
        .post(
          Uri.parse('$_base/models/${AppConfig.embeddingModel}:embedContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'model': 'models/${AppConfig.embeddingModel}',
            'content': {
              'parts': [
                {'text': text}
              ]
            },
            'outputDimensionality': AppConfig.embeddingDims,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw LlmException('gemini:embed', res.statusCode, _errorMessage(res.body));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final values = ((data['embedding'] as Map?)?['values'] as List?) ?? const [];
    return values.map((v) => (v as num).toDouble()).toList();
  }

  static String _errorMessage(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return ((j['error'] as Map?)?['message'] ?? body).toString();
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }
}
