import 'dart:io';

import 'package:chatl/src/cli/args.dart';
import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:chatl/src/ui/app.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> argv) async {
  final ChatlArgs args;
  try {
    args = parseArgs(argv);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64); // EX_USAGE
  }

  final config = await Config.load();
  if (config.warnings.isNotEmpty) {
    for (final warning in config.warnings) {
      stderr.writeln('config: $warning');
    }
  }

  final dbDir = p.join(Platform.environment['HOME'] ?? '.', '.config', 'chatl');
  Directory(dbDir).createSync(recursive: true);
  final db = ChatlDatabase(p.join(dbDir, 'chatl.db'));
  final store = DriftSessionStore(db);

  Session? session;
  if (args.sessionId != null) {
    try {
      session = await store.getSession(args.sessionId!);
    } catch (_) {
      stderr.writeln('no such session: ${args.sessionId}');
      exit(2);
    }
  } else if (args.continueLatest) {
    session = await store.latestSession();
    if (session == null) {
      stderr.writeln('no previous session to continue');
    }
  }

  // Fresh sessions start on the `default` profile when defined, else the
  // first configured one (configs need not name a profile "default").
  final initialProfile = config.models.containsKey('default')
      ? 'default'
      : config.models.keys.first;

  session ??= await store.createSession(
    id: store.newSessionId(),
    title: '(untitled)',
    model: initialProfile,
    persona: config.personas.containsKey('default') ? 'default' : config.personas.keys.first,
  );

  final controller = SessionController.resume(
    config: config,
    providerFor: providerForProfile,
    store: store,
    session: session,
  );
  await controller.ready;

  await runApp(ChatlApp(controller: controller));
  await db.close();
}
