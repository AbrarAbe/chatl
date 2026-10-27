import 'package:chatl/src/state/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

void main() {
  late ChatlDatabase db;

  setUp(() {
    db = ChatlDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('ChatlDatabase (spec §Data model)', () {
    test('schema version is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('session CRUD round-trip', () async {
      final id = await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's1',
              title: 'test chat',
              model: 'gpt-4o',
              persona: 'default',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      expect(id, greaterThan(0));

      final row = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals('s1'))).getSingle();
      expect(row.title, 'test chat');
      expect(row.activeHeadId, isNull);

      await (db.update(db.sessions)..where((s) => s.id.equals('s1'))).write(
        const SessionsCompanion(activeHeadId: Value('m1')),
      );
      final updated = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals('s1'))).getSingle();
      expect(updated.activeHeadId, 'm1');
    });

    test('message round-trip with null and JSON sources', () async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's1',
              title: 't',
              model: 'm',
              persona: 'p',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );

      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'm1',
              sessionId: 's1',
              role: 'user',
              content: 'hello',
              createdAt: DateTime(2026),
            ),
          );
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'm2',
              sessionId: 's1',
              parentId: const Value('m1'),
              role: 'assistant',
              content: 'hi',
              model: const Value('gpt-4o'),
              promptTokens: const Value(3),
              completionTokens: const Value(5),
              sources: const Value('[{"url":"https://x","title":"X"}]'),
              createdAt: DateTime(2026),
            ),
          );

      final m1 = await (db.select(
        db.messages,
      )..where((m) => m.id.equals('m1'))).getSingle();
      expect(m1.parentId, isNull);
      expect(m1.sources, isNull);

      final m2 = await (db.select(
        db.messages,
      )..where((m) => m.id.equals('m2'))).getSingle();
      expect(m2.parentId, 'm1');
      expect(m2.sources, contains('https://x'));
      expect(m2.promptTokens, 3);
    });

    test('fork chains: branched siblings share parent linkage', () async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's1',
              title: 't',
              model: 'm',
              persona: 'p',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
      Future<void> ins(String id, String? parent) => db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              sessionId: 's1',
              parentId: parent == null ? const Value.absent() : Value(parent),
              role: 'assistant',
              content: id,
              createdAt: DateTime(2026),
            ),
          );

      await ins('a', null);
      await ins('b', 'a');
      await ins('b2', 'a'); // fork sibling
      await ins('c', 'b');

      final siblingsOfA = await (db.select(
        db.messages,
      )..where((m) => m.parentId.equals('a'))).get();
      expect(siblingsOfA.map((m) => m.id), unorderedEquals(['b', 'b2']));
    });
  });
}
