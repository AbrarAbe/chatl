import 'dart:async';

import '../config/config.dart';
import '../providers/provider.dart';
import '../resolve/resolver.dart';
import '../state/database.dart' show Message, Session;
import '../state/session_store.dart';

/// One entry in the visible conversation.
class Turn {
  Turn({required this.role, required this.content, this.error = false, this.id});

  final String role; // 'user' | 'assistant'
  String content;

  /// True when this turn records a failure (spec §Interaction Model: failures
  /// are visible in the transcript, never silently dropped).
  final bool error;

  /// Persisted message id; null for purely in-memory conversations.
  final String? id;

  /// What the provider sees for this turn when it differs from [content]
  /// (resolved `@` mentions). Null means "same as content" — e.g. turns
  /// restored from disk, where the raw text is replayed as-is.
  String? requestContent;
}

/// One row of `/history`: the current branch, flat (spec Decisions).
class HistoryEntry {
  const HistoryEntry({required this.role, required this.preview});

  final String role;
  final String preview;
}

/// Orchestrates one conversation: config → [Provider] stream → transcript.
/// No HTTP/SSE imports live here (spec §Seams).
///
/// With a [SessionStore] + [Session] supplied, every turn is persisted and
/// the session head advances (Task 8); without them the controller is purely
/// in-memory (used by the UI tests and the walking skeleton).
class SessionController {
  SessionController({
    required this._config,
    required this._providerFor,
    this._store,
    this._resolver = const MentionResolver(),
    Session? session,
  }) : _session = session {
    _modelName = session?.model ?? 'default';
    _personaName = session?.persona ?? 'default';
  }

  /// Resumes a persisted session, loading its active branch. Await [ready]
  /// before reading [transcript].
  SessionController.resume({
    required this._config,
    required this._providerFor,
    required DriftSessionStore this._store,
    this._resolver = const MentionResolver(),
    required Session session,
  }) : _session = session {
    _modelName = session.model;
    _personaName = session.persona;
    _ready = _load();
  }

  final Config _config;
  final Provider Function(ModelProfile profile) _providerFor;
  final DriftSessionStore? _store;
  final Session? _session;

  /// `@` mention resolver (spec §The `@` resolver layer). v1 registers none.
  final MentionResolver _resolver;
  final StreamController<void> _updates = StreamController<void>.broadcast();

  late String _modelName;
  late String _personaName;
  bool _streaming = false;
  Future<void> _ready = Future.value();

  /// Cumulative token usage reported by the provider (0 when it omits usage;
  /// the spec's `~`-estimate fallback is not implemented — Task 14 polish).
  int totalPromptTokens = 0;
  int totalCompletionTokens = 0;

  /// Session id when persisted, else null.
  String? get sessionId => _session?.id;

  final List<Turn> transcript = [];

  /// The loaded configuration (commands registry, UI options).
  Config get config => _config;

  String get currentModel => _modelName;
  String get currentPersona => _personaName;
  String get promptPrefix => _config.ui.promptPrefix;
  bool get streaming => _streaming;

  /// Completes when a resumed session's transcript has been loaded.
  Future<void> get ready => _ready;

  /// Emits after every transcript change (including in-place delta appends).
  Stream<void> get updates => _updates.stream;

  Future<void> _load() async {
    final session = _session;
    final store = _store;
    if (session == null || store == null) return;
    await _rebuildTranscript();
    _updates.add(null);
  }

  /// Replaces [transcript] with the persisted active branch. The session row
  /// is re-read first — the stored object is stale after every head move.
  Future<void> _rebuildTranscript() async {
    final store = _store!;
    final session = await store.getSession(_session!.id);
    transcript.clear();
    for (final message in await store.activeBranch(session)) {
      transcript.add(Turn(role: message.role, content: message.content, id: message.id));
    }
  }

  /// A visible, non-persisted transcript note (`/context`, command notices).
  void addNotice(String text) {
    transcript.add(Turn(role: 'notice', content: text));
    _updates.add(null);
  }

