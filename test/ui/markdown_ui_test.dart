import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/ui/chat_screen.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

Config configWith({bool? markdown}) => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: UiConfig(theme: 'dark', promptPrefix: '❯', markdown: markdown ?? true),
  commands: const [],
  search: const SearchConfig(backend: '', results: 5, citations: true),
  warnings: const [],
);

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
  Future<void> pumpReply(NoctermTester tester, SessionController controller) async {
    await tester.pumpComponent(ChatScreen(controller: controller));
    await tester.pump();
    await tester.enterText('q1');
    await tester.sendKey(LogicalKey.enter);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (tester.terminalState.containsText('heading')) break;
    }
  }

  test('ui.markdown: true renders the assistant reply as markdown', () async {
    final controller = SessionController(
      config: configWith(markdown: true),
      providerFor: (_) => FakeProvider([
        [ChatTextEvent('# heading\n\nsome **bold** words'), ChatDoneEvent()],
      ]),
    );

    await testNocterm('md on', (tester) async {
      await pumpReply(tester, controller);

      expect(tester.terminalState.containsText('heading'), isTrue);
      expect(tester.terminalState.containsText('some bold words'), isTrue);
      expect(tester.terminalState.containsText('**bold**'), isFalse);
      expect(tester.terminalState.containsText('# heading'), isFalse);
    }, size: const Size(80, 24));
  });

  test('ui.markdown: false leaves the reply verbatim', () async {
    final controller = SessionController(
      config: configWith(markdown: false),
      providerFor: (_) => FakeProvider([
        [ChatTextEvent('# heading\n\nsome **bold** words'), ChatDoneEvent()],
      ]),
    );

    await testNocterm('md off', (tester) async {
      await pumpReply(tester, controller);

      expect(tester.terminalState.containsText('**bold** words'), isTrue);
    }, size: const Size(80, 24));
  });
}
