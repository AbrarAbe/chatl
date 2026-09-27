import 'dart:io';

import 'package:chatl/src/config/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chatl_config_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<Config> loadSource(String source, {Map<String, String> env = const {}}) async =>
      Config.load(path: p.join(tmp.path, 'config.yaml'), sourceOverride: source, environment: env);

  group('Config.load', () {
    test('missing file → defaults with warning', () async {
      final config = await Config.load(
        path: p.join(tmp.path, 'absent.yaml'),
        environment: const {},
      );

      expect(config.models.containsKey('default'), isTrue);
      expect(config.models['default']!.model, 'gpt-4o');
      expect(config.ui.theme, 'dark');
      expect(config.ui.promptPrefix, '❯');
      expect(config.ui.markdown, isTrue);
      expect(config.warnings.single, contains('defaults'));
    });

    test('full valid config parses all sections', () async {
      final config = await loadSource('''
models:
  default: gpt-4o
  cheap: { model: gpt-4o-mini }
  local: { base_url: http://localhost:11434/v1, model: qwen2.5 }
persona:
  default: Terse assistant.
  review: Skeptical reviewer.
ui:
  theme: light
  prompt_prefix: "»"
  markdown: false
commands:
  - name: recap
    prompt: Summarize our conversation in 5 bullets.
  - name: simplify
    prompt: Rewrite the last answer, 50% shorter.
''');

      expect(config.models['default']!.model, 'gpt-4o');
      expect(config.models['cheap']!.model, 'gpt-4o-mini');
      expect(config.models['cheap']!.baseUrl, isNull);
      expect(config.models['local']!.baseUrl, 'http://localhost:11434/v1');
      expect(config.personas['review'], 'Skeptical reviewer.');
      expect(config.ui.theme, 'light');
      expect(config.ui.promptPrefix, '»');
      expect(config.ui.markdown, isFalse);
      expect(config.commands.singleWhere((c) => c.name == 'recap').prompt, contains('5 bullets'));
    });

    test(r'$VAR and ${VAR} env interpolation', () async {
      final config = await loadSource(
        '''
models:
  default:
    model: gpt-4o
    api_key: \$CHATL_TEST_KEY
  other:
    model: o1
    api_key: \${CHATL_TEST_SUFFIX}
''',
        env: const {'CHATL_TEST_KEY': 'sk-abc', 'CHATL_TEST_SUFFIX': 'tail'},
      );

      expect(config.models['default']!.apiKey, 'sk-abc');
      expect(config.models['other']!.apiKey, 'tail');
    });

    test('unset env var interpolates to empty string + warning', () async {
      final config = await loadSource('''
models:
  default:
    model: gpt-4o
    api_key: \$CHATL_UNSET_VAR
''', env: const {});

      expect(config.models['default']!.apiKey, isNull);
      expect(config.warnings.any((w) => w.contains('CHATL_UNSET_VAR')), isTrue);
    });

    test('invalid YAML fails with line information', () async {
      await expectLater(
        loadSource('models:\n  default: [unclosed\n'),
        throwsA(isA<ConfigException>().having((e) => e.message, 'message', contains('line '))),
      );
    });

    test('unknown top-level keys warn, do not fail', () async {
      final config = await loadSource('''
models: { default: gpt-4o }
futuristic_feature: true
''');

      expect(config.models['default']!.model, 'gpt-4o');
      expect(config.warnings.single, contains('futuristic_feature'));
    });

    test('model profile without model name fails with location', () async {
      await expectLater(
        loadSource('models:\n  cheap: { base_url: http://x }\n'),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains('cheap'))
              .having((e) => e.message, 'message', contains('model')),
        ),
      );
    });

    test('ui.markdown with wrong type fails with location', () async {
      await expectLater(
        loadSource('ui:\n  markdown: yes please\n'),
        throwsA(
          isA<ConfigException>().having((e) => e.message, 'message', contains('ui.markdown')),
        ),
      );
    });

    test('command without name fails', () async {
      await expectLater(
        loadSource('commands:\n  - prompt: hello\n'),
        throwsA(isA<ConfigException>().having((e) => e.message, 'message', contains('name'))),
      );
    });

    test('unknown nested model key warns (typo guard: api-key vs api_key)', () async {
      final config = await loadSource('''
models:
  default:
    model: gpt-4o
    api-key: sk-nope
''');

      expect(config.warnings.any((w) => w.contains('api-key')), isTrue);
      // ignored, not applied: no auth header will be built from it
      expect(config.models['default']!.apiKey, isNull);
    });

    test('map-form profile without base_url warns about OpenAI default', () async {
      final config = await loadSource('''
models:
  default:
    model: some-model-id
    api_key: sk-abc
''');

      expect(config.models['default']!.baseUrl, isNull);
      expect(config.warnings.any((w) => w.contains('api.openai.com')), isTrue);
    });
  });
}
