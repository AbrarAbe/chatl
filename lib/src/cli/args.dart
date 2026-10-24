/// CLI argument parsing (`chatl`, `--continue`, `--session <id>`).
class UsageException implements Exception {
  UsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parsed invocation. See spec §MVP Scope: `--continue` / `--session <id>`.
class ChatlArgs {
  const ChatlArgs({this.continueLatest = false, this.sessionId});

  final bool continueLatest;
  final String? sessionId;
}

const usage = 'usage: chatl [--continue | -c] [--session <id>]';

ChatlArgs parseArgs(List<String> argv) {
  var continueLatest = false;
  String? sessionId;

  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (arg == '--continue' || arg == '-c') {
      continueLatest = true;
    } else if (arg == '--session') {
      if (i + 1 >= argv.length) {
        throw UsageException('--session requires an id.\n$usage');
      }
      sessionId = argv[++i];
    } else if (arg.startsWith('--session=')) {
      final value = arg.substring('--session='.length);
      if (value.isEmpty) {
        throw UsageException('--session requires an id.\n$usage');
      }
      sessionId = value;
    } else {
      throw UsageException('unknown argument "$arg".\n$usage');
    }
  }

  if (continueLatest && sessionId != null) {
    throw UsageException(
      '--continue and --session are mutually exclusive.\n$usage',
    );
  }

  return ChatlArgs(continueLatest: continueLatest, sessionId: sessionId);
}
