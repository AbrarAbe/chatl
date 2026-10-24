import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
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
  group('request message roles (HTTP 400 guard)', () {
    test('notice turns never reach the provider', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
      );

      await controller.send('q1');
      controller.addNotice('context: whatever');
      await controller.send('q2');

      final roles = provider.requests[1].messages.map((m) => m.role).toSet();
      expect(roles, {'system', 'user', 'assistant'});
      expect(provider.requests[1].messages.map((m) => m.content).toList(), [
        'Terse.',
        'q1',
        'a1',
        'q2',
      ]);
    });

    test('error turns are not replayed to the provider', () async {
      final provider = RecordingProvider([
        const [ChatErrorEvent('HTTP 400: bad role')],
        const [ChatTextEvent('ok'), ChatDoneEvent()],
      ]);
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
      );

      await controller.send('q1');
      await controller.send('q2');

      final contents = provider.requests[1].messages
          .map((m) => m.content)
          .toList();
      expect(contents, ['Terse.', 'q1', 'q2']);
      // the errored assistant turn is skipped, so only user/system remain
      expect(provider.requests[1].messages.map((m) => m.role).toSet(), {
        'system',
        'user',
      });
    });

    test('regenerate after edit also filters non-conversation turns', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
      );

      await controller.send('q1');
      controller.addNotice('a notice');
      await controller.regenerate();

      final contents = provider.requests[1].messages
          .map((m) => m.content)
          .toList();
      expect(contents, ['Terse.', 'q1', 'a1']);
    });
  });
}
