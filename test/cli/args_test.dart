import 'package:chatl/src/cli/args.dart';
import 'package:test/test.dart';

void main() {
  group('parseArgs', () {
    test('no args → fresh session', () {
      final args = parseArgs([]);
      expect(args.continueLatest, isFalse);
      expect(args.sessionId, isNull);
    });

    test('--continue and -c', () {
      expect(parseArgs(['--continue']).continueLatest, isTrue);
      expect(parseArgs(['-c']).continueLatest, isTrue);
    });

    test('--session <id> and --session=<id>', () {
      expect(parseArgs(['--session', 'abc']).sessionId, 'abc');
      expect(parseArgs(['--session=abc']).sessionId, 'abc');
    });

    test('conflicting flags are rejected', () {
      expect(() => parseArgs(['--continue', '--session', 'x']), throwsA(isA<UsageException>()));
    });

    test('unknown flag is rejected', () {
      expect(
        () => parseArgs(['--nope']),
        throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('--nope'))),
      );
    });

    test('--session without value is rejected', () {
      expect(() => parseArgs(['--session']), throwsA(isA<UsageException>()));
    });
  });
}
