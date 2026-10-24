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
  commands: const [],
  warnings: const [],
);

void main() {
  late SlashRegistry registry;

  setUp(() {
    registry = SlashRegistry(config: testConfig());
  });

  group('/model and /persona (Task 11)', () {
    test('bare /model and /persona ask for the current profile listing', () {
      final model = registry.resolve('/model') as CommandAction;
      expect(model.action, BuiltinAction.setModel);
      expect(model.payload, isNull);

      final persona = registry.resolve('/persona') as CommandAction;
      expect(persona.action, BuiltinAction.setPersona);
      expect(persona.payload, isNull);
    });

    test('payload names the profile to switch to', () {
      expect(
        (registry.resolve('/model cheap') as CommandAction).payload,
        'cheap',
      );
      expect(
        (registry.resolve('/persona review') as CommandAction).payload,
        'review',
      );
    });

    test('extra whitespace is trimmed, inner spaces are kept', () {
      expect(
        (registry.resolve('/model   cheap  ') as CommandAction).payload,
        'cheap',
      );
      expect(
        (registry.resolve('/persona a b') as CommandAction).payload,
        'a b',
      );
    });
  });
}
