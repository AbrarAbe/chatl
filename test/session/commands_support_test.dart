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

  group('command support (Task 10)', () {
    test('addNotice is visible but never persisted', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a1'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);
      await controller.send('q1');

      controller.addNotice('context: s1');

      expect(controller.transcript.last.role, 'notice');
      expect(controller.transcript.last.content, 'context: s1');
      final branch = await store.activeBranch(await store.getSession('s1'));
      expect(branch.map((m) => m.content).toList(), ['q1', 'a1']);
    });

    test('renameSession persists the new title', () async {
      final provider = RecordingProvider([
        const [ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);

      await controller.renameSession('my chat');

      expect((await store.getSession('s1')).title, 'my chat');
    });

    test('token usage accumulates when the provider reports it', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a'), ChatDoneEvent(promptTokens: 3, completionTokens: 5)],
        const [ChatTextEvent('b'), ChatDoneEvent(promptTokens: 7, completionTokens: 11)],
      ]);
      final controller = await persisted(provider);

      await controller.send('q1');
      await controller.send('q2');

      expect(controller.totalPromptTokens, 10);
      expect(controller.totalCompletionTokens, 16);
    });

    test('describeContext names session, model, persona and usage', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a'), ChatDoneEvent()],
      ]);
      final controller = await persisted(provider);
      await controller.send('q1');

      final summary = controller.describeContext();

      expect(summary, contains('s1'));
      expect(summary, contains('gpt-4o'));
      expect(summary, contains('default'));
      expect(summary, contains('turns: 2'));
      expect(summary, contains('usage: provider did not report'));
    });
  });
}
