import 'dart:async';

import '../config/config.dart';
import '../providers/provider.dart';

/// One entry in the visible conversation.
class Turn {
  Turn({required this.role, required this.content, this.error = false});

  final String role; // 'user' | 'assistant'
  String content;

  /// True when this turn records a failure (spec §Interaction Model: failures
  /// are visible in the transcript, never silently dropped).
  final bool error;
}

/// Orchestrates one in-memory conversation: config → [Provider] stream →
/// transcript. No HTTP/SSE imports live here (spec §Seams); persistence is
/// layered on in Task 8.
class SessionController {
  SessionController({required this._config, required this._providerFor}) {
    _modelName = 'default';
    _personaName = 'default';
  }

  final Config _config;
  final Provider Function(ModelProfile profile) _providerFor;
  final StreamController<void> _updates = StreamController<void>.broadcast();

  late String _modelName;
  late String _personaName;
  bool _streaming = false;

  final List<Turn> transcript = [];

  String get currentModel => _modelName;
  String get currentPersona => _personaName;
  String get promptPrefix => _config.ui.promptPrefix;
  bool get streaming => _streaming;

  /// Emits after every transcript change (including in-place delta appends).
  Stream<void> get updates => _updates.stream;

  void setModel(String name) {
    if (!_config.models.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown model');
    }
    _modelName = name;
  }

  void setPersona(String name) {
    if (!_config.personas.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown persona');
    }
    _personaName = name;
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
    final request = StreamRequest(
      model: profile.model,
      messages: [
        ChatMessage(role: 'system', content: _config.personas[_personaName] ?? ''),
        for (var i = 0; i < transcript.length - 1; i++)
          ChatMessage(role: transcript[i].role, content: transcript[i].content),
      ],
    );

    final assistant = transcript.last;
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
        case ChatDoneEvent():
          break;
      }
      _updates.add(null);
      if (event is ChatErrorEvent) break;
    }

    _streaming = false;
  }
}
