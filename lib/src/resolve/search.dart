/// `@search` resolver (Task 1.1 of plan_v0.2.0).
///
/// Searches for context to attach to a user turn. Backend-agnostic — any
/// search provider implementing [SearchBackend] can be plugged in.
///
/// v1 ships with no built-in backend; configure `search.backend` in config.
/// A missing backend fails visibly (spec §MVP Scope).
library;

import 'resolver.dart';

/// A search result: title, URL, and snippet text.
class SearchResult {
  const SearchResult({required this.title, required this.url, required this.snippet});

  final String title;
  final String url;
  final String snippet;
}

/// Backend for `@search` resolution.
abstract class SearchBackend {
  /// Returns ranked search results for [query].
  Future<List<SearchResult>> search(String query);
}

/// Resolves `@search <query>` mentions into `[CONTEXT source="search"]` blocks.
class SearchResolver {
  /// Creates a resolver with an optional backend.
  ///
  /// If [_backend] is null, all searches fail visibly.
  ///
  /// [maxBytes] caps each result body; over-cap content is truncated with a
  /// visible notice, never silently dropped (spec §Decisions).
  const SearchResolver({this._backend, this.maxBytes = _kDefaultMaxBytes});

  final SearchBackend? _backend;
  final int maxBytes;

  /// Resolves `@search <query>` into `[CONTEXT ...]` blocks plus `Q: ...`.
  ///
  /// If no backend is configured, returns a visible error block and no
  /// context blocks (spec §MVP Scope: a missing backend fails visibly,
  /// never silently drops).
  Future<ResolveResult> resolve(String query) async {
    if (_backend == null) {
      return ResolveResult(
        requestContent:
            '[CONTEXT ERROR source=search]no search backend configured[/CONTEXT]\nQ: $query',
        blocks: const [],
        failures: [ResolveFailure(source: 'search', message: 'no search backend configured')],
      );
    }

    final results = await _backend.search(query);

    final blocks = <ContextBlock>[];
    final sources = <Map<String, String>>[];
    for (final result in results) {
      final body = truncateWithNotice(
        '${result.title}\n${result.url}\n${result.snippet}',
        maxBytes,
      );
      blocks.add(ContextBlock(source: 'search', body: body));
      sources.add({'url': result.url, 'title': result.title});
    }

    return ResolveResult(
      requestContent: _buildRequestContent(results, query),
      blocks: List.unmodifiable(blocks),
      failures: const [],
      sources: sources,
    );
  }

  String _buildRequestContent(List<SearchResult> results, String query) {
    final buf = StringBuffer();
    for (final result in results) {
      final body = truncateWithNotice(
        '${result.title}\n${result.url}\n${result.snippet}',
        maxBytes,
      );
      buf.writeln('[CONTEXT source="search"]');
      buf.writeln(body);
      buf.writeln('[/CONTEXT]');
    }
    buf.writeln('Q: $query');
    return buf.toString().trimRight();
  }
}

const int _kDefaultMaxBytes = 100 * 1024;
