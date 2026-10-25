import 'package:test/test.dart';

import '../../tool/check_version.dart';

void main() {
  group('tagMismatch (release guard, ADR 0001)', () {
    test('a matching tag passes', () {
      expect(tagMismatch(tag: 'v0.2.0', pubspecVersion: '0.2.0'), isNull);
    });

    test('the tag may omit the v prefix', () {
      expect(tagMismatch(tag: '0.2.0', pubspecVersion: '0.2.0'), isNull);
    });

    test('pubspec build metadata is ignored', () {
      expect(tagMismatch(tag: 'v0.1.0', pubspecVersion: '0.1.0+1'), isNull);
    });

    test('a mismatched tag is reported with both versions', () {
      final message = tagMismatch(tag: 'v0.2.0', pubspecVersion: '0.2.1');
      expect(message, isNotNull);
      expect(message, contains('0.2.0'));
      expect(message, contains('0.2.1'));
    });

    test('a non-version tag is rejected clearly', () {
      final message = tagMismatch(tag: 'nightly', pubspecVersion: '0.2.0');
      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('tag'));
    });
  });
}
