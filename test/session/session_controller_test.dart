import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
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
  group('SessionController', () {
    test('send streams deltas into assistant turn and completes', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('Hel'), ChatTextEvent('lo'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('hi');

      expect(controller.streaming, isFalse);
      expect(controller.transcript, hasLength(2));
      expect(controller.transcript[0].role, 'user');
      expect(controller.transcript[0].content, 'hi');
      expect(controller.transcript[1].role, 'assistant');
      expect(controller.transcript[1].content, 'Hello');
      expect(controller.transcript[1].error, isFalse);
    });

    test('request carries persona system message, prior turns, model', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('one'), ChatDoneEvent()],
        const [ChatTextEvent('two'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('first');
      await controller.send('second');

      final first = provider.requests[0];
      expect(first.model, 'gpt-4o');
      expect(first.messages.first.role, 'system');
      expect(first.messages.first.content, 'Terse.');
      expect(first.messages.last.content, 'first');

      final second = provider.requests[1];
      expect(second.messages.map((m) => m.content).toList(), ['Terse.', 'first', 'one', 'second']);
    });

    test('provider error event becomes visible error turn', () async {
      final provider = RecordingProvider([
        const [ChatErrorEvent('HTTP 500: nope')],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('hi');

      expect(controller.streaming, isFalse);
      expect(controller.transcript.last.error, isTrue);
      expect(controller.transcript.last.content, contains('HTTP 500'));
    });

    test('model/persona switch applies to next request only', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a'), ChatDoneEvent()],
        const [ChatTextEvent('b'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await controller.send('one');
      controller.setModel('cheap');
      controller.setPersona('review');
      await controller.send('two');

      expect(provider.requests[0].model, 'gpt-4o');
      expect(provider.requests[1].model, 'gpt-4o-mini');
      expect(provider.requests[1].messages.first.content, 'Skeptical reviewer.');
    });

    test('unknown model/persona name throws', () {
      final controller = SessionController(
        config: testConfig(),
        providerFor: (_) => FakeProvider(<List<ChatEvent>>[]),
      );

      expect(() => controller.setModel('nope'), throwsArgumentError);
      expect(() => controller.setPersona('nope'), throwsArgumentError);
    });

    test('send while streaming throws StateError', () async {
      final provider = RecordingProvider([
        // deliberately never completes within the test
      ]);
      provider.scripts.add(const [ChatTextEvent('slow...')]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      final pending = controller.send('hi');
      expect(controller.streaming, isTrue);
      expect(() => controller.send('again'), throwsStateError);
      await pending;
    });

    test('notifies listeners per streamed update', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('a'), ChatTextEvent('b'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      var updates = 0;
      final sub = controller.updates.listen((_) => updates++);
      await controller.send('hi');
      await sub.cancel();

      // user turn + 2 deltas + done
      expect(updates, greaterThanOrEqualTo(3));
      expect(controller.transcript.last.content, 'ab');
    });
  });
}
