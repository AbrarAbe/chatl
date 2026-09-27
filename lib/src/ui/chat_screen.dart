import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../session/session_controller.dart';
import 'chat_scroll_controller.dart';
import 'coalescer.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_list.dart';

/// The main chat screen: scrollback list + input bar + status line.
///
/// Transcript updates are coalesced to ~30 fps (spec §Risk Module; never a
/// per-token rebuild).
class ChatScreen extends StatefulComponent {
  const ChatScreen({super.key, required this.controller, this.onScrollControllerReady});

  final SessionController controller;

  /// Test hook: exposes the live scroll controller (see spike/anchor_test).
  final void Function(ChatScrollController)? onScrollControllerReady;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatScrollController _scroll = ChatScrollController();
  final FrameCoalescer _coalescer = FrameCoalescer();
  StreamSubscription<void>? _updates;

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
    super.dispose();
  }

  void _submit(String text) {
    if (component.controller.streaming) return;
    // Errors are surfaced as visible transcript turns (spec §Interaction
    // Model): the stream never throws.
    component.controller.send(text);
  }

  bool _onKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyC && event.isControlPressed) {
      TerminalBinding.instance.requestShutdown();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final c = component.controller;
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Expanded(
            child: MessageList(transcript: c.transcript, scrollController: _scroll),
          ),
          InputBar(promptPrefix: _promptPrefix, enabled: !c.streaming, onSubmitted: _submit),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${c.currentModel} · ${c.currentPersona}'
              '${c.streaming ? ' · …' : ''}'
              '${_scroll.isAutoScrollEnabled ? '' : ' · paused (↓ bottom to resume)'}',
              style: const TextStyle(color: Colors.gray),
            ),
          ),
        ],
      ),
    );
  }

  String get _promptPrefix => component.controller.promptPrefix;
}
