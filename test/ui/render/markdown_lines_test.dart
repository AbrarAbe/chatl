import 'package:chatl/src/ui/render/markdown_lines.dart';
import 'package:test/test.dart';

String plain(List<RenderedLine> lines) => lines.map((l) => l.text).join('\n');

void main() {
  group('renderMarkdown (golden strings, spec Success #3)', () {
    test('headings keep their text and are styled by level', () {
      final lines = renderMarkdown('# One\n\n## Two\n\n### Three');

      expect(plain(lines), 'One\nTwo\nThree');
      expect(lines.map((l) => l.style).toList(), [LineStyle.h1, LineStyle.h2, LineStyle.h3]);
    });

    test('emphasis markers are stripped, text preserved', () {
      final lines = renderMarkdown('some **bold** and *italic* and `code`');
      expect(plain(lines), 'some bold and italic and code');
      expect(lines.single.style, LineStyle.paragraph);
    });

    test('bullet lists become bullet lines', () {
      final lines = renderMarkdown('- first\n- second');
      expect(plain(lines), '• first\n• second');
      expect(lines.map((l) => l.style).toList(), [LineStyle.bullet, LineStyle.bullet]);
    });

    test('ordered lists keep their numbering', () {
      final lines = renderMarkdown('1. first\n2. second');
      expect(plain(lines), '1. first\n2. second');
      expect(lines.first.style, LineStyle.ordered);
    });

    test('fenced code blocks are preserved verbatim and styled as code', () {
      final lines = renderMarkdown('```dart\nfinal x = 1;\n```');
      expect(plain(lines), 'final x = 1;');
      expect(lines.single.style, LineStyle.codeBlock);
    });

    test('unclosed fence still renders as code (no corruption)', () {
      final lines = renderMarkdown('```dart\nfinal x = 1;');
      expect(plain(lines), 'final x = 1;');
      expect(lines.single.style, LineStyle.codeBlock);
    });

    test('complete tables render as aligned rows', () {
      final lines = renderMarkdown('| a | b |\n|---|---|\n| 1 | 2 |');
      expect(plain(lines), 'a | b\n1 | 2');
      expect(lines.every((l) => l.style == LineStyle.table), isTrue);
    });

    test('half-streamed table degrades to text, not a crash', () {
      final lines = renderMarkdown('| a | b |\n|---');
      expect(plain(lines), contains('a | b'));
      expect(
        lines.any((l) => l.style == LineStyle.paragraph || l.style == LineStyle.table),
        isTrue,
      );
    });

    test('blockquotes are prefixed', () {
      final lines = renderMarkdown('> quoted words');
      expect(plain(lines), '> quoted words');
      expect(lines.single.style, LineStyle.quote);
    });

    test('thematic breaks render as a rule', () {
      final lines = renderMarkdown('---');
      expect(lines.single.style, LineStyle.rule);
      expect(lines.single.text.isNotEmpty, isTrue);
    });

    test('links keep their label', () {
      final lines = renderMarkdown('see [the docs](https://x) here');
      expect(plain(lines), 'see the docs here');
    });

    test('plain text without markdown passes through unchanged', () {
      final lines = renderMarkdown('just a sentence');
      expect(plain(lines), 'just a sentence');
      expect(lines.single.style, LineStyle.paragraph);
    });

    test('code inside a list item survives', () {
      final lines = renderMarkdown('- run `chatl --continue` now');
      expect(plain(lines), '• run chatl --continue now');
    });

    test('renderer is deterministic for the same input', () {
      const input = '# h\n\n- a\n\n```\ncode\n```\n\n| x |\n|---|\n| 1 |';
      expect(plain(renderMarkdown(input)), plain(renderMarkdown(input)));
    });
  });
}
