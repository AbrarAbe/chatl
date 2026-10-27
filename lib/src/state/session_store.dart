import 'dart:math';

import 'package:drift/drift.dart';

import 'database.dart';

/// Persistence seam (spec §Seams): fork-on-edit primitives over the drift
/// `ChatlDatabase`.
abstract interface class SessionStore {
  /// Walks `parent_id` links from `active_head_id` back to the root and
  /// returns the active branch oldest-first. Empty when the session has no
  /// head yet.
  Future<List<Message>> activeBranch(Session session);

  /// Fork-on-edit: inserts a new message with [content], re-parented to the
  /// original message's parent. Callers must follow with [setHead].
  Future<Message> forkAt(String sessionId, String messageId, String content);

  /// Moves a session's active head to [messageId].
  Future<void> setHead(Session session, String messageId);
}

/// Drift-backed [SessionStore].
class DriftSessionStore implements SessionStore {
  DriftSessionStore(this._db);

  final ChatlDatabase _db;
  final _rand = Random();

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _rand.nextInt(1 << 20).toRadixString(36);
    return 'm$now$salt';
  }

  /// Fresh session id (prefix `s`).
  String newSessionId() => 's${_newId().substring(1)}';

  Future<Session> createSession({
    required String id,
    required String title,
    required String model,
    required String persona,
  }) async {
    final now = DateTime.now();
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            title: title,
            model: model,
            persona: persona,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return getSession(id);
  }

  Future<Session> getSession(String id) =>
      (_db.select(_db.sessions)..where((s) => s.id.equals(id))).getSingle();

  /// Most recently updated session, or null when none exist (`--continue`).
  Future<Session?> latestSession() async {
    final rows =
        await (_db.select(_db.sessions)
              ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Sets a session's title (first user message, truncated).
  Future<void> updateTitle(String sessionId, String title) =>
      (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId))).write(
        SessionsCompanion(
          title: Value(title),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Persists a mid-conversation model/persona switch.
  Future<void> updateProfile(
    String sessionId, {
    required String model,
    required String persona,
  }) => (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId))).write(
    SessionsCompanion(
      model: Value(model),
      persona: Value(persona),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<Message> getMessage(String id) =>
      (_db.select(_db.messages)..where((m) => m.id.equals(id))).getSingle();

  /// Appends a message. When [linkToHead] is true and [parentId] is omitted,
  /// the message links to the session's current head; [linkToHead] false with
  /// a null [parentId] means a root message (forkAt's root case). Unless
  /// [advanceHead] is false (forkAt's case), the new message becomes the
  /// session's active head.
  Future<Message> appendMessage({
    String? id,
    required String sessionId,
    String? parentId,
    bool linkToHead = true,
    bool advanceHead = true,
    required String role,
    required String content,
    String? model,
    int? promptTokens,
    int? completionTokens,
  }) async {
    final messageId = id ?? _newId();
    final effectiveParent =
        parentId ??
        (linkToHead ? (await getSession(sessionId)).activeHeadId : null);
    await _db
        .into(_db.messages)
        .insert(
          MessagesCompanion.insert(
            id: messageId,
            sessionId: sessionId,
            parentId: effectiveParent == null
                ? const Value.absent()
                : Value(effectiveParent),
            role: role,
            content: content,
            model: model == null ? const Value.absent() : Value(model),
            promptTokens: promptTokens == null
                ? const Value.absent()
                : Value(promptTokens),
            completionTokens: completionTokens == null
                ? const Value.absent()
                : Value(completionTokens),
            createdAt: DateTime.now(),
          ),
        );
    if (advanceHead) {
      await setHead(await getSession(sessionId), messageId);
    }
    return getMessage(messageId);
  }

  @override
  Future<List<Message>> activeBranch(Session session) async {
    final headId = session.activeHeadId;
    if (headId == null) return const [];

    // One query for the session's messages, then walk links in memory —
    // branch walks touch at most head-depth rows anyway.
    final all = await (_db.select(
      _db.messages,
    )..where((m) => m.sessionId.equals(session.id))).get();
    final byId = {for (final m in all) m.id: m};

    final branch = <Message>[];
    var cursor = byId[headId];
    while (cursor != null) {
      branch.add(cursor);
      cursor = cursor.parentId == null ? null : byId[cursor.parentId];
    }
    return branch.reversed.toList();
  }

  @override
  Future<Message> forkAt(
    String sessionId,
    String messageId,
    String content,
  ) async {
    final rows = await (_db.select(
      _db.messages,
    )..where((m) => m.id.equals(messageId))).get();
    if (rows.isEmpty) {
      throw StateError('no message $messageId in session $sessionId');
    }
    final original = rows.single;
    return appendMessage(
      sessionId: sessionId,
      parentId: original.parentId,
      linkToHead: false, // a root-message fork must stay a root
      advanceHead: false, // caller follows with setHead (spec §Seams)
      role: original.role,
      content: content,
      model: original.model,
      promptTokens: original.promptTokens,
      completionTokens: original.completionTokens,
    );
  }

  @override
  Future<void> setHead(Session session, String messageId) async {
    await (_db.update(
      _db.sessions,
    )..where((s) => s.id.equals(session.id))).write(
      SessionsCompanion(
        activeHeadId: Value(messageId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
