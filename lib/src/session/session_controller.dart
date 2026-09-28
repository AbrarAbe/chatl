import 'dart:async';

import '../config/config.dart';
import '../providers/provider.dart';
import '../state/database.dart' show Session;
import '../state/session_store.dart';

/// One entry in the visible conversation.
class Turn {
  Turn({required this.role, required this.content, this.error = false});

  final String role; // 'user' | 'assistant'
  String content;

  /// True when this turn records a failure (spec §Interaction Model: failures
  /// are visible in the transcript, never silently dropped).
  final bool error;
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
  final StreamController<void> _updates = StreamController<void>.broadcast();

  late String _modelName;
  late String _personaName;
  bool _streaming = false;
  Future<void> _ready = Future.value();

  /// Session id when persisted, else null.
  String? get sessionId => _session?.id;

  final List<Turn> transcript = [];

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
    for (final message in await store.activeBranch(session)) {
      transcript.add(Turn(role: message.role, content: message.content));
    }
    _updates.add(null);
  }

  void setModel(String name) {
    if (!_config.models.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown model');
    }
    _modelName = name;
    _persistProfile();
  }

  void setPersona(String name) {
    if (!_config.personas.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown persona');
    }
    _personaName = name;
    _persistProfile();
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

    await _persistUserTurn(text);

    final request = StreamRequest(
      model: profile.model,
      messages: [
        ChatMessage(role: 'system', content: _config.personas[_personaName] ?? ''),
        for (var i = 0; i < transcript.length - 1; i++)
          ChatMessage(role: transcript[i].role, content: transcript[i].content),
      ],
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

    await _persistAssistantTurn(
      transcript.last,
      model: profile.model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );

    _streaming = false;
    _updates.add(null);
  }

  Future<void> _persistUserTurn(String text) async {
    final store = _store;
    final session = _session;
    if (store == null || session == null) return;
    await store.appendMessage(sessionId: session.id, role: 'user', content: text);
    if (session.title.isEmpty || session.title == '(untitled)') {
      final title = text.length <= 60 ? text : text.substring(0, 60);
      await store.updateTitle(session.id, title);
    }
  }

  Future<void> _persistAssistantTurn(
    Turn turn, {
    required String model,
    int? promptTokens,
    int? completionTokens,
  }) async {
    final store = _store;
    final session = _session;
    if (store == null || session == null) return;
    await store.appendMessage(
      sessionId: session.id,
      role: 'assistant',
      content: turn.content,
      model: model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }
}
