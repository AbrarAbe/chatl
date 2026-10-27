import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/providers/provider.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/ui/chat_screen.dart';
import 'package:chatl/src/ui/theme.dart';
import 'package:nocterm/nocterm.dart' hide isNotEmpty;
import 'package:test/test.dart';

Config configWith({String theme = 'dark', String prefix = '❯'}) => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: UiConfig(theme: theme, promptPrefix: prefix, markdown: false),
  commands: const [],
  warnings: const [],
);

SessionController controllerFor(Config config) => SessionController(
  config: config,
  providerFor: (_) =>
      const FakeProvider([ChatTextEvent('a1'), ChatDoneEvent()]),
);

/// Colour of the first cell of [needle], as the terminal actually painted it.
Future<Color?> colourOf(NoctermTester tester, String needle) async {
  final positions = tester.terminalState.findText(needle);
  if (positions.isEmpty) return null;
  final cell = tester.terminalState.getCellAt(
    positions.first.x,
    positions.first.y,
  );
  return cell?.style.color;
}

void main() {
  Future<void> pumpReply(
    NoctermTester tester,
    SessionController controller,
  ) async {
    await tester.pumpComponent(ChatScreen(controller: controller));
    await tester.pump();
    await tester.enterText('q1');
    await tester.sendKey(LogicalKey.enter);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (tester.terminalState.containsText('a1')) break;
    }
  }

  test('ui.theme light paints assistant text in the light palette', () async {
    await testNocterm('light', (tester) async {
      await pumpReply(tester, controllerFor(configWith(theme: 'light')));
      expect(await colourOf(tester, 'a1'), ChatlTheme.light.paragraph);
    }, size: const Size(80, 24));
  });

  test('ui.theme dark paints assistant text in the dark palette', () async {
    await testNocterm('dark', (tester) async {
      await pumpReply(tester, controllerFor(configWith(theme: 'dark')));
      expect(await colourOf(tester, 'a1'), ChatlTheme.dark.paragraph);
    }, size: const Size(80, 24));
  });

  test('an unknown ui.theme falls back to the dark palette', () async {
    await testNocterm('fallback', (tester) async {
      await pumpReply(tester, controllerFor(configWith(theme: 'solarized')));
      expect(await colourOf(tester, 'a1'), ChatlTheme.dark.paragraph);
    }, size: const Size(80, 24));
  });

  test('ui.prompt_prefix from config is what the input line shows', () async {
    await testNocterm('prefix', (tester) async {
      await tester.pumpComponent(
        ChatScreen(controller: controllerFor(configWith(prefix: '»'))),
      );
      await tester.pump();

      expect(tester.terminalState.containsText('»'), isTrue);
      expect(tester.terminalState.containsText('❯'), isFalse);
    }, size: const Size(80, 24));
  });
}
