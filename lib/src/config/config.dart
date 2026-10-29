import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Fatal configuration problem. [message] includes the offending key and,
/// when the YAML source provides it, the line number.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Default per-resolver context block size cap (100 KB).
const int _kDefaultMaxBytes = 100 * 1024;

/// One entry under `models:`.
class ModelProfile {
  const ModelProfile({required this.model, this.baseUrl, this.apiKey});

  final String model;
  final String? baseUrl;
  final String? apiKey;
}

/// One entry under `commands:`.
class SlashCommand {
  const SlashCommand({required this.name, required this.prompt});

  final String name;
  final String prompt;
}

/// The `ui:` section.
class UiConfig {
  const UiConfig({required this.theme, required this.promptPrefix, required this.markdown});

  final String theme;
  final String promptPrefix;
  final bool markdown;
}

/// One entry under `search:`.
class SearchConfig {
  const SearchConfig({
    required this.backend,
    required this.results,
    this.citations = true,
    this.maxBytes = _kDefaultMaxBytes,
  });

  final String backend;
  final int results;
  final bool citations;
  final int maxBytes;
}

/// One entry under `fetch:`.
class FetchConfig {
  const FetchConfig({
    required this.type,
    required this.reader,
    this.apiKey,
    this.baseUrl,
    this.results = 5,
    this.maxBytes = _kDefaultMaxBytes,
  });

  /// Backend type: `shell` (default) or `firecrawl`.
  final String type;
  final String reader;
  final String? apiKey;
  final String? baseUrl;
  final int results;
  final int maxBytes;
}

/// Validated chatl configuration (spec §Config Surface).
class Config {
  Config({
    required this.models,
    required this.personas,
    required this.ui,
    required this.commands,
    required this.warnings,
    required this.search,
    this.fetch = const FetchConfig(type: 'shell', reader: '', results: 5),
  });

  final Map<String, ModelProfile> models;
  final Map<String, String> personas;
  final UiConfig ui;
  final List<SlashCommand> commands;
  final SearchConfig search;
  final FetchConfig fetch;

  /// Non-fatal problems: missing file, unknown keys, unset `$ENV` vars.
  final List<String> warnings;

  static const _knownTopLevel = {'models', 'persona', 'ui', 'commands', 'search', 'fetch'};

  static final _envPattern = RegExp(r'\$(\w+)|\$\{(\w+)\}');