  /// `/rename <title>` — persists a new session title.
  Future<void> renameSession(String title) async {
    final store = _store;
    final session = _session;
    if (store == null || session == null) {
      throw StateError('renameSession requires a persisted session');
    }
    await store.updateTitle(session.id, title);
  }

  /// `/context` summary: session id, model, persona, turns, token usage.
  String describeContext() {
    final usage = totalPromptTokens == 0 && totalCompletionTokens == 0
        ? 'usage: provider did not report'
        : 'tokens: $totalPromptTokens in / $totalCompletionTokens out';
    return 'session: ${_session?.id ?? '(in-memory)'}'
        '\nmodel: ${_config.models[_modelName]?.model ?? _modelName}'
        ' (profile $_modelName)'
        '\npersona: $_personaName'
        '\nturns: ${transcript.where((t) => t.role != 'notice').length}'
        '\n$usage';
  }

  /// Flat current-branch listing for `/history`.
  List<HistoryEntry> history() => [
    for (final turn in transcript)
      HistoryEntry(
        role: turn.role,
        preview: turn.content.length > 60 ? '${turn.content.substring(0, 60)}…' : turn.content,
      ),
  ];

  /// Fork-on-edit: replaces the content of user turn [turnId] with [text],
  /// moves the session head to the fork, then regenerates the assistant
  /// reply. The old branch is left intact (spec §MVP Scope).
  Future<void> editTurn(String turnId, String text) async {
    if (_streaming) {
      throw StateError('a stream is already in flight');
    }
    final store = _store;
    final session = _session;
    if (store == null || session == null) {
      throw StateError('editTurn requires a persisted session');
    }
    final index = transcript.indexWhere((t) => t.id == turnId);
    if (index < 0) {
      throw ArgumentError.value(turnId, 'turnId', 'unknown turn');
    }
    if (transcript[index].role != 'user') {
      throw ArgumentError.value(turnId, 'turnId', 'only user turns are editable');
    }

    final fork = await store.forkAt(session.id, turnId, text);
    await store.setHead(session, fork.id);
    await _rebuildTranscript();
    _updates.add(null);

    await regenerate();
  }

  /// Streams an assistant reply from the current branch without adding a user
  /// turn (used after an edit).
  Future<void> regenerate() async {
    if (_streaming) {
      throw StateError('a stream is already in flight');
    }
    _streaming = true;

    transcript.add(Turn(role: 'assistant', content: ''));
    _updates.add(null);

    final profile = _config.models[_modelName]!;
    // Regeneration replays already-resolved history verbatim; no re-expansion.
    final request = StreamRequest(
      model: profile.model,
      messages: _conversationMessages(trailing: 1),
    );

    final assistant = transcript.last;
    int? promptTokens;
    int? completionTokens;

    await for (final event in _providerFor(profile).chat(request)) {
      switch (event) {
        case ChatTextEvent(:final text):
          assistant.content += text;
        case ChatErrorEvent(:final message):
          transcript[transcript.length - 1] = Turn(
            role: 'assistant',
            content: message,
            error: true,
          );
          break;
        case final ChatDoneEvent done:
          promptTokens = done.promptTokens ?? promptTokens;
          completionTokens = done.completionTokens ?? completionTokens;
          break;
      }
      _updates.add(null);
      if (event is ChatErrorEvent) break;
    }

    _assignTurnId(
      transcript.length - 1,
      await _persistAssistantTurn(
        transcript.last,
        model: profile.model,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      ),
    );

    _streaming = false;
    _updates.add(null);
  }

  void setModel(String name) {
    if (!_config.models.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown model');
    }
    _modelName = name;
    _persistProfile();
    _updates.add(null);
  }

  void setPersona(String name) {
    if (!_config.personas.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown persona');
    }
    _personaName = name;
    _persistProfile();
    _updates.add(null);
  }

  /// `/model` listing: profile names with the active one marked.
  String describeModels() {
    final lines = _config.models.keys
        .map((name) => name == _modelName ? '* $name' : '  $name')
        .join('\n');
    return 'models (active: $_modelName):\n$lines';
  }

