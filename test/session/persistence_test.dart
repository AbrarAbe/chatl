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

  group('persisted sessions (spec Success #4)', () {
    test('send persists turns; reload restores transcript identically', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('Hello'), ChatTextEvent('!'), ChatDoneEvent()],
      ]);
      final session = await store.createSession(
        id: 's1',
        title: '(untitled)',
        model: 'default',
        persona: 'default',
      );
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: session,
      );

      await controller.send('hi');

      // simulate restart: fresh controller over the same db
      final resumed = SessionController.resume(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: await store.getSession('s1'),
      );
      await resumed.ready;

      expect(resumed.transcript.map((t) => '${t.role}:${t.content}').toList(), [
        'user:hi',
        'assistant:Hello!',
      ]);
    });

    test('session title comes from first user message, truncated to 60', () async {
      final provider = RecordingProvider([
        const [ChatDoneEvent()],
      ]);
      final session = await store.createSession(
        id: 's1',
        title: '(untitled)',
        model: 'default',
        persona: 'default',
      );
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => provider,
        store: store,
        session: session,
      );

      final longMessage = 'x' * 100;
      await controller.send(longMessage);

      final stored = await store.getSession('s1');
      expect(stored.title.length, 60);
      expect(stored.title, longMessage.substring(0, 60));
    });

    test('latestSession/find for --continue and --session', () async {
      expect(await store.latestSession(), isNull);

      await store.createSession(id: 'old', title: 'a', model: 'm', persona: 'p');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.createSession(id: 'new', title: 'b', model: 'm', persona: 'p');

      expect((await store.latestSession())!.id, 'new');
    });
  });
}
