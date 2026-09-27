import 'dart:async';
import 'dart:convert';

import 'package:chatl/src/providers/openai_compat.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/providers/sse.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

List<List<int>> _split(List<int> bytes, List<int> sizes) {
  final out = <List<int>>[];
  var i = 0;
  var s = 0;
  while (i < bytes.length) {
    final n = sizes[s % sizes.length];
    out.add(bytes.sublist(i, i + n > bytes.length ? bytes.length : i + n));
    i += n;
    s++;
  }
  return out;
}

void main() {
  group('SseParser', () {
    Stream<String> feed(List<String> chunks) =>
        Stream<List<int>>.fromIterable(chunks.map((c) => utf8.encode(c) as List<int>))
            .transform(const SseDecoder())
            .transform(const SseParser());

    test('parses single-line data events', () async {
      final events = await feed(['data: hello\n\n', 'data: world\n\n']).toList();
      expect(events, ['hello', 'world']);
    });

    test('handles chunks split mid-line', () async {
      final events = await feed(['data: hel', 'lo\n', '\nda', 'ta: done\n\n']).toList();
      expect(events, ['hello', 'done']);
    });

    test('handles multi-line data fields in one event', () async {
      final events = await feed(['data: part1\n', 'data: part2\n\n']).toList();
      expect(events, ['part1\npart2']);
    });

    test('ignores comment lines (keepalives)', () async {
      final events = await feed([': OPENAI keepalive\n', '\n', 'data: real\n\n']).toList();
      expect(events, ['real']);
    });

    test('passes [DONE] through as an event', () async {
      final events = await feed(['data: [DONE]\n\n']).toList();
      expect(events, ['[DONE]']);
    });

    test('handles CRLF line endings', () async {
      final events = await feed(['data: a\r\n\r\ndata: b\r\n\r\n']).toList();
      expect(events, ['a', 'b']);
    });

    test('flushes trailing event without blank line at stream end', () async {
      final events = await feed(['data: tail\n']).toList();
      expect(events, ['tail']);
    });
  });

  group('OpenAiCompatProvider', () {
    http.StreamedResponse streamBody(
      String body, {
      int status = 200,
      List<int> chunkSizes = const [7],
    }) => http.StreamedResponse(
      Stream.fromIterable(_split(utf8.encode(body), chunkSizes)),
      status,
      headers: {'content-type': 'text/event-stream'},
    );

    test('maps SSE delta chunks to ChatEvents', () async {
      const body =
          'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
          ': keepalive\n\n'
          'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'
          'data: [DONE]\n\n';
      final provider = OpenAiCompatProvider(
        baseUrl: 'http://x.test/v1',
        apiKey: 'k',
        client: MockClient.streaming((_, _) => Future.value(streamBody(body))),
      );

      final events = await provider
          .chat(
            const StreamRequest(
              model: 'gpt-4o',
              messages: [ChatMessage(role: 'user', content: 'hi')],
            ),
          )
          .toList();

      expect(events.whereType<ChatTextEvent>().map((e) => e.text).toList(), ['Hel', 'lo']);
      expect(events.last, isA<ChatDoneEvent>());
    });

    test('emits error event on non-200', () async {
      final provider = OpenAiCompatProvider(
        baseUrl: 'http://x.test/v1',
        client: MockClient.streaming((_, _) => Future.value(streamBody('nope', status: 500))),
      );

      final events = await provider.chat(const StreamRequest(model: 'm', messages: [])).toList();

      expect(events.single, isA<ChatErrorEvent>());
      expect((events.single as ChatErrorEvent).message, contains('500'));
    });

    test('captures usage when present', () async {
      const body =
          'data: {"choices":[{"delta":{"content":"x"}}],'
          '"usage":null}\n\n'
          'data: {"choices":[{"delta":{}}],'
          '"usage":{"prompt_tokens":3,"completion_tokens":5}}\n\n'
          'data: [DONE]\n\n';
      final provider = OpenAiCompatProvider(
        baseUrl: 'http://x.test/v1',
        client: MockClient.streaming((_, _) => Future.value(streamBody(body))),
      );

      final events = await provider.chat(const StreamRequest(model: 'm', messages: [])).toList();

      final done = events.whereType<ChatDoneEvent>().single;
      expect(done.promptTokens, 3);
      expect(done.completionTokens, 5);
    });

    test('transport failure yields error event, not throw', () async {
      final provider = OpenAiCompatProvider(
        baseUrl: 'http://x.test/v1',
        client: MockClient.streaming((_, _) => throw http.ClientException('boom')),
      );
      final events = await provider.chat(const StreamRequest(model: 'm', messages: [])).toList();
      expect(events.single, isA<ChatErrorEvent>());
    });
  });

  group('FakeProvider', () {
    test('replays scripted events', () async {
      final provider = FakeProvider(const [
        ChatTextEvent('a'),
        ChatTextEvent('b'),
        ChatDoneEvent(),
      ]);
      final events = await provider.chat(const StreamRequest(model: 'm', messages: [])).toList();
      expect(events.map((e) => e.runtimeType).toList(), [
        ChatTextEvent,
        ChatTextEvent,
        ChatDoneEvent,
      ]);
    });
  });
}
