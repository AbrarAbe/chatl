import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';
import 'sse.dart';

/// OpenAI-compatible `/chat/completions` streaming provider (OpenAI, Ollama,
/// LM Studio, vLLM, llama.cpp, Groq, Together, OpenRouter, DeepSeek, Mistral
/// — spec §Seams).
final class OpenAiCompatProvider implements Provider {
  OpenAiCompatProvider({
    required this.baseUrl,
    this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;

  /// Sent as `Authorization: Bearer …` when non-null and non-empty.
  final String? apiKey;

  final http.Client _client;

  @override
  Stream<ChatEvent> chat(StreamRequest request) {
    final controller = StreamController<ChatEvent>();

    () async {
      final uri = Uri.parse('$baseUrl/chat/completions');
      final httpRequest = http.Request('POST', uri)
        ..headers['content-type'] = 'application/json'
        ..headers['accept'] = 'text/event-stream'
        ..body = jsonEncode(request.toJson());
      final key = apiKey;
      if (key != null && key.isNotEmpty) {
        httpRequest.headers['authorization'] = 'Bearer $key';
      }

      final http.StreamedResponse response;
      try {
        response = await _client.send(httpRequest);
      } catch (e) {
        controller
          ..add(ChatErrorEvent('transport error', cause: e))
          ..close();
        return;
      }

      if (response.statusCode != 200) {
        final snippet = await response.stream.bytesToString();
        controller
          ..add(
            ChatErrorEvent(
              'HTTP ${response.statusCode}: '
              '${snippet.length > 200 ? snippet.substring(0, 200) : snippet}',
            ),
          )
          ..close();
        return;
      }

      int? promptTokens;
      int? completionTokens;
      await for (final payload
          in response.stream
              .transform(const SseDecoder())
              .transform(const SseParser())) {
        if (payload == '[DONE]') break;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices.first['delta'] as Map<String, dynamic>?;
            final content = delta?['content'];
            if (content is String && content.isNotEmpty) {
              controller.add(ChatTextEvent(content));
            }
          }
          final usage = json['usage'];
          if (usage is Map<String, dynamic>) {
            promptTokens = usage['prompt_tokens'] as int? ?? promptTokens;
            completionTokens =
                usage['completion_tokens'] as int? ?? completionTokens;
          }
        } catch (e) {
          controller.add(ChatErrorEvent('malformed SSE payload', cause: e));
        }
      }
      controller
        ..add(
          ChatDoneEvent(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
          ),
        )
        ..close();
    }();

    return controller.stream;
  }
}
