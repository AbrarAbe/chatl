import 'package:nocterm/nocterm.dart';

import '../../session/session_controller.dart';
import '../chat_scroll_controller.dart';
import '../render/streaming_markdown_view.dart';
import '../theme.dart';

/// Scrollable list of conversation turns. Assistant turns render as markdown
/// when `ui.markdown` is enabled (ADR 0003); user turns and notices stay
/// verbatim. Colours come from the `ui.theme` palette.
class MessageList extends StatelessComponent {
  const MessageList({
    super.key,
    required this.transcript,
    required this.scrollController,
    this.markdown = true,
    this.theme = ChatlTheme.dark,
  });

  final List<Turn> transcript;
  final ChatScrollController scrollController;
  final bool markdown;
  final ChatlTheme theme;

  @override
  Component build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: scrollController,
        keyboardScrollable: true,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        itemCount: transcript.length,
        itemBuilder: (context, index) {
          final turn = transcript[index];
          final isUser = turn.role == 'user';
          final isNotice = turn.role == 'notice';
          final isAssistant = !isUser && !isNotice;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUser
                      ? '❯ '
                      : (isNotice ? 'ℹ ' : (turn.error ? '✗ ' : '◆ ')),
                  style: TextStyle(
                    color: theme.accentFor(
                      isUser: isUser,
                      isNotice: isNotice,
                      isError: turn.error,
                    ),
                  ),
                ),
                Expanded(
                  child: isAssistant && markdown && !turn.error
                      ? StreamingMarkdownView(
                          key: ValueKey('md-$index'),
                          text: turn.content,
                          theme: theme,
                        )
                      : Text(
                          turn.content,
                          key: ValueKey(index),
                          style: theme.styleForRole(
                            isUser: isUser,
                            isNotice: isNotice,
                            isError: turn.error,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
