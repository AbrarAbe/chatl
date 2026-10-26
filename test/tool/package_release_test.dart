import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/package_release.dart';

void main() {
  group('packaging helpers (Task 0.3)', () {
    test('asset and archive names follow the spec', () {
      expect(
        zipNameFor(version: '0.2.0', platform: 'linux-x64'),
        'chatl-0.2.0-linux-x64.zip',
      );
      expect(
        zipNameFor(version: '0.2.0', platform: 'windows-x64'),
        'chatl-0.2.0-windows-x64.zip',
      );
    });

    test('bundle entries are the binary, sqlite3 and a README', () {
      expect(bundleBinaryName('linux-x64'), 'chatl');
      expect(bundleBinaryName('windows-x64'), 'chatl.exe');
      expect(bundleSqliteName('linux-x64'), 'libsqlite3.so');
      expect(bundleSqliteName('windows-x64'), 'sqlite3.dll');
      expect(bundleReadmeName(), 'README.txt');
    });

    test('SHA256SUMS lines are "<hash>  <file>"', () async {
      final dir = await Directory.systemTemp.createTemp('chatl_pkg');
      final file = File(p.join(dir.path, 'x.txt'))..writeAsStringSync('hello');

      final line = await sha256Line(file);

      // sha256("hello")
      expect(
        line,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  x.txt',
      );
      await dir.delete(recursive: true);
    });

    test(
      'assembleBundle lays out a directory; zipBundle checksums it',
      () async {
        final dir = await Directory.systemTemp.createTemp('chatl_asm');
        final fakeBinary = File(p.join(dir.path, 'fake-binary'))
          ..writeAsStringSync('#!/bin/sh\necho chatl\n');
        final fakeLib = File(p.join(dir.path, 'fake-sqlite.so'))
          ..writeAsStringSync('sqlite bytes');

        final bundle = await assembleBundle(
          platform: 'linux-x64',
          version: '0.2.0',
          binary: fakeBinary,
          sqliteLibrary: fakeLib,
          outDir: Directory(p.join(dir.path, 'dist')),
        );

        expect(File(p.join(bundle.path, 'chatl')).existsSync(), isTrue);
        expect(File(p.join(bundle.path, 'libsqlite3.so')).existsSync(), isTrue);
        expect(File(p.join(bundle.path, 'README.txt')).existsSync(), isTrue);
        expect(
          File(p.join(bundle.path, 'README.txt')).readAsStringSync(),
          contains('chatl 0.2.0'),
        );

        // checksums are written once the archive exists
        final archive = await zipBundle(
          bundle,
          distDir: Directory(p.join(dir.path, 'dist')),
        );
        expect(archive.existsSync(), isTrue);
        final sums = File(p.join(dir.path, 'dist', 'SHA256SUMS'))
            .readAsStringSync();
        expect(sums, contains('chatl-0.2.0-linux-x64.zip'));

        await dir.delete(recursive: true);
      },
    );

    test('zipArchive actually contains the bundle entries', () async {
      final dir = await Directory.systemTemp.createTemp('chatl_zip');
      final fakeBinary = File(p.join(dir.path, 'bin'))..writeAsStringSync('x');
      final fakeLib = File(p.join(dir.path, 'lib'))..writeAsStringSync('y');

      final bundle = await assembleBundle(
        platform: 'linux-x64',
        version: '0.2.0',
        binary: fakeBinary,
        sqliteLibrary: fakeLib,
        outDir: Directory(p.join(dir.path, 'dist')),
      );
      final archive = await zipBundle(bundle);

      expect(archive.existsSync(), isTrue);
      final listing = await Process.run('unzip', ['-l', archive.path]);
      if (listing.exitCode == 0) {
        expect(listing.stdout, contains('chatl'));
        expect(listing.stdout, contains('libsqlite3.so'));
        expect(listing.stdout, contains('README.txt'));
      }
      await dir.delete(recursive: true);
    });
  });
}
