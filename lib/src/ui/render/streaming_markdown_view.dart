import 'package:nocterm/nocterm.dart';

import '../theme.dart';
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
    this.theme = ChatlTheme.dark,
    this.onBlockRendered,
  });

  final String text;
  final bool markdown;
  final ChatlTheme theme;

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
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              key: ValueKey('plain-$i'),
              style: TextStyle(color: component.theme.paragraph),
            ),
        ],
      );
    }

    _cache.update(component.text, onRender: component.onBlockRendered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var block = 0; block < _cache.completedLines.length; block++)
          for (var line = 0; line < _cache.completedLines[block].length; line++)
            _line(
              _cache.completedLines[block][line],
              key: ValueKey('frozen-$block-$line'),
            ),
        for (var line = 0; line < _cache.openLines.length; line++)
          _line(_cache.openLines[line], key: ValueKey('open-$line')),
      ],
    );
  }

  Component _line(RenderedLine line, {required Key key}) =>
      Text(line.text, key: key, style: component.theme.styleFor(line.style));
}
