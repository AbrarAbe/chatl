import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:test/test.dart';

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

  Future<Session> makeSession() =>
      store.createSession(id: 's1', title: 'chat', model: 'gpt-4o', persona: 'default');

  /// Inserts a linear chain; message ids equal their contents.
  Future<void> chain(List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      await store.appendMessage(
        id: ids[i],
        sessionId: 's1',
        parentId: i == 0 ? null : ids[i - 1],
        role: i.isEven ? 'user' : 'assistant',
        content: ids[i],
      );
    }
  }

  Future<List<String>> branchContent() async =>
      (await store.activeBranch(await store.getSession('s1'))).map((m) => m.content).toList();

  group('DriftSessionStore (spec §Seams)', () {
    test('activeBranch of a fresh session is empty', () async {
      final session = await makeSession();
      expect(await store.activeBranch(session), isEmpty);
    });

    test('activeBranch walks linear history to head', () async {
      await makeSession();
      await chain(['a', 'b', 'c']);
      expect(await branchContent(), ['a', 'b', 'c']);
    });

    test('forkAt + setHead creates alternative branch', () async {
      final session = await makeSession();
      await chain(['a', 'b', 'c']);

      final forked = await store.forkAt('s1', 'b', 'b2');
      expect(forked.content, 'b2');
      expect(forked.parentId, 'a');

      await store.setHead(session, forked.id);
      expect(await branchContent(), ['a', 'b2']);
    });

    test('old branch untouched after fork (isolation)', () async {
      await makeSession();
      await chain(['a', 'b']);

      await store.forkAt('s1', 'a', 'a2');

      expect((await store.getMessage('a')).content, 'a');
      expect((await store.getMessage('b')).parentId, 'a');
    });

    test('fork-of-fork walks correctly', () async {
      final session = await makeSession();
      await chain(['a', 'b']);

      final f1 = await store.forkAt('s1', 'b', 'b2');
      await store.appendMessage(sessionId: 's1', parentId: f1.id, role: 'assistant', content: 'c2');
      final f2 = await store.forkAt('s1', f1.id, 'b3');
      await store.setHead(session, f2.id);

      expect(await branchContent(), ['a', 'b3']);
    });

    test('forkAt of unknown message throws', () async {
      await makeSession();
      expect(() => store.forkAt('s1', 'nope', 'x'), throwsStateError);
    });
  });
}
