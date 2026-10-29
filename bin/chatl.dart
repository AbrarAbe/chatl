import 'dart:io';

import 'package:chatl/src/cli/args.dart';
import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/resolve/fetch.dart';
import 'package:chatl/src/resolve/firecrawl_fetch.dart';
import 'package:chatl/src/resolve/resolver.dart';
import 'package:chatl/src/resolve/search.dart';
import 'package:chatl/src/resolve/search_backend.dart';
import 'package:chatl/src/session/session_controller.dart';
import 'package:chatl/src/state/database.dart';
import 'package:chatl/src/state/session_store.dart';
import 'package:chatl/src/state/sqlite_loader.dart';
import 'package:chatl/src/ui/app.dart';
import 'package:chatl/src/version.dart';
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

  // Prefer the sqlite3 library shipped beside the binary (Linux does not
  // search the executable's directory; Windows does).
  useBundledSqlite();

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
    final fetchBackend = switch (config.fetch.type) {
      'firecrawl' =>
        config.fetch.apiKey == null || config.fetch.apiKey!.isEmpty
            ? null
            : FirecrawlFetchBackend(apiKey: config.fetch.apiKey!, baseUrl: config.fetch.baseUrl),
      _ => config.fetch.reader.isNotEmpty ? ShellFetchBackend(reader: config.fetch.reader) : null,
    };
    final resolver = MentionResolver(
      entries: const [],
      searchResolver: SearchResolver(
        backend: config.search.backend.isNotEmpty
            ? ShellSearchBackend(command: config.search.backend)
            : null,
        maxBytes: config.search.maxBytes,
      ),
      fetchResolver: FetchResolver(backend: fetchBackend, maxBytes: config.fetch.maxBytes),
    );
    final controller = SessionController.resume(
      config: config,
      providerFor: providerForProfile,
      store: store,
      session: s,
      resolver: resolver,
    );
    await controller.ready;
    return controller;
  }

  session ??= await createPersistedSession();
  final controller = await controllerFor(session);

  // `/new`: fresh persisted session, same config/store (spec §MVP Scope).
  Future<SessionController> newSession() async => controllerFor(await createPersistedSession());

  await runApp(ChatlApp(controller: controller, newSession: newSession));
  await db.close();
}
