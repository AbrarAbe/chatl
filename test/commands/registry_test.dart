import 'package:chatl/src/commands/registry.dart';
import 'package:chatl/src/config/config.dart';
import 'package:test/test.dart';

Config testConfig() => Config(
  models: const {
    'default': ModelProfile(model: 'gpt-4o'),
    'cheap': ModelProfile(model: 'gpt-4o-mini'),
  },
  personas: const {'default': 'Terse.', 'review': 'Skeptical.'},
  ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
  commands: const [SlashCommand(name: 'recap', prompt: 'Summarize our conversation in 5 bullets.')],
  search: const SearchConfig(backend: '', results: 5, citations: true),
  warnings: const [],
);

void main() {
  late SlashRegistry registry;

  setUp(() {
    registry = SlashRegistry(config: testConfig());
  });

  group('SlashRegistry', () {
    test('config-defined commands render as prompts', () {
      final result = registry.resolve('/recap');
      expect(result, isA<SendPrompt>());
      expect((result as SendPrompt).prompt, 'Summarize our conversation in 5 bullets.');
    });

    test('unknown commands fail visibly', () {
      final result = registry.resolve('/unknown');
      expect(result, isA<CommandMessage>());
    });
  });
}
