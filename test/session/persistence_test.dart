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

/// Fake provider for testing.
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

/// Fake provider for testing that does nothing.
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

  group('persisted sessions (spec Success #4)', () {
    test('send persists turns; reload restores transcript identically', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('Hello'), ChatTextEvent('!'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await controller.send('q1');

      expect(controller.transcript.map((t) => t.content).toList(), ['q1', 'Hello!']);

      // restart: new controller over same store
      final restarted = SessionController.resume(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: await store.getSession('s1'),
      );
      await restarted.ready;

      expect(restarted.transcript.map((t) => t.content).toList(), ['q1', 'Hello!']);
    });

    test('session title comes from first user message, truncated to 60', () async {
      final provider = RecordingProvider([
        const [ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await controller.send(
        'A very long first message that should be truncated to sixty characters exactly',
      );

      expect((await store.getSession('s1')).title.length, 60);
      expect(
        (await store.getSession('s1')).title,
        'A very long first message that should be truncated to sixty',
      );
    });

    test('latestSession/find for --continue and --session', () async {
      expect(await store.latestSession(), isNull);

      await store.createSession(
        id: 'old',
        title: 'old session',
        model: 'gpt-4o',
        persona: 'default',
      );
      await store.createSession(
        id: 'new',
        title: 'new session',
        model: 'gpt-4o',
        persona: 'default',
      );

      expect((await store.latestSession())!.id, 'new');
    });
  });
}
