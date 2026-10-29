/// Client-side `@` mention resolution (spec §The `@` resolver layer).
///
/// Mentions expand **before** the request is built: `user input → @-resolver →
/// [context blocks] + message → Provider.chat`. The model therefore never sees
/// the syntax and cannot learn or misuse it.
library;

import 'dart:convert';

import 'fetch.dart';
import 'search.dart';

/// One piece of attached context, rendered as a `[CONTEXT …]` block.
class ContextBlock {
  const ContextBlock({required this.source, required this.body});

  final String source;
  final String body;
}

/// A resolver that failed; surfaced inline so nothing is silently dropped.
class ResolveFailure {
  const ResolveFailure({required this.source, required this.message});

  final String source;
  final String message;
}

/// The outcome of resolving one input line.
class ResolveResult {
  const ResolveResult({
    required this.requestContent,
    required this.blocks,
    required this.failures,
    this.sources = const [],
  });

  /// What actually goes to the provider: rendered blocks followed by
  /// `Q: <leftover text>`. Never contains `@` syntax.
  final String requestContent;

  final List<ContextBlock> blocks;
  final List<ResolveFailure> failures;

  /// Citation sources: `[{url, title}]` pairs from @search / @fetch results,
  /// written to `messages.sources` on persist.
  final List<Map<String, String>> sources;
}

/// One resolver entry: a reserved `@` name and its resolution function.
class ResolverEntry {
  const ResolverEntry({required this.name, required this.resolve, this.takesArgument = false});

  final String name;

  /// Consumes the next whitespace-delimited token as its argument
  /// (`@fetch <url>`); false for verbs like `@time`.
  final bool takesArgument;

  final Future<ContextBlock> Function(String? argument) resolve;
}

/// Resolves `@` mentions against the registered [ResolverEntry] set.
///
/// v1 ships **zero** resolvers (spec §Post-v1 Roadmap: `@fetch`/`@search` come
/// later); this class exists so adding one is config plus a function, not a
/// rework of the request path.
class MentionResolver {
  /// Creates a resolver with the given entries.
  ///
  /// If [searchResolver] is provided, `@search <query>` mentions are delegated
  /// to it. If no backend is configured on the search resolver, `@search`
  /// mentions fail visibly.
  ///
  /// If [fetchResolver] is provided, `@fetch <url>` mentions are delegated
  /// to it. If no backend is configured on the fetch resolver, `@fetch`
  /// mentions fail visibly.
  const MentionResolver({this.entries = const [], this.searchResolver, this.fetchResolver});

  final List<ResolverEntry> entries;
  final SearchResolver? searchResolver;
  final FetchResolver? fetchResolver;

  /// A mention is `@` at line start or after whitespace, followed by a
  /// `[A-Za-z0-9_-]` name — so `a@b.com` is never a mention.
  static final _mentionPattern = RegExp(r'(?:^|\s)@([A-Za-z0-9_-]+)');

