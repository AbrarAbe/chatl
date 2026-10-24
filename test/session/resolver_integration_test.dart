import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/resolve/resolver.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:test/test.dart';

import 'session_controller_test.dart' show RecordingProvider;

Config testConfig() => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [],
  warnings: const [],
);

void main() {
  group('@ resolution in the request path (Task 12)', () {
    test(
      'registered mention expands into the request; transcript keeps raw',
      () async {
        final provider = RecordingProvider([
          const [ChatTextEvent('a1'), ChatDoneEvent()],
        ]);
        final resolver = MentionResolver(
          entries: [
            ResolverEntry(
              name: 'fake',
              takesArgument: true,
              resolve: (argument) async =>
                  ContextBlock(source: 'fake:$argument', body: 'PAGE TEXT'),
            ),
          ],
        );
        final controller = SessionController(
          config: testConfig(),
          providerFor: (_) => provider,
          resolver: resolver,
        );

        await controller.send('@fake https://x — is this true?');

        // what the user sees
        expect(
          controller.transcript.first.content,
          '@fake https://x — is this true?',
        );

        // what the model sees
        final userMessage = provider.requests.single.messages.last;
        expect(userMessage.role, 'user');
        expect(
          userMessage.content,
          contains('[CONTEXT source="fake:https://x"'),
        );
        expect(userMessage.content, contains('PAGE TEXT'));
        expect(userMessage.content, contains('Q: is this true?'));
        expect(userMessage.content.contains('@fake'), isFalse);
      },
    );

    test(
      'without resolvers the request is byte-identical to the input',
      () async {
        final provider = RecordingProvider([
          const [ChatTextEvent('a1'), ChatDoneEvent()],
        ]);
        final controller = SessionController(
          config: testConfig(),
          providerFor: (_) => provider,
        );

        await controller.send('@fetch https://x — plain passthrough');

        expect(
          provider.requests.single.messages.last.content,
          '@fetch https://x — plain passthrough',
        );
      },
    );

    test('resolved history is not re-expanded on later turns', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      var calls = 0;
      final resolver = MentionResolver(
        entries: [
          ResolverEntry(
            name: 'fake',
            takesArgument: false,
            resolve: (_) async {
              calls++;
              return const ContextBlock(source: 'fake', body: 'ONCE');
            },
          ),
        ],
      );
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        resolver: resolver,
      );

      await controller.send('@fake first');
      await controller.send('second');

      // the second request replays the already-resolved first turn verbatim
      final second = provider.requests[1].messages;
      expect(calls, 1);
      expect(second[1].content, contains('ONCE'));
      expect(second.last.content, 'second');
    });
  });
}
