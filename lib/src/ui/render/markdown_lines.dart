import 'package:markdown/markdown.dart' as md;

/// How a rendered line should be styled by the terminal widget.
enum LineStyle { h1, h2, h3, h4, h5, h6, paragraph, bullet, ordered, codeBlock, quote, table, rule }

/// One display line: text plus the style the widget maps to a terminal look.
class RenderedLine {
  const RenderedLine(this.text, this.style);

  final String text;
  final LineStyle style;

  @override
  String toString() => '${style.name}:$text';
}

/// Renders markdown to terminal lines using `package:markdown`'s AST.
///
/// Contract: one `RenderedLine` per visible terminal row, no blank spacer
/// rows, inline formatting flattened (`**x**` → `x`). Called once per completed
/// block and once per flush for the open block (ADR 0003), so it stays cheap
/// and allocation-light.
List<RenderedLine> renderMarkdown(String source) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
  final lines = <RenderedLine>[];
  for (final node in document.parse(source)) {
    _renderBlock(node, lines);
  }
  return lines;
}

void _renderBlock(md.Node node, List<RenderedLine> out) {
  if (node is! md.Element) {
    final text = node.textContent.trim();
    if (text.isNotEmpty) out.add(RenderedLine(text, LineStyle.paragraph));
    return;
  }

  switch (node.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.parse(node.tag.substring(1));
      out.add(RenderedLine(node.textContent.trim(), _headingStyle(level)));
    case 'p':
      final text = node.textContent.trim();
      if (text.isNotEmpty) out.add(RenderedLine(text, LineStyle.paragraph));
    case 'pre':
      for (final line in node.textContent.trimRight().split('\n')) {
        out.add(RenderedLine(line, LineStyle.codeBlock));
      }
    case 'ul':
      for (final item in _kids(node)) {
        final text = item.textContent.trim();
        out.add(RenderedLine(text.isEmpty ? '•' : '• $text', LineStyle.bullet));
      }
    case 'ol':
      var index = 1;
      for (final item in _kids(node)) {
        final text = item.textContent.trim();
        out.add(RenderedLine('${index++}. $text', LineStyle.ordered));
      }
    case 'blockquote':
      final text = node.textContent.trim();
      if (text.isNotEmpty) {
        for (final line in text.split('\n')) {
          out.add(RenderedLine('> ${line.trim()}', LineStyle.quote));
        }
      }
    case 'table':
      for (final row in _rows(node)) {
        final cells = _kids(row).map((cell) => cell.textContent.trim()).toList();
        out.add(RenderedLine(cells.join(' | '), LineStyle.table));
      }
    case 'hr':
      out.add(RenderedLine('─' * 20, LineStyle.rule));
    default:
      _renderBlock(_unwrapInline(node), out);
  }
}

LineStyle _headingStyle(int level) => switch (level) {
  1 => LineStyle.h1,
  2 => LineStyle.h2,
  3 => LineStyle.h3,
  4 => LineStyle.h4,
  5 => LineStyle.h5,
  _ => LineStyle.h6,
};

/// Children of [node] when it is an element.
List<md.Node> _kids(md.Node node) =>
    node is md.Element ? (node.children ?? <md.Node>[]) : <md.Node>[];

/// Table rows, which GitHub-flavoured markdown nests under thead/tbody.
Iterable<md.Element> _rows(md.Element table) sync* {
  for (final child in _kids(table)) {
    if (child is! md.Element) continue;
    if (child.tag == 'tr') {
      yield child;
    } else {
      yield* _rows(child);
    }
  }
}

/// Fallback for containers this renderer does not model: emit their text as a
/// paragraph rather than recursing into unknown structure.
md.Node _unwrapInline(md.Element element) => md.Text(element.textContent);