  /// Resolves [input] against the registered resolver entries.
  ///
  /// If no resolvers are registered, returns [input] unchanged.
  Future<ResolveResult> resolve(String input) async {
    final expansions = <_Expansion>[];
    final leftovers = StringBuffer();
    var cursor = 0;
    final sources = <Map<String, String>>[];

    for (final match in _mentionPattern.allMatches(input)) {
      final entry = _entryFor(match.group(1)!);

      if (match.group(1) == 'search') {
        final searchResolverLocal = searchResolver;
        if (searchResolverLocal != null) {
          // text before the mention survives (its leading space is dropped)
          leftovers.write(input.substring(cursor, match.start));
          cursor = match.end;

          String? argument;
          if (entry != null && entry.takesArgument) {
            final rest = input.substring(cursor);
            final trimmed = rest.trimLeft();
            final gap = rest.length - trimmed.length;
            final token = RegExp(r'^\S+').firstMatch(trimmed);
            if (token != null) {
              argument = token.group(0);
              cursor += gap + token.end;
            }
          }

          final source = argument == null ? 'search' : 'search:$argument';
          try {
            final searchResult = await searchResolverLocal.resolve(argument ?? '');
            sources.addAll(searchResult.sources);
            expansions.addAll(await _resolveSearch(searchResult, source));
          } catch (e) {
            expansions.add(_Expansion(source, null, '$e'));
          }
          continue;
        }
      }

      // If this is an @fetch mention and we have a fetch resolver,
      // delegate to it. Otherwise use the registered resolver entry.
      if (match.group(1) == 'fetch') {
        final fetchResolverLocal = fetchResolver;
        if (fetchResolverLocal != null) {
          leftovers.write(input.substring(cursor, match.start));
          cursor = match.end;

          String? argument;
          if (entry != null && entry.takesArgument) {
            final rest = input.substring(cursor);
            final trimmed = rest.trimLeft();
            final gap = rest.length - trimmed.length;
            final token = RegExp(r'^\S+').firstMatch(trimmed);
            if (token != null) {
              argument = token.group(0);
              cursor += gap + token.end;
            }
          }

          final source = argument == null ? 'fetch' : 'fetch:$argument';
          try {
            final fetchResult = await fetchResolverLocal.resolve(argument ?? '');
            sources.addAll(fetchResult.sources);
            expansions.addAll(await _resolveFetch(fetchResult, source));
          } catch (e) {
            expansions.add(_Expansion(source, null, '$e'));
          }
          continue;
        }
      }

      if (entry == null) continue; // unknown → stays literal

      // text before the mention survives (its leading space is dropped)
      leftovers.write(input.substring(cursor, match.start));
      cursor = match.end;

      String? argument;
      if (entry.takesArgument) {
        final rest = input.substring(cursor);
        final trimmed = rest.trimLeft();
        final gap = rest.length - trimmed.length;
        final token = RegExp(r'^\S+').firstMatch(trimmed);
        if (token != null) {
          argument = token.group(0);
          cursor += gap + token.end;
        }
      }
      leftovers.write(' ');

      final source = argument == null ? entry.name : '${entry.name}:$argument';
      try {
        expansions.add(_Expansion(source, await entry.resolve(argument)));
      } catch (e) {
        expansions.add(_Expansion(source, null, '$e'));
      }
    }

    if (expansions.isEmpty) {
      // pure passthrough: byte-for-byte identical to the input
      return ResolveResult(requestContent: input, blocks: const [], failures: const []);
    }

    leftovers.write(input.substring(cursor));
    final question = _cleanup(leftovers.toString());

    final rendered = StringBuffer();
    final blocks = <ContextBlock>[];
    final failures = <ResolveFailure>[];
    for (final expansion in expansions) {
      if (expansion.failure != null) {
        failures.add(ResolveFailure(source: expansion.source, message: expansion.failure!));
        rendered.writeln(
          '[CONTEXT ERROR source="${expansion.source}"]${expansion.failure}[/CONTEXT]',
        );
      } else {
        blocks.add(expansion.block!);
        rendered.writeln('[CONTEXT source="${expansion.block!.source}"]');
        rendered.writeln(expansion.block!.body);
        rendered.writeln('[/CONTEXT]');
      }
    }
    if (question.isNotEmpty) rendered.writeln('Q: $question');

    return ResolveResult(
      requestContent: rendered.toString().trimRight(),
      blocks: List.unmodifiable(blocks),
      failures: List.unmodifiable(failures),
      sources: sources,
    );
  }

  ResolverEntry? _entryFor(String name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  Future<List<_Expansion>> _resolveSearch(ResolveResult searchResult, String source) async {
    final blocks = <_Expansion>[];
    for (final block in searchResult.blocks) {
      blocks.add(_Expansion(source, block));
    }
    for (final failure in searchResult.failures) {
      blocks.add(_Expansion(source, null, failure.message));
    }
    return blocks;
  }

  Future<List<_Expansion>> _resolveFetch(ResolveResult fetchResult, String source) async {
    final blocks = <_Expansion>[];
    for (final block in fetchResult.blocks) {
      blocks.add(_Expansion(source, block));
    }
    for (final failure in fetchResult.failures) {
      blocks.add(_Expansion(source, null, failure.message));
    }
    return blocks;
  }

  String _cleanup(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r'^[—–-]\s*'), '').trim();
}

class _Expansion {
  _Expansion(this.source, this.block, [this.failure]);

  final String source;
  final ContextBlock? block;
  final String? failure;
}

/// Truncates [body] to [maxBytes] UTF-8 bytes, appending a visible notice
/// when truncation occurs. Never silently drops content.
String truncateWithNotice(String body, int maxBytes) {
  final bytes = utf8.encode(body);
  if (bytes.length <= maxBytes) return body;

  // Decode back up to the cap boundary to avoid splitting a multi-byte char.
  final truncated = utf8.decode(bytes.sublist(0, maxBytes));
  final over = bytes.length - maxBytes;
  return '$truncated\n[... truncated: $over bytes over cap ...]';
}
