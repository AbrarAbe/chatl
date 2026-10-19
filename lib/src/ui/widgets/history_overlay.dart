import 'package:nocterm/nocterm.dart';

import '../../session/session_controller.dart';
import '../chat_scroll_controller.dart';

/// Flat current-branch listing for `/history` (spec Decisions: flat, not a
/// tree).
class HistoryOverlay extends StatelessComponent {
  const HistoryOverlay({super.key, required this.entries, required this.onClose});

  final List<HistoryEntry> entries;
  final void Function() onClose;

  bool _onKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      onClose();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final scroll = ChatScrollController();
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(border: BoxBorder.all(color: Colors.cyan)),
        child: Column(
          children: [
            Text(
              'history (${entries.length} turns) — esc to close',
              style: const TextStyle(color: Colors.brightWhite, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                keyboardScrollable: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isUser = entry.role == 'user';
                  return Text(
                    '${index + 1}. ${isUser ? '❯' : '◆'} ${entry.preview}',
                    style: TextStyle(color: isUser ? Colors.green : Colors.white),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
