import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

/// Resolves the path of a `sqlite3` library shipped beside the executable.
///
/// Linux does not search the executable's directory when loading shared
/// libraries, so a bundled `libsqlite3.so` would be ignored without an explicit
/// override. Windows *does* search the application directory, so it needs
/// nothing. Returns null when nothing is bundled (use the system library).
///
/// The [exists] probe is injectable so the resolution is testable without a
/// real bundle.
String? bundledSqlitePath({
  required String executablePath,
  required String platform,
  required bool Function(String candidate) exists,
}) {
  if (platform != 'linux') return null;
  final candidate = p.join(p.dirname(executablePath), 'libsqlite3.so');
  return exists(candidate) ? candidate : null;
}

/// Points `package:sqlite3` at the bundled library when one ships beside this
/// executable. Called from the entrypoint before any database is opened.
void useBundledSqlite({String? platform, String? executablePath}) {
  final resolved = bundledSqlitePath(
    executablePath: executablePath ?? Platform.resolvedExecutable,
    platform: platform ?? Platform.operatingSystem,
    exists: (candidate) => File(candidate).existsSync(),
  );
  if (resolved == null) return;
  open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open(resolved));
}
