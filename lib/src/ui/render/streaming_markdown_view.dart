import 'package:nocterm/nocterm.dart';

import 'markdown_block_cache.dart';
import 'markdown_lines.dart';

/// Renders streaming markdown incrementally (ADR 0003).
///
/// Completed blocks are rendered once and cached in state — a growing
/// transcript therefore re-parses only the open block per update, which the
/// spike measured at p95 0.47 ms versus 12.2 ms for whole-document reparse.
/// With [markdown] false the text renders as plain lines, verbatim.
class StreamingMarkdownView extends StatefulComponent {
  const StreamingMarkdownView({
    super.key,
    required this.text,
    this.markdown = true,
    this.onBlockRendered,
  });

  final String text;
  final bool markdown;

  /// Test hook: called once per completed block render and per open-block
  /// render, so incrementality is observable.
  final void Function({required bool completed})? onBlockRendered;

  @override
  State<StreamingMarkdownView> createState() => _StreamingMarkdownViewState();
}

class _StreamingMarkdownViewState extends State<StreamingMarkdownView> {
  final MarkdownBlockCache _cache = MarkdownBlockCache();

  @override
  Component build(BuildContext context) {
    if (!component.markdown) {
      final lines = component.text.split('\n');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) Text(lines[i], key: ValueKey('plain-$i')),
        ],
      );
    }

    _cache.update(component.text, onRender: component.onBlockRendered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var block = 0; block < _cache.completedLines.length; block++)
          for (var line = 0; line < _cache.completedLines[block].length; line++)
            _line(_cache.completedLines[block][line],
                key: ValueKey('frozen-$block-$line')),
        for (var line = 0; line < _cache.openLines.length; line++)
          _line(_cache.openLines[line], key: ValueKey('open-$line')),
      ],
    );
  }

  Component _line(RenderedLine line, {required Key key}) =>
      Text(line.text, key: key, style: styleFor(line.style));
}

/// Terminal look per markdown line style (no font sizes in a terminal, so
/// hierarchy comes from colour and weight).
TextStyle styleFor(LineStyle style) => switch (style) {
  LineStyle.h1 => const TextStyle(color: Colors.brightWhite, fontWeight: FontWeight.bold),
  LineStyle.h2 => const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
  LineStyle.h3 => const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
  LineStyle.h4 ||
  LineStyle.h5 ||
  LineStyle.h6 => const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
  LineStyle.paragraph => const TextStyle(color: Colors.white),
  LineStyle.bullet || LineStyle.ordered => const TextStyle(color: Colors.white),
  LineStyle.codeBlock => const TextStyle(color: Colors.yellow),
  LineStyle.quote => const TextStyle(color: Colors.gray),
  LineStyle.table => const TextStyle(color: Colors.cyan),
  LineStyle.rule => const TextStyle(color: Colors.gray),
};
