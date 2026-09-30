import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../session/session_controller.dart';
import 'chat_scroll_controller.dart';
import 'coalescer.dart';
import 'widgets/history_overlay.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_list.dart';

/// The main chat screen: scrollback list + input bar + status line.
///
/// Transcript updates are coalesced to ~30 fps (spec §Risk Module; never a
/// per-token rebuild). Ctrl+E edits the most recent user turn (fork-on-edit);
/// `/history` opens the flat current-branch list.
class ChatScreen extends StatefulComponent {
  const ChatScreen({super.key, required this.controller, this.onScrollControllerReady});

  final SessionController controller;

  /// Test hook: exposes the live scroll controller.
  final void Function(ChatScrollController)? onScrollControllerReady;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatScrollController _scroll = ChatScrollController();
  final FrameCoalescer _coalescer = FrameCoalescer();
  final TextEditingController _input = TextEditingController();
  StreamSubscription<void>? _updates;
  bool _historyOpen = false;

  @override
  void initState() {
    super.initState();
    component.onScrollControllerReady?.call(_scroll);
    _updates = component.controller.updates.listen((_) {
      _coalescer.schedule(() {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    _coalescer.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text == '/history') {
      setState(() => _historyOpen = true);
      return;
    }
    if (text == '/edit' || text.startsWith('/edit ')) {
      _editLastUserTurn(text.startsWith('/edit ') ? text.substring(6).trim() : '');
      return;
    }
    if (component.controller.streaming) return;

    // Errors surface as visible transcript turns; the stream never throws.
    component.controller.send(text);
  }

  /// `/edit <new text>`: forks the most recent user turn with the revised
  /// text and regenerates the reply (fork-on-edit, spec §MVP Scope).
  ///
  /// One-shot by design: nocterm dispatches key events children-first, so the
  /// focused TextField swallows chords (Ctrl+E) and prefill-into-the-field is
  /// racy across rebuilds — both verified while implementing (plan_v0.1.0
  /// Task 9 note).
  void _editLastUserTurn(String newText) {
    if (component.controller.streaming) return;
    if (newText.isEmpty) return; // bare `/edit` needs the revised text
    final index = component.controller.transcript.lastIndexWhere((t) => t.role == 'user');
    if (index < 0) return;
    final turn = component.controller.transcript[index];
    if (turn.id == null) return; // in-memory conversation: nothing to fork
    component.controller.editTurn(turn.id!, newText);
  }

  bool _onKey(KeyboardEvent event) {
    if (_historyOpen) return false; // overlay handles esc/scrolling
    if (event.logicalKey == LogicalKey.keyC && event.isControlPressed) {
      TerminalBinding.instance.requestShutdown();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final c = component.controller;

    if (_historyOpen) {
      return HistoryOverlay(
        entries: c.history(),
        onClose: () => setState(() => _historyOpen = false),
      );
    }

    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Expanded(
            child: MessageList(transcript: c.transcript, scrollController: _scroll),
          ),
          InputBar(
            promptPrefix: c.promptPrefix,
            controller: _input,
            enabled: !c.streaming,
            hint: c.streaming ? 'streaming…' : 'type a message…',
            onSubmitted: _submit,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${c.currentModel} · ${c.currentPersona}'
              '${c.streaming ? ' · …' : ''}'
              '${_scroll.isAutoScrollEnabled ? '' : ' · paused (↓ to resume)'}'
              ' · /edit <text> · /history',
              style: const TextStyle(color: Colors.gray),
            ),
          ),
        ],
      ),
    );
  }
}
