import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:test/test.dart';

Config testConfig() => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [],
  search: const SearchConfig(backend: '', results: 5, citations: true),
  warnings: const [],
);

class RecordingProvider implements Provider {
  final List<List<ChatEvent>> scripts;
  final List<StreamRequest> requests = [];
  var _call = 0;

  RecordingProvider(this.scripts);

  @override
  Stream<ChatEvent> chat(StreamRequest request) {
    requests.add(request);
    return Stream.fromIterable(scripts[_call++]);
  }
}

class FakeProvider implements Provider {
  FakeProvider(this.scripts);
  final List<List<ChatEvent>> scripts;
  final List<StreamRequest> requests = [];
  var _call = 0;

  @override
  Stream<ChatEvent> chat(StreamRequest request) {
    requests.add(request);
    return Stream.fromIterable(scripts[_call++]);
  }
}

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

  group('fork-on-edit (spec MVP Scope)', () {
    test('editing a user turn forks and regenerates the reply', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await controller.send('first question');
      await controller.send('second question');
      expect(controller.transcript.map((t) => t.content).toList(), [
        'first question',
        'answer one',
        'second question',
        'answer two',
      ]);

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
      final controller = await persisted(provider);

      await controller.send('original question');
      final originalAssistant = controller.transcript[1];

      await controller.editTurn(controller.transcript[0].id!, 'revised question');

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
      final controller = await persisted(provider);
      await controller.send('q1');
      await controller.editTurn(controller.transcript[0].id!, 'q1 revised');

      final resumed = SessionController.resume(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: await store.getSession('s1'),
      );
      await resumed.ready;
      expect(resumed.transcript.map((t) => t.content).toList(), ['q1 revised', 'a2']);
    });

    test('editing an assistant turn is rejected', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);
      await controller.send('q1');

      expect(() => controller.editTurn(controller.transcript[1].id!, 'x'), throwsArgumentError);
    });

    test('in-memory controllers reject editTurn (nothing to fork)', () async {
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => FakeProvider([
          [ChatDoneEvent()],
        ]),
      );
      await controller.send('q1');
      expect(() => controller.editTurn('nope', 'x'), throwsStateError);
    });
  });
}
