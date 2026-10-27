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

  group('request message roles (HTTP 400 guard)', () {
    test('notice turns never reach the provider', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: await store.createSession(
          id: 's1',
          title: '(untitled)',
          model: 'default',
          persona: 'default',
        ),
      );
      await controller.ready;

      await controller.send('q1');
      controller.addNotice('context: whatever');
      await controller.send('q2');

      final roles = provider.requests[1].messages.map((m) => m.role).toSet();
      expect(roles, {'system', 'user', 'assistant'});
      expect(provider.requests[1].messages.map((m) => m.content).toList(), ['Terse.', 'q1', 'q2']);
    });

    test('error turns are not replayed to the provider', () async {
      final provider = RecordingProvider([
        const [ChatErrorEvent('HTTP 400: nope')],
        const [ChatTextEvent('ok'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('q1');
      await controller.send('q2');

      final contents = provider.requests[1].messages.map((m) => m.content).toList();
      expect(contents, ['Terse.', 'q1', 'q2']);
      expect(provider.requests[1].messages.map((m) => m.role).toSet(), {'system', 'user'});
    });

    test('regenerate after edit also filters non-conversation turns', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
        const [ChatTextEvent('a2'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('q1');
      controller.addNotice('a notice');
      await controller.regenerate();

      final contents = provider.requests[1].messages.map((m) => m.content).toList();
      expect(contents, ['Terse.', 'q1', 'a1']);
    });
  });
}
