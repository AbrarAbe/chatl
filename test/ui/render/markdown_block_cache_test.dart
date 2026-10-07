import 'package:chatl/src/ui/render/markdown_block_cache.dart';
import 'package:chatl/src/ui/render/markdown_lines.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownBlockCache (ADR 0003 incrementality)', () {
    test('grows completed blocks once each', () {
      final cache = MarkdownBlockCache();
      var completedRenders = 0;
      var openRenders = 0;

      void render(String text) => cache.update(
        text,
        onRender: ({required completed}) => completed ? completedRenders++ : openRenders++,
      );

      render('first block');
      expect(completedRenders, 0);
      expect(openRenders, 1);
      expect(cache.completedLines, isEmpty);

      render('first block\n\nsecond');
      expect(completedRenders, 1);
      expect(cache.completedLines, hasLength(1));

      // more text streaming into the open block: frozen block untouched
      render('first block\n\nsecond grows');
      render('first block\n\nsecond grows more');
      expect(completedRenders, 1);
      expect(cache.completedLines, hasLength(1));

      // completing the second block renders it exactly once more
      render('first block\n\nsecond grows more\n\nthird');
      expect(completedRenders, 2);
      expect(cache.completedLines, hasLength(2));
    });

    test('allLines joins frozen and open blocks in order', () {
      final cache = MarkdownBlockCache();
      cache.update('# head\n\nstreaming');

      expect(cache.allLines.first.text, 'head');
      expect(cache.allLines.last.text, 'streaming');
    });

    test('an empty open block yields no open lines', () {
      final cache = MarkdownBlockCache();
      cache.update('done\n\n');

      expect(cache.completedLines, hasLength(1));
      expect(cache.openLines, isEmpty);
    });

    test('code fences never split into frozen blocks mid-fence', () {
      final cache = MarkdownBlockCache();
      cache.update('```\nline one\n\nline two');

      expect(cache.completedLines, isEmpty);
      expect(cache.openLines.map((l) => l.style).toSet(), {LineStyle.codeBlock});
    });

    test('rendering the same text twice renders the open block again only', () {
      final cache = MarkdownBlockCache();
      var completedRenders = 0;
      cache.update(
        'one\n\ntwo',
        onRender: ({required completed}) => completed ? completedRenders++ : null,
      );

      cache.update(
        'one\n\ntwo',
        onRender: ({required completed}) => completed ? completedRenders++ : null,
      );

      expect(completedRenders, 1);
    });
  });
}
