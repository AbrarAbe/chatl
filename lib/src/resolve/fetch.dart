/// `@fetch` resolver (Task 1.2 of plan_v0.2.0).
///
/// Fetches a URL's text content via a configured shell reader (e.g. `w3m -dump`,
/// `lynx -dump`, `html2text`) and attaches it as a `[CONTEXT …]` block.
/// Backend-agnostic — any fetch provider implementing [FetchBackend] can be
/// plugged in.
///
/// v1 ships with no built-in backend; configure `fetch.reader` in config.
/// A missing reader fails visibly (spec §MVP Scope).
library;

import 'dart:convert';
import 'dart:io';

import 'resolver.dart';

/// A fetch result: source URL and extracted text body.
class FetchResult {
  const FetchResult({required this.url, required this.body});

  final String url;
  final String body;
}

/// Backend for `@fetch` resolution.
abstract class FetchBackend {
  /// Returns extracted text content for [url].
  Future<FetchResult> fetch(String url);
}

/// A `FetchBackend` that runs a shell reader command to extract text from a URL.
///
/// The command receives the URL as its final argument. Output is read as the
/// extracted page text.
class ShellFetchBackend implements FetchBackend {
  /// Creates a shell-backed fetch backend.
  ///
  /// [reader] is the shell command template. The URL is appended as the
  /// argument. Example: `w3m -dump` or `lynx -dump`.
  const ShellFetchBackend({required this.reader});

  final String reader;

  @override
  Future<FetchResult> fetch(String url) async {
    final process = await Process.start('sh', ['-c', '$reader ${_shellEscape(url)}']);

    final body = await process.stdout.transform(utf8.decoder).join();
    await process.exitCode;

    return FetchResult(url: url, body: body);
  }

  /// Shell-escapes [url] for safe passing to a shell command.
  static String _shellEscape(String url) {
    return "'${url.replaceAll("'", "'\\''")}'";
  }
}

/// Resolves `@fetch <url>` mentions into `[CONTEXT source="url"]` blocks.
class FetchResolver {
  /// Creates a resolver with an optional backend.
  ///
  /// If [_backend] is null, all fetches fail visibly.
  ///
  /// [maxBytes] caps the result body; over-cap content is truncated with a
  /// visible notice, never silently dropped (spec §Decisions).
  const FetchResolver({this._backend, this.maxBytes = _kDefaultMaxBytes});

  final FetchBackend? _backend;
  final int maxBytes;

  /// Resolves `@fetch <url>` into `[CONTEXT ...]` blocks plus `Q: ...`.
  ///
  /// If no backend is configured, returns a visible error block and no
  /// context blocks (spec §MVP Scope: a missing backend fails visibly,
  /// never silently drops).
  Future<ResolveResult> resolve(String url) async {
    if (_backend == null) {
      return ResolveResult(
        requestContent:
            '[CONTEXT ERROR source=fetch]no fetch backend configured[/CONTEXT]\nQ: $url',
        blocks: const [],
        failures: [ResolveFailure(source: 'fetch', message: 'no fetch backend configured')],
      );
    }

    FetchResult result;
    try {
      result = await _backend.fetch(url);
    } catch (e) {
      return ResolveResult(
        requestContent: '[CONTEXT ERROR source=fetch]$e[/CONTEXT]\nQ: $url',
        blocks: const [],
        failures: [ResolveFailure(source: 'fetch', message: '$e')],
      );
    }

    final body = truncateWithNotice(result.body, maxBytes);

    final blocks = <ContextBlock>[];
    blocks.add(ContextBlock(source: url, body: body));

    return ResolveResult(
      requestContent: _buildRequestContent(result, url),
      blocks: List.unmodifiable(blocks),
      failures: const [],
      sources: [
        {'url': url, 'title': result.body.isNotEmpty ? result.body.split('\n').first : url},
      ],
    );
  }

  String _buildRequestContent(FetchResult result, String url) {
    final buf = StringBuffer();
    buf.writeln('[CONTEXT source="$url"]');
    buf.writeln(truncateWithNotice(result.body, maxBytes));
    buf.writeln('[/CONTEXT]');
    buf.writeln('Q: $url');
    return buf.toString().trimRight();
  }
}

const int _kDefaultMaxBytes = 100 * 1024;
