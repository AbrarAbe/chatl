import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/ui/chat_screen.dart';
import 'package:chatl/src/ui/chat_scroll_controller.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import '../session/session_controller_test.dart' show RecordingProvider;

Config testConfig() => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [],
  warnings: const [],
);

void main() {
  group('ChatScreen', () {
    test('submit input → user turn and streamed assistant reply render', () async {
      final provider = RecordingProvider([
        const [ChatTextEvent('Hello'), ChatTextEvent('!'), ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);

      await testNocterm('chat', (tester) async {
        await tester.pumpComponent(ChatScreen(controller: controller));
        await tester.pump();

        // type and submit
        await tester.enterText('hi there');
        await tester.sendKey(LogicalKey.enter);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (tester.terminalState.containsText('Hello!')) break;
        }

        expect(tester.terminalState.containsText('hi there'), isTrue);
        expect(tester.terminalState.containsText('Hello!'), isTrue);
      }, size: const Size(80, 24));
    });

    test('any upward scroll releases anchor; bottom re-engages', () async {
      // a long response so the viewport overflows (one word per line)
      final longText = List.filled(60, 'line').join('\n');
      final provider = RecordingProvider([
        [ChatTextEvent(longText), const ChatDoneEvent()],
      ]);
      final controller = SessionController(config: testConfig(), providerFor: (_) => provider);
      ChatScrollController? scroll;

      await testNocterm('chat', (tester) async {
        await tester.pumpComponent(
          ChatScreen(controller: controller, onScrollControllerReady: (c) => scroll = c),
        );
        await tester.pump();

        await tester.enterText('go');
        await tester.sendKey(LogicalKey.enter);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (scroll != null && scroll!.maxScrollExtent > 0) break;
        }
        expect(scroll!.maxScrollExtent, greaterThan(0));
        expect(scroll!.isAutoScrollEnabled, isTrue);

        // a single arrow-up must release the anchor (ADR 0003)
        await tester.sendKey(LogicalKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 50));
        expect(scroll!.isAutoScrollEnabled, isFalse);

        // scroll to bottom re-engages
        for (var i = 0; i < 20; i++) {
          await tester.sendKey(LogicalKey.pageDown);
          await tester.pump(const Duration(milliseconds: 30));
          if (scroll!.isAutoScrollEnabled) break;
        }
        expect(scroll!.isAutoScrollEnabled, isTrue);
      }, size: const Size(80, 24));
    });
  });
}
