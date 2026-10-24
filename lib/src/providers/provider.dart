/// The provider seam (spec §Seams): orchestration talks to this and never
/// touches HTTP or SSE. Implementations: [OpenAiCompatProvider] (real),
/// [FakeProvider] (tests).
library;

/// A single message in a chat request.
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// One streaming chat completion request.
class StreamRequest {
  const StreamRequest({
    required this.model,
    required this.messages,
    this.maxTokens,
  });

  final String model;
  final List<ChatMessage> messages;
  final int? maxTokens;

  Map<String, dynamic> toJson() => {
    'model': model,
    'messages': [for (final m in messages) m.toJson()],
    if (maxTokens != null) 'max_tokens': maxTokens,
    'stream': true,
  };
}

/// What a [ChatEvent] carries. `other` reserves room for non-text events
/// (forward-compat: spec §Post-v1 Roadmap — never narrow this to text-only).
enum ChatEventKind { text, done, error, other }

/// Base type for streamed chat events.
sealed class ChatEvent {
  const ChatEvent();

  ChatEventKind get kind;
}

/// A text delta from the model.
class ChatTextEvent extends ChatEvent {
  const ChatTextEvent(this.text);

  final String text;

  @override
  ChatEventKind get kind => ChatEventKind.text;
}

/// Stream finished normally; token usage when the provider reports it.
class ChatDoneEvent extends ChatEvent {
  const ChatDoneEvent({this.promptTokens, this.completionTokens});

  final int? promptTokens;
  final int? completionTokens;

  @override
  ChatEventKind get kind => ChatEventKind.done;
}

/// Transport or provider-level failure. Ends the logical stream.
class ChatErrorEvent extends ChatEvent {
  const ChatErrorEvent(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  ChatEventKind get kind => ChatEventKind.error;
}

/// The provider seam.
abstract interface class Provider {
  /// Streams events for one completion. The stream closes after a
  /// [ChatDoneEvent] or [ChatErrorEvent].
  Stream<ChatEvent> chat(StreamRequest request);
}

/// Replays a scripted event list. The whole orchestration layer is testable
/// against this (spec §Seams).
final class FakeProvider implements Provider {
  const FakeProvider(this.script);

  final List<ChatEvent> script;

  @override
  Stream<ChatEvent> chat(StreamRequest request) => Stream.fromIterable(script);
}
