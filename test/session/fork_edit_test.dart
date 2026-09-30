import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
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
  late ChatlDatabase db;
  late DriftSessionStore store;

  setUp(() {
    db = ChatlDatabase.memory();
    store = DriftSessionStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Session> newSession() =>
      store.createSession(id: 's1', title: '(untitled)', model: 'default', persona: 'default');

  Future<SessionController> controllerWith(RecordingProvider provider, Session session) async {
    final controller = SessionController.resume(
      config: testConfig(),
      providerFor: (_) => provider,
      store: store,
      session: session,
    );
    await controller.ready;
    return controller;
  }

  group('fork-on-edit (spec §MVP Scope, Success #5)', () {
    test('editing a user turn forks and regenerates the reply', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('answer one'), ChatDoneEvent()],
        const [ChatTextEvent('answer two'), ChatDoneEvent()],
        const [ChatTextEvent('regenerated'), ChatDoneEvent()],
      ]);
      final controller = await controllerWith(provider, await newSession());

      await controller.send('first question');
      await controller.send('second question');
      expect(controller.transcript.map((t) => t.content).toList(), [
        'first question',
        'answer one',
        'second question',
        'answer two',
      ]);

      // edit the most recent user turn
      final editedUser = controller.transcript[2];
      await controller.editTurn(editedUser.id!, 'second question, revised');

      expect(controller.transcript.map((t) => t.content).toList(), [
        'first question',
        'answer one',
        'second question, revised',
        'regenerated',
      ]);
    });

    test('the old branch stays in the database, untouched', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('answer one'), ChatDoneEvent()],
        const [ChatTextEvent('regenerated'), ChatDoneEvent()],
      ]);
      final controller = await controllerWith(provider, await newSession());

      await controller.send('original question');
      final originalAssistant = controller.transcript[1];

      await controller.editTurn(controller.transcript[0].id!, 'revised question');

      // original assistant reply still exists by id, pointing at old user turn
      final stored = await store.getMessage(originalAssistant.id!);
      expect(stored.content, 'answer one');

      final branch = await store.activeBranch(await store.getSession('s1'));
      expect(branch.map((m) => m.content).toList(), ['revised question', 'regenerated']);
    });

    test('resume after edit shows the edited branch (Success #5)', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = await controllerWith(provider, await newSession());
      await controller.send('q1');
      await controller.editTurn(controller.transcript[0].id!, 'q1 revised');

      final resumed = await controllerWith(provider, await store.getSession('s1'));
      expect(resumed.transcript.map((t) => t.content).toList(), ['q1 revised', 'a2']);
    });

    test('editing an assistant turn is rejected', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await controllerWith(provider, await newSession());
      await controller.send('q1');

      expect(() => controller.editTurn(controller.transcript[1].id!, 'x'), throwsArgumentError);
    });

    test('in-memory controllers reject editTurn (nothing to fork)', () async {
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => const FakeProvider([ChatDoneEvent()]),
      );
      await controller.send('q1');
      expect(() => controller.editTurn('nope', 'x'), throwsStateError);
    });
  });

  group('/history (flat current-branch list, spec Decisions)', () {
    test('history returns the active branch labels in order', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await controllerWith(provider, await newSession());
      await controller.send('q1');

      final history = controller.history();
      expect(history.map((h) => '${h.role}:${h.preview}').toList(), ['user:q1', 'assistant:a1']);
    });
  });
}
