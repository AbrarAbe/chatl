import 'package:nocterm/nocterm.dart';

import '../../session/session_controller.dart';
import '../chat_scroll_controller.dart';
import '../render/streaming_markdown_view.dart';

/// Scrollable list of conversation turns. Assistant turns render as markdown
/// when `ui.markdown` is enabled (ADR 0003); user turns and notices stay
/// verbatim.
class MessageList extends StatelessComponent {
  const MessageList({
    super.key,
    required this.transcript,
    required this.scrollController,
    this.markdown = true,
  });

  final List<Turn> transcript;
  final ChatScrollController scrollController;
  final bool markdown;

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
                  isUser ? '❯ ' : (isNotice ? 'ℹ ' : (turn.error ? '✗ ' : '◆ ')),
                  style: TextStyle(
                    color: turn.error
                        ? Colors.red
                        : isNotice
                        ? Colors.gray
                        : isUser
                        ? Colors.green
                        : Colors.cyan,
                  ),
                ),
                Expanded(
                  child: isAssistant && markdown && !turn.error
                      ? StreamingMarkdownView(key: ValueKey('md-$index'), text: turn.content)
                      : Text(
                          turn.content,
                          key: ValueKey(index),
                          style: TextStyle(
                            color: turn.error
                                ? Colors.red
                                : isNotice
                                ? Colors.gray
                                : Colors.white,
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