  /// `/persona` listing.
  String describePersonas() {
    final lines = _config.personas.keys
        .map((name) => name == _personaName ? '* $name' : '  $name')
        .join('\n');
    return 'personas (active: $_personaName):\n$lines';
  }

  void _persistProfile() {
    final session = _session;
    final store = _store;
    if (session == null || store == null) return;
    store.updateProfile(session.id, model: _modelName, persona: _personaName);
  }

  /// Sends [text] as the next user turn and streams the assistant reply.
  ///
  /// Throws [StateError] if a stream is already in flight.
  Future<void> send(String text) async {
    if (_streaming) {
      throw StateError('a stream is already in flight');
    }
    _streaming = true;

    transcript
      ..add(Turn(role: 'user', content: text))
      ..add(Turn(role: 'assistant', content: ''));
    _updates.add(null);

    final profile = _config.models[_modelName]!;

    _assignTurnId(transcript.length - 2, await _persistUserTurn(text));

    // `@` mentions expand client-side, before the request is built; the
    // transcript keeps the raw text the user typed (spec §The @ resolver
    // layer). The resolved form rides on the turn so later requests never
    // leak the syntax either.
    final resolution = await _resolver.resolve(text);
    transcript[transcript.length - 2].requestContent = resolution.requestContent;
    final request = StreamRequest(
      model: profile.model,
      messages: _conversationMessages(trailing: 1),
    );

    final assistant = transcript.last;
    int? promptTokens;
    int? completionTokens;

    await for (final event in _providerFor(profile).chat(request)) {
      switch (event) {
        case ChatTextEvent(:final text):
          assistant.content += text;
        case ChatErrorEvent(:final message):
          transcript[transcript.length - 1] = Turn(
            role: 'assistant',
            content: message,
            error: true,
          );
          break;
        case final ChatDoneEvent done:
          promptTokens = done.promptTokens ?? promptTokens;
          completionTokens = done.completionTokens ?? completionTokens;
          break;
      }
      _updates.add(null);
      if (event is ChatErrorEvent) break;
    }

    totalPromptTokens += promptTokens ?? 0;
    totalCompletionTokens += completionTokens ?? 0;

    _assignTurnId(
      transcript.length - 1,
      await _persistAssistantTurn(
        transcript.last,
        model: profile.model,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      ),
    );

    _streaming = false;
    _updates.add(null);
  }

  /// Turns that belong in an API request: real conversation only. `notice`
  /// turns (command feedback, `/context`) and error turns must never be sent —
  /// a non-user/assistant role is rejected by OpenAI-compatible endpoints with
  /// HTTP 400.
  List<ChatMessage> _conversationMessages({int trailing = 0}) {
    final end = transcript.length - trailing;
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: _config.personas[_personaName] ?? ''),
    ];
    for (var i = 0; i < end; i++) {
      final turn = transcript[i];
      if (turn.role != 'user' && turn.role != 'assistant') continue;
      if (turn.error) continue;
      messages.add(ChatMessage(role: turn.role, content: turn.requestContent ?? turn.content));
    }
    return messages;
  }

  Future<Message?> _persistUserTurn(String text) async {
    final store = _store;
    final session = _session;
    if (store == null || session == null) return null;
    final message = await store.appendMessage(sessionId: session.id, role: 'user', content: text);
    if (session.title.isEmpty || session.title == '(untitled)') {
      final title = text.length <= 60 ? text : text.substring(0, 60);
      await store.updateTitle(session.id, title);
    }
    return message;
  }

  /// Gives an in-memory turn its persisted id so later edits can target it.
  void _assignTurnId(int index, Message? message) {
    if (message == null || index < 0 || index >= transcript.length) return;
    final turn = transcript[index];
    transcript[index] = Turn(role: turn.role, content: turn.content, id: message.id);
  }

  Future<Message?> _persistAssistantTurn(
    Turn turn, {
    required String model,
    int? promptTokens,
    int? completionTokens,
  }) async {
    final store = _store;
    final session = _session;
    if (store == null || session == null) return null;
    return store.appendMessage(
      sessionId: session.id,
      role: 'assistant',
      content: turn.content,
      model: model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }
}
