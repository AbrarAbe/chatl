import 'package:chatl/src/ui/render/markdown_lines.dart';
import 'package:chatl/src/ui/theme.dart';
import 'package:nocterm/nocterm.dart' show FontWeight;
import 'package:test/test.dart';

void main() {
  group('ChatlTheme (ui.theme, Task 14)', () {
    test('resolves dark and light, case-insensitively', () {
      expect(ChatlTheme.forName('dark').name, 'dark');
      expect(ChatlTheme.forName('light').name, 'light');
      expect(ChatlTheme.forName('LIGHT').name, 'light');
    });

    test('an unknown theme name falls back to dark, never unreadable', () {
      expect(ChatlTheme.forName('solarized-mango').name, 'dark');
      expect(ChatlTheme.forName('').name, 'dark');
    });

    test('the two palettes genuinely differ', () {
      expect(ChatlTheme.dark.paragraph, isNot(ChatlTheme.light.paragraph));
      expect(ChatlTheme.dark.code, isNot(ChatlTheme.light.code));
      expect(
        ChatlTheme.dark.assistantAccent,
        isNot(ChatlTheme.light.assistantAccent),
      );
      expect(ChatlTheme.dark.status, isNot(ChatlTheme.light.status));
    });

    test('markdown styles follow the palette and keep heading weight', () {
      final darkH1 = ChatlTheme.dark.styleFor(LineStyle.h1);
      final lightH1 = ChatlTheme.light.styleFor(LineStyle.h1);

      expect(darkH1.fontWeight, FontWeight.bold);
      expect(lightH1.fontWeight, FontWeight.bold);
      expect(darkH1.color, isNot(lightH1.color));

      expect(
        ChatlTheme.dark.styleFor(LineStyle.codeBlock).color,
        ChatlTheme.dark.code,
      );
      expect(
        ChatlTheme.light.styleFor(LineStyle.codeBlock).color,
        ChatlTheme.light.code,
      );
    });

    test('role accents distinguish user, assistant, notice and error', () {
      final dark = ChatlTheme.dark;
      final accents = {
        dark.accentFor(isUser: true, isNotice: false, isError: false),
        dark.accentFor(isUser: false, isNotice: false, isError: false),
        dark.accentFor(isUser: false, isNotice: true, isError: false),
        dark.accentFor(isUser: false, isNotice: false, isError: true),
      };
      expect(accents, hasLength(4));
    });
  });
}
