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
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [
    SlashCommand(name: 'recap', prompt: 'Summarize in 5 bullets.'),
  ],
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

  group('Task 10 UI: registry-driven commands', () {
    test('/context shows a notice with session, model and usage', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await testNocterm('context', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/context');

        expect(tester.terminalState.containsText('session: s1'), isTrue);
        expect(tester.terminalState.containsText('gpt-4o'), isTrue);
        expect(
          tester.terminalState.containsText('usage: provider did not report'),
          isTrue,
        );
      }, size: const Size(90, 24));
    });

    test('unknown command is a visible notice, not a request', () async {
      final provider = RecordingProvider([]);
      final controller = await persisted(provider);

      await testNocterm('unknown', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/nope');

        expect(
          tester.terminalState.containsText('unknown command /nope'),
          isTrue,
        );
        expect(controller.transcript.map((t) => t.role).toList(), ['notice']);
      }, size: const Size(90, 24));
    });

    test('config command submits its prompt as the next message', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('summary'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await testNocterm('recap', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/recap');

        expect(controller.transcript.first.content, 'Summarize in 5 bullets.');
        expect(tester.terminalState.containsText('summary'), isTrue);
      }, size: const Size(90, 24));
    });

    test('/rename persists the title and confirms visibly', () async {
      final provider = RecordingProvider([]);
      final controller = await persisted(provider);

      await testNocterm('rename', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndPump(tester, '/rename errands');

        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect((await store.getSession('s1')).title, 'errands');
        expect(
          tester.terminalState.containsText(
            '/rename: session is now "errands"',
          ),
          isTrue,
        );
      }, size: const Size(90, 24));
    });

    test('/copy writes the last reply to the injected clipboard', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('copy me'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);
      String? copied;

      await testNocterm('copy', (tester) async {
        await tester.pumpComponent(
          ChatScreen(
            controller: controller,
            copyToClipboard: (text) {
              copied = text;
              return true;
            },
          ),
        );
        await tester.pump();

        await typeAndPump(tester, 'q1');
        await typeAndPump(tester, '/copy');

        expect(copied, 'copy me');
        expect(
          tester.terminalState.containsText('/copy: 7 chars copied'),
          isTrue,
        );
      }, size: const Size(90, 24));
    });

    test('/new asks the factory for a fresh session', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('fresh reply'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);
      final freshSession = await store.createSession(
        id: 's2',
        title: '(untitled)',
        model: 'default',
        persona: 'default',
      );

      await testNocterm('new', (tester) async {
        await tester.pumpComponent(
          ChatScreen(
            controller: controller,
            newSession: () async {
              final next = SessionController.resume(
                config: testConfig(),
                providerFor: (_) => provider,
                store: store,
                session: freshSession,
              );
              await next.ready;
              return next;
            },
          ),
        );
        await tester.pump();

        await typeAndPump(tester, 'q1');
        await typeAndPump(tester, '/new');
        expect(tester.terminalState.containsText('a1'), isFalse);

        await typeAndPump(tester, 'second session question');
        expect(tester.terminalState.containsText('fresh reply'), isTrue);
      }, size: const Size(90, 24));
    });
  });
}
