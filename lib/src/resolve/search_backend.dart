/// Shell-based `@search` resolver backend (Task 1.1).
///
/// Executes a shell command (e.g. `ddgr`, `brave`, `tavily`, or a custom
/// script) and parses the output into `[SearchResult]` records.
///
/// The command receives the user query as its final argument. The backend
/// is expected to emit one result per line in TSV format:
///   title\turl\tsnippet
///
/// Lines that don't parse as TSV are skipped.
library;

import 'dart:convert';
import 'dart:io';

import 'search.dart';

/// A `SearchBackend` that runs a shell command to perform web searches.
///
/// The command receives the search query as its final argument. Output is
/// parsed as tab-separated values: title, URL, snippet. Lines that don't
/// parse are skipped.
class ShellSearchBackend implements SearchBackend {
  /// Creates a shell-backed search backend.
  ///
  /// [command] is the shell command template. The query is appended as the
  /// argument. Example: `ddgr --json` or `brave --search`.
  const ShellSearchBackend({required this.command});

  final String command;

  @override
  Future<List<SearchResult>> search(String query) async {
    final process = await Process.start('sh', ['-c', '$command ${_shellEscape(query)}']);

    final results = <SearchResult>[];
    await for (final line
        in process.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.isEmpty) continue;

      final parts = lineTrimmed.split('\t');
      if (parts.length < 3) continue; // Need at least title, url, snippet

      results.add(SearchResult(title: parts[0], url: parts[1], snippet: parts.skip(2).join('\t')));
    }

    await process.exitCode;

    return results;
  }

  /// Shell-escapes [query] for safe passing to a shell command.
  static String _shellEscape(String query) {
    // Simple escaping: wrap in single quotes and escape any single quotes
    // within by ending the quote, adding an escaped quote, and restarting.
    return "'${query.replaceAll("'", "'\\''")}'";
  }
}
