import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/repositories/llm_repository.dart';

/// Groq: API compatible con OpenAI que corre Llama en chips LPU (muy rápido).
/// Se usa como respaldo cuando Gemini falla o llega al límite gratuito.
class GroqClient {
  GroqClient(this._http);

  final http.Client _http;
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';

  Future<String> chat({
    required String apiKey,
    required String model,
    required String system,
    required String user,
    bool json = true,
    int maxTokens = 1024,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final res = await _http
        .post(
          Uri.parse(_url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
          body: jsonEncode({
            'model': model,
            'temperature': temperature,
            'max_tokens': maxTokens,
            if (json) 'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw LlmException('groq:$model', res.statusCode, res.body.length > 200 ? res.body.substring(0, 200) : res.body);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = (data['choices'] as List?) ?? const [];
    if (choices.isEmpty) throw LlmException('groq:$model', 200, 'Respuesta vacía');
    return (((choices.first as Map)['message'] as Map?)?['content'] ?? '').toString();
  }
}
