import 'package:chatl/src/ui/render/block_splitter.dart';
import 'package:test/test.dart';

void main() {
  group('BlockSplitter (ADR 0003)', () {
    test('blank line ends a block', () {
      final split = BlockSplitter.split('one\n\ntwo\n\npartial');
      expect(split.completed, ['one', 'two']);
      expect(split.open, 'partial');
    });

    test('trailing blank line leaves an empty open block', () {
      final split = BlockSplitter.split('one\n\ntwo\n\n');
      expect(split.completed, ['one', 'two']);
      expect(split.open, '');
    });

    test('blank lines inside a fenced code block do not split', () {
      const text = '```dart\n\nvoid main() {}\n\n```\n\nafter';
      final split = BlockSplitter.split(text);
      expect(split.completed, hasLength(1));
      expect(split.completed.single, contains('void main()'));
      expect(split.completed.single, contains('```'));
      expect(split.open, 'after');
    });

    test('an unclosed fence stays in the open block', () {
      const text = 'intro\n\n```dart\nfinal x = 1;\n';
      final split = BlockSplitter.split(text);
      expect(split.completed, ['intro']);
      expect(split.open, startsWith('```dart'));
      expect(split.open, contains('final x = 1;'));
    });

    test('a half-streamed table stays in the open block', () {
      const text = '| a | b |\n|---|---|\n| 1 |';
      final split = BlockSplitter.split(text);
      expect(split.completed, isEmpty);
      expect(split.open, contains('| 1 |'));
    });

    test('tildes fences are recognised too', () {
      const text = '~~~\nblank\n\nlines\n~~~\n\nafter';
      final split = BlockSplitter.split(text);
      expect(split.completed, hasLength(1));
      expect(split.open, 'after');
    });

    test('empty input yields nothing', () {
      final split = BlockSplitter.split('');
      expect(split.completed, isEmpty);
      expect(split.open, '');
    });

    test('windows line endings behave like unix ones', () {
      final split = BlockSplitter.split('one\r\n\r\ntwo');
      expect(split.completed, ['one']);
      expect(split.open, 'two');
    });
  });
}
