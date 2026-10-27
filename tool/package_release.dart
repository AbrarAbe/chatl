/// Builds a platform release bundle (Task 0.3 of plan_v0.2.0).
///
/// Produces `dist/chatl-<version>-<platform>.zip` containing the compiled
/// binary, the bundled sqlite3 library and a short README, then appends the
/// archive's checksum to `dist/SHA256SUMS` (which the install scripts verify).
///
/// Usage:
///   dart run tool/package_release.dart --version 0.2.0
///   dart run tool/package_release.dart --version 0.2.0 --platform windows-x64 \
///        --sqlite-src path/to/sqlite3.dll --skip-compile --binary path/to/chatl.exe
///
/// Linux takes the sqlite3 library from the system (`--sqlite-src` to override);
/// Windows artifacts are built in CI where the official DLL is downloaded.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String zipNameFor({required String version, required String platform}) =>
    'chatl-$version-$platform.zip';

String bundleBinaryName(String platform) =>
    platform.startsWith('windows') ? 'chatl.exe' : 'chatl';

String bundleSqliteName(String platform) =>
    platform.startsWith('windows') ? 'sqlite3.dll' : 'libsqlite3.so';

String bundleReadmeName() => 'README.txt';

/// `"<sha256>  <basename>"`, the format `sha256sum -c` expects.
Future<String> sha256Line(File file) async {
  final digest = sha256.convert(await file.readAsBytes());
  return '$digest  ${p.basename(file.path)}';
}

/// Lays out the bundle directory: binary, sqlite library and a short README.
/// Checksums are written by [zipBundle] once the archive exists.
Future<Directory> assembleBundle({
  required String platform,
  required String version,
  required File binary,
  required File sqliteLibrary,
  required Directory outDir,
}) async {
  final bundle = Directory(p.join(outDir.path, 'chatl-$platform'));
  if (bundle.existsSync()) bundle.deleteSync(recursive: true);
  bundle.createSync(recursive: true);

  binary.copySync(p.join(bundle.path, bundleBinaryName(platform)));
  sqliteLibrary.copySync(p.join(bundle.path, bundleSqliteName(platform)));

  File(p.join(bundle.path, bundleReadmeName())).writeAsStringSync('''
chatl $version ($platform)

Run:
  ./${bundleBinaryName(platform)}

Keep ${bundleSqliteName(platform)} in this same directory: chatl uses it for
sessions. Configuration and the session database live in
~/.config/chatl/config.yaml and ~/.config/chatl/chatl.db.

Note: on Linux, extract the whole archive — the binary looks for
${bundleSqliteName(platform)} next to itself.
''');

  outDir.createSync(recursive: true);
  return bundle;
}

/// Zips [bundle] into `dist/`, then appends its checksum to `SHA256SUMS`.
Future<File> zipBundle(Directory bundle, {Directory? distDir}) async {
  final dist = distDir ?? Directory(p.join(Directory.current.path, 'dist'));
  dist.createSync(recursive: true);

  final platform = p.basename(bundle.path).replaceFirst('chatl-', '');
  final archiveName = zipNameFor(
    version: _versionOfBundle(bundle),
    platform: platform,
  );
  final archive = File(p.join(dist.path, archiveName));
  if (archive.existsSync()) archive.deleteSync();

  final result = await Process.run('zip', [
    '-r',
    '-q',
    archive.path,
    p.basename(bundle.path),
  ], workingDirectory: p.dirname(bundle.path));
  if (result.exitCode != 0) {
    throw ProcessException(
      'zip',
      ['-r', archive.path, bundle.path],
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }

  final sums = File(p.join(dist.path, 'SHA256SUMS'));
  final existing = sums.existsSync() ? sums.readAsStringSync() : '';
  sums.writeAsStringSync('$existing${await sha256Line(archive)}\n');
  return archive;
}

String _versionOfBundle(Directory bundle) {
  final readme = File(p.join(bundle.path, bundleReadmeName()));
  final first = readme.readAsLinesSync().first; // "chatl 0.2.0 (linux-x64)"
  return first.split(' ')[1];
}

Future<void> main(List<String> argv) async {
  var version = '';
  var platform = Platform.isWindows
      ? 'windows-x64'
      : Platform.isMacOS
      ? 'macos-arm64'
      : 'linux-x64';
  String? sqliteSrc;
  String? binaryPath;
  for (var i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--version':
        if (++i >= argv.length) _fail('--version requires a value');
        version = argv[i];
      case '--platform':
        if (++i >= argv.length) _fail('--platform requires a value');
        platform = argv[i];
      case '--sqlite-src':
        if (++i >= argv.length) _fail('--sqlite-src requires a value');
        sqliteSrc = argv[i];
      case '--binary':
        if (++i >= argv.length) _fail('--binary requires a value');
        binaryPath = argv[i];
      default:
        _fail('unknown argument "${argv[i]}"');
    }
  }

  if (version.isEmpty) {
    _fail('usage: dart run tool/package_release.dart --version X.Y.Z');
  }

  final tmp = Directory.systemTemp.createTempSync('chatl-package');
  final binary = await _binary(platform, version, tmp, binaryPath);
  final sqlite = _sqlite(platform, sqliteSrc);

  final out = Directory(p.join(Directory.current.path, 'dist'));
  // A packaging run owns its dist/SHA256SUMS: start it clean so re-runs do not
  // accumulate duplicate lines.
  final sums = File(p.join(out.path, 'SHA256SUMS'));
  if (sums.existsSync()) sums.deleteSync();
  out.createSync(recursive: true);
  final bundle = await assembleBundle(
    platform: platform,
    version: version,
    binary: binary,
    sqliteLibrary: sqlite,
    outDir: out,
  );
  final archive = await zipBundle(bundle, distDir: out);

  stdout.writeln('packaged ${p.basename(archive.path)}');
  stdout.writeln(await sha256Line(archive));
}

Future<File> _binary(
  String platform,
  String version,
  Directory tmp,
  String? explicit,
) async {
  if (explicit != null) return File(explicit);
  final target = p.join(tmp.path, bundleBinaryName(platform));
  stdout.writeln('compiling bin/chatl.dart → $target');
  final result = await Process.run('dart', [
    'compile',
    'exe',
    'bin/chatl.dart',
    '-DCHATL_VERSION=$version',
    '-o',
    target,
  ]);
  if (result.exitCode != 0) {
    _fail('dart compile exe failed:\n${result.stdout}${result.stderr}');
  }
  return File(target);
}

File _sqlite(String platform, String? explicit) {
  if (explicit != null) return File(explicit);
  if (platform.startsWith('windows')) {
    _fail(
      'Windows bundles need the official sqlite3.dll; pass --sqlite-src '
      '(CI downloads it before packaging).',
    );
  }
  final candidates = [
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib64/libsqlite3.so.0',
    '/usr/lib/libsqlite3.so.0',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate);
  }
  final ldconfig = Process.runSync('ldconfig', ['-p']);
  if (ldconfig.exitCode == 0) {
    for (final line in const LineSplitter().convert('${ldconfig.stdout}')) {
      if (line.contains('libsqlite3.so')) {
        final path = line.split('=>').last.trim();
        if (File(path).existsSync()) return File(path);
      }
    }
  }
  _fail('no system libsqlite3 found; pass --sqlite-src');
}

Never _fail(String message) {
  stderr.writeln('package_release: $message');
  exit(1);
}
