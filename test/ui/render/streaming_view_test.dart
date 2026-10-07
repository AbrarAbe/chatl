import 'package:chatl/src/ui/render/streaming_markdown_view.dart';
import 'package:nocterm/nocterm.dart' hide isNotEmpty;
import 'package:nocterm/nocterm_test.dart' show testNocterm;
import 'package:test/test.dart';

void main() {
  group('StreamingMarkdownView (ADR 0003)', () {
    test('markdown off renders the raw text verbatim', () async {
      await testNocterm('plain', (tester) async {
        await tester.pumpComponent(
          const StreamingMarkdownView(text: '**bold** stays', markdown: false),
        );
        await tester.pump();

        expect(tester.terminalState.containsText('**bold** stays'), isTrue);
      });
    });

    test('markdown on strips emphasis markers', () async {
      await testNocterm('md', (tester) async {
        await tester.pumpComponent(const StreamingMarkdownView(text: '**bold** now'));
        await tester.pump();

        expect(tester.terminalState.containsText('bold now'), isTrue);
        expect(tester.terminalState.containsText('**bold**'), isFalse);
      });
    });

    test('a streaming code fence renders code text without fence markers', () async {
      await testNocterm('fence', (tester) async {
        await tester.pumpComponent(
          const StreamingMarkdownView(text: 'before\n\n```dart\nfinal x = 1;'),
        );
        await tester.pump();

        expect(tester.terminalState.containsText('before'), isTrue);
        expect(tester.terminalState.containsText('final x = 1;'), isTrue);
        expect(tester.terminalState.containsText('```dart'), isFalse);
      });
    });

    test('a half-streamed table does not corrupt the display', () async {
      await testNocterm('table', (tester) async {
        await tester.pumpComponent(
          const StreamingMarkdownView(text: '| a | b |\n|---|---|\n| 1 |'),
        );
        await tester.pump();

        expect(tester.terminalState.getText(), isNotEmpty);
      });
    });
  });
}
