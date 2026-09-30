import 'package:nocterm/nocterm.dart';

import '../../session/session_controller.dart';
import '../chat_scroll_controller.dart';

/// Scrollable list of conversation turns. Rendering is plain text; markdown
/// rendering arrives in Task 13 (ADR 0003).
class MessageList extends StatelessComponent {
  const MessageList({super.key, required this.transcript, required this.scrollController});

  final List<Turn> transcript;
  final ChatScrollController scrollController;

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
                  child: Text(
                    turn.content,
                    key: ValueKey(index),
                    style: TextStyle(color: turn.error ? Colors.red : Colors.white),
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
