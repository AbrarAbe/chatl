import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:chatl/src/ui/chat_screen.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import '../session/session_controller_test.dart' show RecordingProvider;

Config testConfig() => Config(
  models: const {
    'default': ModelProfile(model: 'gpt-4o'),
    'cheap': ModelProfile(model: 'gpt-4o-mini'),
  },
  personas: const {'default': 'Terse.', 'review': 'Skeptical.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [],
  warnings: const [],
);

void main() {
  late ChatlDatabase db;
  late DriftSessionStore store;

  setUp(() {
    db = ChatlDatabase.memory();
    store = DriftSessionStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<SessionController> persisted(RecordingProvider provider) async {
    final session = await store.createSession(
      id: 's1',
      title: '(untitled)',
      model: 'default',
      persona: 'default',
    );
    final controller = SessionController.resume(
      config: testConfig(),
      providerFor: (_) => provider,
      store: store,
      session: session,
    );
    await controller.ready;
    return controller;
  }

  Future<void> typeAndPump(NoctermTester tester, String text) async {
    await tester.enterText(text);
    await tester.sendKey(LogicalKey.enter);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  group('Task 11: /model and /persona', () {
    test('/model <name> applies from the next request and persists', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await testNocterm('switch', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, 'q1');
        expect(provider.requests[0].model, 'gpt-4o');

        await typeAndPump(tester, '/model cheap');
        expect(
          tester.terminalState.containsText(
            '/model: now using profile "cheap"',
          ),
          isTrue,
        );

        await typeAndPump(tester, 'q2');
        expect(provider.requests[1].model, 'gpt-4o-mini');

        // earlier request untouched; session row updated
        expect(provider.requests[0].model, 'gpt-4o');
        expect((await store.getSession('s1')).model, 'cheap');
      }, size: const Size(90, 24));
    });

    test(
      '/persona <name> swaps the system prompt for later requests',
      () async {
        final provider = RecordingProvider([
          const [ChatTextEvent('a1'), ChatDoneEvent()],
          const [ChatTextEvent('a2'), ChatDoneEvent()],
        ]);
        final controller = await persisted(provider);

        await testNocterm('persona', (tester) async {
          await tester.pumpComponent(ChatScreen(controller: controller));
          await tester.pump();

          await typeAndPump(tester, 'q1');
          expect(provider.requests[0].messages.first.content, 'Terse.');

          await typeAndPump(tester, '/persona review');
          await typeAndPump(tester, 'q2');

          expect(provider.requests[1].messages.first.content, 'Skeptical.');
          expect((await store.getSession('s1')).persona, 'review');
        }, size: const Size(90, 24));
      },
    );

    test('unknown profile name fails visibly and lists what exists', () async {
      final provider = RecordingProvider([]);
      final controller = await persisted(provider);

      await testNocterm('unknown model', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/model nope');

        expect(
          tester.terminalState.containsText('unknown model "nope"'),
          isTrue,
        );
        expect(tester.terminalState.containsText('default, cheap'), isTrue);
        expect(controller.currentModel, 'default');
      }, size: const Size(90, 24));
    });

    test('bare /model lists profiles with the active one marked', () async {
      final provider = RecordingProvider([]);
      final controller = await persisted(provider);

      await testNocterm('list models', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/model');

        expect(
          tester.terminalState.containsText('models (active: default)'),
          isTrue,
        );
        expect(tester.terminalState.containsText('* default'), isTrue);
        expect(tester.terminalState.containsText('cheap'), isTrue);
      }, size: const Size(90, 24));
    });

    test('bare /persona lists personas', () async {
      final provider = RecordingProvider([]);
      final controller = await persisted(provider);

      await testNocterm('list personas', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/persona');

        expect(
          tester.terminalState.containsText('personas (active: default)'),
          isTrue,
        );
        expect(tester.terminalState.containsText('review'), isTrue);
      }, size: const Size(90, 24));
    });
  });
}
