import 'package:nocterm/nocterm.dart';

import 'render/markdown_lines.dart';

/// The `ui.theme` palettes (spec §Config Surface). Unknown theme names fall
/// back to dark — a terminal chat client should never render unreadable text
/// because of a typo in config.
///
/// Hierarchy in a terminal comes from colour and weight, not size; the light
/// palette therefore picks dark-on-light inks instead of inverting wholesale.
class ChatlTheme {
  const ChatlTheme({
    required this.name,
    required this.paragraph,
    required this.userAccent,
    required this.assistantAccent,
    required this.notice,
    required this.error,
    required this.prompt,
    required this.border,
    required this.status,
    required this.code,
    required this.quote,
    required this.table,
    required this.h1,
    required this.h2,
    required this.h3,
  });

  final String name;
  final Color paragraph;
  final Color userAccent;
  final Color assistantAccent;
  final Color notice;
  final Color error;
  final Color prompt;
  final Color border;
  final Color status;
  final Color code;
  final Color quote;
  final Color table;
  final Color h1;
  final Color h2;
  final Color h3;

  static const dark = ChatlTheme(
    name: 'dark',
    paragraph: Colors.white,
    userAccent: Colors.green,
    assistantAccent: Colors.cyan,
    notice: Colors.gray,
    error: Colors.red,
    prompt: Colors.green,
    border: Colors.cyan,
    status: Colors.gray,
    code: Colors.yellow,
    quote: Colors.gray,
    table: Colors.cyan,
    h1: Colors.brightWhite,
    h2: Colors.cyan,
    h3: Colors.green,
  );

  /// Light-terminal palette: dark inks on a presumed light background.
  static const light = ChatlTheme(
    name: 'light',
    paragraph: Colors.black,
    userAccent: Colors.blue,
    assistantAccent: Colors.magenta,
    notice: Colors.brightBlack,
    error: Colors.red,
    prompt: Colors.blue,
    border: Colors.brightBlack,
    status: Colors.brightBlack,
    code: Colors.magenta,
    quote: Colors.brightBlack,
    table: Colors.blue,
    h1: Colors.black,
    h2: Colors.blue,
    h3: Colors.magenta,
  );

  /// Resolves `ui.theme`; case-insensitive, unknown → [dark].
  static ChatlTheme forName(String name) => switch (name.toLowerCase()) {
    'light' => light,
    'dark' => dark,
    _ => dark,
  };

  /// Terminal look per markdown line style for this palette.
  TextStyle styleFor(LineStyle style) => switch (style) {
    LineStyle.h1 => TextStyle(color: h1, fontWeight: FontWeight.bold),
    LineStyle.h2 => TextStyle(color: h2, fontWeight: FontWeight.bold),
    LineStyle.h3 => TextStyle(color: h3, fontWeight: FontWeight.bold),
    LineStyle.h4 ||
    LineStyle.h5 ||
    LineStyle.h6 => TextStyle(color: h2, fontWeight: FontWeight.bold),
    LineStyle.paragraph => TextStyle(color: paragraph),
    LineStyle.bullet || LineStyle.ordered => TextStyle(color: paragraph),
    LineStyle.codeBlock => TextStyle(color: code),
    LineStyle.quote => TextStyle(color: quote),
    LineStyle.table => TextStyle(color: table),
    LineStyle.rule => TextStyle(color: quote),
  };

  /// Style for a plain (non-markdown) transcript line.
  TextStyle styleForRole({required bool isUser, required bool isNotice, required bool isError}) =>
      TextStyle(
        color: isError
            ? error
            : isNotice
            ? notice
            : isUser
            ? paragraph
            : paragraph,
      );

  /// Accent used by the `❯`/`◆`/`ℹ`/`✗` prefix for a turn.
  Color accentFor({required bool isUser, required bool isNotice, required bool isError}) => isError
      ? error
      : isNotice
      ? notice
      : isUser
      ? userAccent
      : assistantAccent;
}
