import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/resolve/resolver.dart';
import 'package:chatl/src/resolve/search.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

class _FakeSearchBackend implements SearchBackend {
  final List<SearchResult> results;
  final void Function(String)? onCall;

  _FakeSearchBackend({required this.results, this.onCall});

  @override
  Future<List<SearchResult>> search(String query) async {
    onCall?.call(query);
    return results;
  }
}

void main() {
  group('@ resolution in the request path (Task 12)', () {
    test('registered mention expands into the request; transcript keeps raw', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final resolver = MentionResolver(
        entries: [
          ResolverEntry(
            name: 'fake',
            takesArgument: true,
            resolve: (argument) async => ContextBlock(source: 'fake', body: 'PAGE TEXT'),
          ),
        ],
        searchResolver: SearchResolver(
          backend: _FakeSearchBackend(
            results: [
              SearchResult(title: 'Result 1', url: 'https://example.com/1', snippet: 'PAGE TEXT'),
            ],
          ),
        ),
      );
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        resolver: resolver,
      );

      await controller.send('@fake https://x — is this true?');

      // what the user sees
      expect(controller.transcript.first.content, '@fake https://x — is this true?');

      // what the model sees
      final userMessage = provider.requests.single.messages.last;
      expect(userMessage.role, 'user');
      expect(userMessage.content, contains('[CONTEXT source="fake"]'));
      expect(userMessage.content, contains('PAGE TEXT'));
      expect(userMessage.content, contains('Q: is this true?'));
      expect(userMessage.content.contains('@fake'), isFalse);
    });

    test('without resolvers the request is byte-identical to the input', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('@fetch https://x — plain passthrough');

      expect(
        provider.requests.single.messages.last.content,
        '@fetch https://x — plain passthrough',
      );
    });

    test('resolved history is not re-expanded on later turns', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      var calls = 0;
      final resolver = MentionResolver(
        entries: const [],
        searchResolver: SearchResolver(
          backend: _FakeSearchBackend(
            results: [SearchResult(title: 'Result', url: 'https://example.com', snippet: 'ONCE')],
            onCall: (query) => calls++,
          ),
        ),
      );
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        resolver: resolver,
      );

      await controller.send('@search first');
      await controller.send('second');

      // the second request replays the already-resolved first turn verbatim
      final second = provider.requests[1].messages;
      expect(calls, 1);
      expect(second[1].content, contains('ONCE'));
      expect(second.last.content, 'second');
    });
  });
}