  /// Loads config from [path] (default: `~/.config/chatl/config.yaml`),
  /// interpolating `$VAR`/`${VAR}` from [environment] (default: process env).
  ///
  /// A missing file yields defaults plus a warning. Invalid content throws
  /// [ConfigException] with the offending key and line when known.
  static Future<Config> load({
    String? path,
    String? sourceOverride,
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final configPath = path ?? p.join(_home(), '.config', 'chatl', 'config.yaml');

    final String? source = sourceOverride;
    if (source == null && !File(configPath).existsSync()) {
      return Config._defaults()..warnings.add('no config file at $configPath — using defaults');
    }

    final warnings = <String>[];
    final String text = source ?? await File(configPath).readAsString();
    final String interpolated = _interpolate(text, env, warnings, configPath);

    final YamlNode root;
    try {
      root = loadYamlNode(interpolated, sourceUrl: Uri.file(configPath));
    } on YamlException catch (e) {
      final line = (e.span?.start.line ?? -1) + 1;
      throw ConfigException('$configPath: ${e.message} (line $line)');
    }

    if (root is! YamlMap) {
      throw ConfigException('$configPath: top level must be a mapping');
    }

    for (final key in root.keys) {
      if (!_knownTopLevel.contains(key)) {
        warnings.add('$configPath: unknown top-level key "$key" (ignored)');
      }
    }

    return Config(
      models: _parseModels(root['models'], configPath, warnings),
      personas: _parsePersonas(root['persona'], configPath),
      ui: _parseUi(root['ui'], configPath),
      commands: _parseCommands(root['commands'], configPath),
      search: _parseSearch(root['search'], configPath),
      fetch: _parseFetch(root['fetch'], configPath),
      warnings: warnings,
    );
  }

  static Config _defaults() => Config(
    models: const {'default': ModelProfile(model: 'gpt-4o')},
    personas: const {'default': 'Concise technical assistant. Terse. No preamble.'},
    ui: const UiConfig(theme: 'dark', promptPrefix: '❯', markdown: true),
    commands: const [],
    search: const SearchConfig(backend: '', results: 5, citations: true),
    fetch: const FetchConfig(type: 'shell', reader: '', results: 5),
    warnings: [],
  );

  static String _home() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

  static String _interpolate(
    String text,
    Map<String, String> env,
    List<String> warnings,
    String path,
  ) {
    return text.replaceAllMapped(_envPattern, (m) {
      final name = m.group(1) ?? m.group(2)!;
      final value = env[name];
      if (value == null) {
        warnings.add('$path: \$$name is not set (interpolated as empty)');
        return '';
      }
      return value;
    });
  }

  static const _knownModelKeys = {'model', 'base_url', 'api_key'};

  static Map<String, ModelProfile> _parseModels(
    YamlNode? node,
    String path,
    List<String> warnings,
  ) {
    if (node == null) return _defaults().models;
    if (node is! YamlMap) {
      throw ConfigException('$path: models must be a mapping');
    }
    final out = <String, ModelProfile>{};
    for (final entry in node.nodes.entries) {
      final name = '${entry.key}';
      final value = entry.value;
      if (value is YamlScalar) {
        if (value.value is! String) {
          throw ConfigException(
            '$path: models.$name must be a model name or mapping '
            '(line ${value.span.start.line + 1})',
          );
        }
        out[name] = ModelProfile(model: value.value as String);
      } else if (value is YamlMap) {
        for (final key in value.nodes.keys) {
          if (!_knownModelKeys.contains(key)) {
            warnings.add('$path: models.$name has unknown key "$key" (ignored)');
          }
        }
        if (!value.nodes.containsKey('base_url')) {
          warnings.add(
            '$path: models.$name has no base_url — '
            'defaults to https://api.openai.com/v1',
          );
        }
        final model = value['model'];
        if (model is! String) {
          throw ConfigException(
            '$path: models.$name.model is required '
            '(line ${value.span.start.line + 1})',
          );
        }
        final baseUrl = value['base_url'];
        final apiKey = value['api_key'];
        if (baseUrl != null && baseUrl is! String) {
          throw ConfigException(
            '$path: models.$name.base_url must be a string '
            '(line ${value.span.start.line + 1})',
          );
        }
        if (apiKey != null && apiKey is! String) {
          throw ConfigException(
            '$path: models.$name.api_key must be a string '
            '(line ${value.span.start.line + 1})',
          );
        }
        if (baseUrl != null && Uri.tryParse(baseUrl as String) == null) {
          throw ConfigException(
            '$path: models.$name.base_url is not a valid URL '
            '(line ${value.span.start.line + 1})',
          );
        }
        out[name] = ModelProfile(model: model, baseUrl: baseUrl, apiKey: apiKey as String?);
      } else {
        throw ConfigException(
          '$path: models.$name has unexpected content '
          '(line ${value.span.start.line + 1})',
        );
      }
    }
    return out;
  }

  static Map<String, String> _parsePersonas(YamlNode? node, String path) {
    if (node == null) return _defaults().personas;
    if (node is! YamlMap) {
      throw ConfigException('$path: persona must be a mapping');
    }
    final out = <String, String>{};
    for (final entry in node.nodes.entries) {
      final value = entry.value;
      if (value is! YamlScalar || value.value is! String) {
        throw ConfigException(
          '$path: persona.${entry.key} must be a string '
          '(line ${value.span.start.line + 1})',
        );
      }
      out['${entry.key}'] = value.value as String;
    }
    return out;
  }

  static UiConfig _parseUi(YamlNode? node, String path) {
    final defaults = _defaults().ui;
    if (node == null) return defaults;
    if (node is! YamlMap) {
      throw ConfigException('$path: ui must be a mapping');
    }

    String theme = defaults.theme;
    String promptPrefix = defaults.promptPrefix;
    bool markdown = defaults.markdown;

    final themeNode = node['theme'];
    if (themeNode != null) {
      if (themeNode is! String) {
        throw ConfigException('$path: ui.theme must be a string');
      }
      theme = themeNode;
    }
    final prefixNode = node['prompt_prefix'];
    if (prefixNode != null) {
      if (prefixNode is! String) {
        throw ConfigException('$path: ui.prompt_prefix must be a string');
      }
      promptPrefix = prefixNode;
    }
    final mdNode = node.nodes['markdown'];
    if (mdNode != null) {
      final value = mdNode.value;
      if (value is! bool) {
        throw ConfigException(
          '$path: ui.markdown must be true or false '
          '(line ${mdNode.span.start.line + 1})',
        );
      }
      markdown = value;
    }
    return UiConfig(theme: theme, promptPrefix: promptPrefix, markdown: markdown);
  }

  static List<SlashCommand> _parseCommands(YamlNode? node, String path) {
    if (node == null) return const [];
    if (node is! YamlList) {
      throw ConfigException(
        '$path: commands must be a list '
        '(line ${node.span.start.line + 1})',
      );
    }
    final out = <SlashCommand>[];
    for (final entry in node.nodes) {
      if (entry is! YamlMap) {
        throw ConfigException(
          '$path: commands entries must be mappings '
          '(line ${entry.span.start.line + 1})',
        );
      }
      final name = entry['name'];
      final prompt = entry['prompt'];
      if (name is! String || name.isEmpty) {
        throw ConfigException(
          '$path: every command needs a name '
          '(line ${entry.span.start.line + 1})',
        );
      }
      if (prompt is! String || prompt.isEmpty) {
        throw ConfigException(
          '$path: command "$name" needs a prompt '
          '(line ${entry.span.start.line + 1})',
        );
      }
      out.add(SlashCommand(name: name, prompt: prompt));
    }
    return out;
  }

  static SearchConfig _parseSearch(YamlNode? node, String path) {
    if (node == null) return const SearchConfig(backend: '', results: 5);
    if (node is! YamlMap) {
      throw ConfigException('$path: search must be a mapping');
    }

    final backendNode = node['backend'];
    final backend = backendNode is String ? backendNode : '';
    if (backendNode != null && backendNode is! String) {
      throw ConfigException('$path: search.backend must be a string');
    }

    final resultsNode = node['results'];
    int results = 5;
    if (resultsNode != null) {
      if (resultsNode is! int) {
        throw ConfigException(
          '$path: search.results must be an integer '
          '(line ${resultsNode.span.start.line + 1})',
        );
      }
      results = resultsNode;
    }

    final citationsNode = node.nodes['citations'];
    bool citations = true;
    if (citationsNode != null) {
      final citationsValue = citationsNode.value;
      if (citationsValue is! bool) {
        throw ConfigException(
          '$path: search.citations must be true or false '
          '(line ${citationsNode.span.start.line + 1})',
        );
      }
      citations = citationsValue;
    }

    final maxBytesNode = node.nodes['max_bytes'];
    int maxBytes = _kDefaultMaxBytes;
    if (maxBytesNode != null) {
      final maxBytesValue = maxBytesNode.value;
      if (maxBytesValue is! int) {
        throw ConfigException(
          '$path: search.max_bytes must be an integer '
          '(line ${maxBytesNode.span.start.line + 1})',
        );
      }
      maxBytes = maxBytesValue;
    }

    return SearchConfig(
      backend: backend,
      results: results,
      citations: citations,
      maxBytes: maxBytes,
    );
  }

  static FetchConfig _parseFetch(YamlNode? node, String path) {
    if (node == null) return const FetchConfig(type: 'shell', reader: '', results: 5);
    if (node is! YamlMap) {
      throw ConfigException('$path: fetch must be a mapping');
    }

    final typeNode = node['type'];
    final type = typeNode is String ? typeNode : 'shell';
    if (typeNode != null && typeNode is! String) {
      throw ConfigException('$path: fetch.type must be a string');
    }
    if (type != 'shell' && type != 'firecrawl') {
      throw ConfigException('$path: fetch.type must be "shell" or "firecrawl"');
    }

    final readerNode = node['reader'];
    final reader = readerNode is String ? readerNode : '';
    if (readerNode != null && readerNode is! String) {
      throw ConfigException('$path: fetch.reader must be a string');
    }

    final apiKeyNode = node.nodes['api_key'];
    String? apiKey;
    if (apiKeyNode != null) {
      if (apiKeyNode.value is! String) {
        throw ConfigException('$path: fetch.api_key must be a string');
      }
      apiKey = apiKeyNode.value as String;
    }

    final baseUrlNode = node.nodes['base_url'];
    String? baseUrl;
    if (baseUrlNode != null) {
      if (baseUrlNode.value is! String) {
        throw ConfigException('$path: fetch.base_url must be a string');
      }
      baseUrl = baseUrlNode.value as String;
      if (Uri.tryParse(baseUrl) == null) {
        throw ConfigException('$path: fetch.base_url is not a valid URL');
      }
    }

    final resultsNode = node['results'];
    int results = 5;
    if (resultsNode != null) {
      if (resultsNode is! int) {
        throw ConfigException(
          '$path: fetch.results must be an integer '
          '(line ${resultsNode.span.start.line + 1})',
        );
      }
      results = resultsNode;
    }

    final maxBytesNode = node.nodes['max_bytes'];
    int maxBytes = _kDefaultMaxBytes;
    if (maxBytesNode != null) {
      final maxBytesValue = maxBytesNode.value;
      if (maxBytesValue is! int) {
        throw ConfigException(
          '$path: fetch.max_bytes must be an integer '
          '(line ${maxBytesNode.span.start.line + 1})',
        );
      }
      maxBytes = maxBytesValue;
    }

    return FetchConfig(
      type: type,
      reader: reader,
      apiKey: apiKey,
      baseUrl: baseUrl,
      results: results,
      maxBytes: maxBytes,
    );
  }
}

/// Truncates [body] to [maxBytes] UTF-8 bytes, appending a visible notice
/// when truncation occurs. Never silently drops content.
String truncateWithNotice(String body, int maxBytes) {
  final bytes = utf8.encode(body);
  if (bytes.length <= maxBytes) return body;

  // Decode back up to the cap boundary to avoid splitting a multi-byte char.
  final truncated = utf8.decode(bytes.sublist(0, maxBytes));
  final over = bytes.length - maxBytes;
  return '$truncated\n[... truncated: $over bytes over cap ...]';
}
