/// Client-side `@` mention resolution (spec §The `@` resolver layer).
///
/// Mentions expand **before** the request is built: `user input → @-resolver →
/// [context blocks] + message → Provider.chat`. The model therefore never sees
/// the syntax and cannot learn or misuse it.
library;

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

/// A registered resolver: one reserved `@` name (spec §Reserved names: exactly
/// the registered set; unknown tokens always pass through literally).
class ResolverEntry {
  const ResolverEntry({
    required this.name,
    required this.resolve,
    this.takesArgument = false,
  });

  final String name;

  /// Consumes the next whitespace-delimited token as its argument
  /// (`@fetch <url>`); false for verbs like `@time`.
  final bool takesArgument;

  final Future<ContextBlock> Function(String? argument) resolve;
}

/// The outcome of resolving one input line.
class ResolveResult {
  const ResolveResult({
    required this.requestContent,
    required this.blocks,
    required this.failures,
  });

  /// What actually goes to the provider: rendered blocks followed by
  /// `Q: <leftover text>`. Never contains `@` syntax.
  final String requestContent;

  final List<ContextBlock> blocks;
  final List<ResolveFailure> failures;
}

/// Resolves `@` mentions against the registered [ResolverEntry] set.
///
/// v1 ships **zero** resolvers (spec §Post-v1 Roadmap: `@fetch`/`@search` come
/// later); this class exists so adding one is config plus a function, not a
/// rework of the request path.
class MentionResolver {
  const MentionResolver({this.entries = const []});

  final List<ResolverEntry> entries;

  ResolverEntry? _entryFor(String name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  /// A mention is `@` at line start or after whitespace, followed by a
  /// `[A-Za-z0-9_-]` name — so `a@b.com` is never a mention.
  static final _mentionPattern = RegExp(r'(?:^|\s)@([A-Za-z0-9_-]+)');

  Future<ResolveResult> resolve(String input) async {
    final expansions = <_Expansion>[];
    final leftovers = StringBuffer();
    var cursor = 0;

    for (final match in _mentionPattern.allMatches(input)) {
      final entry = _entryFor(match.group(1)!);
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
      return ResolveResult(
        requestContent: input,
        blocks: const [],
        failures: const [],
      );
    }

    leftovers.write(input.substring(cursor));
    final question = _cleanup(leftovers.toString());

    final rendered = StringBuffer();
    final blocks = <ContextBlock>[];
    final failures = <ResolveFailure>[];
    for (final expansion in expansions) {
      if (expansion.failure != null) {
        failures.add(
          ResolveFailure(source: expansion.source, message: expansion.failure!),
        );
        rendered.writeln(
          '[CONTEXT ERROR source="${expansion.source}"]${expansion.failure}[/CONTEXT]',
        );
      } else {
        blocks.add(expansion.block!);
        rendered.writeln('[CONTEXT source="${expansion.source}"]');
        rendered.writeln(expansion.block!.body);
        rendered.writeln('[/CONTEXT]');
      }
    }
    if (question.isNotEmpty) rendered.writeln('Q: $question');

    return ResolveResult(
      requestContent: rendered.toString().trimRight(),
      blocks: List.unmodifiable(blocks),
      failures: List.unmodifiable(failures),
    );
  }

  /// Collapses whitespace and strips a leading separator dash left behind by
  /// `@fetch <url> — question` (spec §The `@` resolver layer example).
  String _cleanup(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'^[—–-]\s*'), '')
      .trim();
}

class _Expansion {
  _Expansion(this.source, this.block, [this.failure]);

  final String source;
  final ContextBlock? block;
  final String? failure;
}
