/// Release guard: the git tag must agree with `pubspec.yaml`.
///
/// Run by the release workflow before anything is built, so a mismatched tag
/// fails fast instead of publishing assets whose `--version` disagrees with the
/// release they came from (ADR 0001's coupled scheme, enforced).
///
/// Usage: dart run tool/check_version.dart --tag v0.2.0 [--pubspec pubspec.yaml]
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Returns null when [tag] matches [pubspecVersion], else a human-readable
/// reason. The tag may carry a leading `v`; the pubspec's build metadata
/// (`+1`) is not part of the comparison.
String? tagMismatch({required String tag, required String pubspecVersion}) {
  final tagVersion = tag.startsWith('v') ? tag.substring(1) : tag;
  if (!RegExp(r'^\d+\.\d+\.\d+').hasMatch(tagVersion)) {
    return 'tag "$tag" is not a semantic version — expected something like v1.2.3';
  }
  final declared = pubspecVersion.split('+').first;
  if (tagVersion != declared) {
    return 'tag "$tag" does not match pubspec version "$pubspecVersion"';
  }
  return null;
}

Future<void> main(List<String> argv) async {
  String? tag;
  var pubspecPath = 'pubspec.yaml';

  for (var i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--tag':
        if (i + 1 >= argv.length) _fail('--tag requires a value');
        tag = argv[++i];
      case '--pubspec':
        if (i + 1 >= argv.length) _fail('--pubspec requires a value');
        pubspecPath = argv[++i];
      default:
        _fail('unknown argument "${argv[i]}"');
    }
  }

  if (tag == null) {
    _fail('usage: dart run tool/check_version.dart --tag v1.2.3');
  }

  final file = File(pubspecPath);
  if (!file.existsSync()) {
    _fail('no pubspec at $pubspecPath');
  }
  final pubspec = loadYaml(await file.readAsString());
  final version = pubspec is Map ? '${pubspec['version']}' : null;
  if (version == null || version == 'null') {
    _fail('$pubspecPath has no version field');
  }

  final problem = tagMismatch(tag: tag, pubspecVersion: version);
  if (problem != null) _fail(problem);

  stdout.writeln('tag $tag matches pubspec version $version');
}

Never _fail(String message) {
  stderr.writeln('check_version: $message');
  exit(1);
}
