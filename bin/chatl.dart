import 'dart:io';

import 'package:chatl/src/cli/args.dart';
import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:chatl/src/version.dart';
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

  if (args.showVersion) {
    stdout.writeln('chatl $chatlVersion');
    return;
  }

  final config = await Config.load();
  for (final warning in config.warnings) {
    stderr.writeln('config: $warning');
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
  final initialPersona = config.personas.containsKey('default')
      ? 'default'
      : config.personas.keys.first;

  Future<Session> createPersistedSession() => store.createSession(
    id: store.newSessionId(),
    title: '(untitled)',
    model: initialProfile,
    persona: initialPersona,
  );

  Future<SessionController> controllerFor(Session s) async {
    final controller = SessionController.resume(
      config: config,
      providerFor: providerForProfile,
      store: store,
      session: s,
    );
    await controller.ready;
    return controller;
  }

  session ??= await createPersistedSession();
  final controller = await controllerFor(session);

  // `/new`: fresh persisted session, same config/store (spec §MVP Scope).
  Future<SessionController> newSession() async =>
      controllerFor(await createPersistedSession());

  await runApp(ChatlApp(controller: controller, newSession: newSession));
  await db.close();
}
