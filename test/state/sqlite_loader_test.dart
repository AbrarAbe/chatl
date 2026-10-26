import 'package:chatl/src/state/sqlite_loader.dart';
import 'package:test/test.dart';

void main() {
  group('bundled sqlite3 resolution (Task 0.3)', () {
    test('Linux prefers a bundled library beside the executable', () {
      final path = bundledSqlitePath(
        executablePath: '/opt/chatl/chatl',
        platform: 'linux',
        exists: (candidate) => candidate == '/opt/chatl/libsqlite3.so',
      );
      expect(path, '/opt/chatl/libsqlite3.so');
    });

    test('Linux falls back to the system library when none is bundled', () {
      final path = bundledSqlitePath(
        executablePath: '/usr/local/bin/chatl',
        platform: 'linux',
        exists: (_) => false,
      );
      expect(path, isNull);
    });

    test('Windows relies on the app directory, so nothing is overridden', () {
      final path = bundledSqlitePath(
        executablePath: r'C:\chatl\chatl.exe',
        platform: 'windows',
        exists: (_) => true,
      );
      expect(path, isNull);
    });

    test('other platforms are untouched', () {
      expect(
        bundledSqlitePath(
          executablePath: '/tmp/chatl',
          platform: 'macos',
          exists: (_) => true,
        ),
        isNull,
      );
    });
  });
}
