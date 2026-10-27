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

  /// Sends [text] and waits until [expect] appears on screen.
  Future<void> typeAndWait(
    NoctermTester tester,
    String text,
    String expect,
  ) async {
    await tester.enterText(text);
    await tester.sendKey(LogicalKey.enter);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (tester.terminalState.containsText(expect)) break;
    }
  }

  group('Task 9 UI: /history + fork-on-edit', () {
    test('/history opens the flat branch list and esc closes it', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await testNocterm('history', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndWait(tester, 'q1', 'a1');
        await typeAndWait(tester, '/history', 'history (2 turns)');

        expect(tester.terminalState.containsText('history (2 turns)'), isTrue);
        expect(tester.terminalState.containsText('1. ❯ q1'), isTrue);
        expect(tester.terminalState.containsText('2. ◆ a1'), isTrue);

        await tester.sendKey(LogicalKey.escape);
        await tester.pump();
        expect(tester.terminalState.containsText('history (2 turns)'), isFalse);
      }, size: const Size(80, 24));
    });

    test('/edit <text> forks the last user turn and regenerates', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await testNocterm('edit', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        await typeAndWait(tester, 'q1', 'a1');
        expect(controller.transcript.map((t) => t.content).toList(), [
          'q1',
          'a1',
        ]);
        final originalUserIds = (await store.activeBranch(
          await store.getSession('s1'),
        )).where((m) => m.role == 'user').map((m) => m.id).toList();

        await typeAndWait(tester, '/edit q1 revised', 'a2');

        expect(tester.terminalState.containsText('q1 revised'), isTrue);
        expect(controller.transcript.map((t) => t.content).toList(), [
          'q1 revised',
          'a2',
        ]);

        // the persisted branch reflects the fork; the old branch survives
        final branch = await store.activeBranch(await store.getSession('s1'));
        expect(branch.map((m) => m.content).toList(), ['q1 revised', 'a2']);
        expect((await store.getMessage(originalUserIds.single)).content, 'q1');
      }, size: const Size(80, 24));
    });
  });
}
