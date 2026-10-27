import 'package:chatl/src/commands/registry.dart';
import 'package:chatl/src/config/config.dart';
import 'package:test/test.dart';

Config testConfig() => Config(
  models: const {'default': ModelProfile(model: 'gpt-4o')},
  personas: const {'default': 'Terse.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [
    SlashCommand(name: 'recap', prompt: 'Summarize in 5 bullets.'),
  ],
  warnings: const [],
);

void main() {
  late SlashRegistry registry;

  setUp(() {
    registry = SlashRegistry(config: testConfig());
  });

  group('SlashRegistry.resolve', () {
    test('plain text is not a command', () {
      expect(registry.resolve('hello world'), isA<NotACommand>());
    });

    test('bare "/" is rejected visibly', () {
      final outcome = registry.resolve('/');
      expect(outcome, isA<CommandMessage>());
      expect((outcome as CommandMessage).text, contains('command'));
    });

    test('built-in actions map to their action', () {
      expect(
        (registry.resolve('/new') as CommandAction).action,
        BuiltinAction.newSession,
      );
      expect(
        (registry.resolve('/history') as CommandAction).action,
        BuiltinAction.showHistory,
      );
      expect(
        (registry.resolve('/context') as CommandAction).action,
        BuiltinAction.showContext,
      );
      expect(
        (registry.resolve('/copy') as CommandAction).action,
        BuiltinAction.copyLastReply,
      );
    });

    test('/rename requires a title', () {
      final ok = registry.resolve('/rename my chat') as CommandAction;
      expect(ok.action, BuiltinAction.rename);
      expect(ok.payload, 'my chat');

      final bad = registry.resolve('/rename') as CommandMessage;
      expect(bad.text, contains('/rename'));
    });

    test('/edit requires revised text', () {
      final ok = registry.resolve('/edit new text') as CommandAction;
      expect(ok.action, BuiltinAction.editLastUserTurn);
      expect(ok.payload, 'new text');

      expect(registry.resolve('/edit'), isA<CommandMessage>());
    });

    test('config-defined commands render as prompts', () {
      final outcome = registry.resolve('/recap') as SendPrompt;
      expect(outcome.prompt, 'Summarize in 5 bullets.');
    });

    test('unknown commands fail visibly', () {
      final outcome = registry.resolve('/nope');
      expect(outcome, isA<CommandMessage>());
      expect((outcome as CommandMessage).text, contains('/nope'));
    });

    test('config commands do not shadow built-ins', () {
      final shadowing = SlashRegistry(
        config: Config(
          models: const {'default': ModelProfile(model: 'm')},
          personas: const {'default': 'p'},
          ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
          commands: const [SlashCommand(name: 'new', prompt: 'oops')],
          warnings: const [],
        ),
      );
      expect(
        (shadowing.resolve('/new') as CommandAction).action,
        BuiltinAction.newSession,
      );
    });
  });
}
