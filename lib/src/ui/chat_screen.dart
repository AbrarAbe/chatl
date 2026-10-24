import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../commands/registry.dart';
import '../session/session_controller.dart';
import 'chat_scroll_controller.dart';
import 'coalescer.dart';
import 'theme.dart';
import 'widgets/history_overlay.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_list.dart';

/// The main chat screen: scrollback list + input bar + status line.
///
/// All `/` input goes through [SlashRegistry] (spec §Interaction Model).
/// Transcript updates are coalesced to ~30 fps (spec §Risk Module).
class ChatScreen extends StatefulComponent {
  const ChatScreen({
    super.key,
    required this.controller,
    this.onScrollControllerReady,
    this.newSession,
    this.copyToClipboard,
  });

  final SessionController controller;

  /// Test hook: exposes the live scroll controller.
  final void Function(ChatScrollController)? onScrollControllerReady;

  /// `/new`: creates and returns a fresh persisted session controller.
  /// Absent in tests/in-memory runs, where `/new` only explains itself.
  final Future<SessionController> Function()? newSession;

  /// `/copy`: injectable for tests; defaults to nocterm's OSC-52 clipboard.
  final bool Function(String text)? copyToClipboard;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatScrollController _scroll = ChatScrollController();
  final FrameCoalescer _coalescer = FrameCoalescer();
  final TextEditingController _input = TextEditingController();

  late SessionController _controller;
  late SlashRegistry _registry;
  late ChatlTheme _theme;
  StreamSubscription<void>? _updates;
  bool _historyOpen = false;

  @override
  void initState() {
    super.initState();
    component.onScrollControllerReady?.call(_scroll);
    _controller = component.controller;
    _registry = SlashRegistry(config: _controller.config);
    _theme = ChatlTheme.forName(_controller.config.ui.theme);
    _updates = _controller.updates.listen((_) {
      _coalescer.schedule(() {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void didUpdateComponent(ChatScreen old) {
    super.didUpdateComponent(old);
    if (old.controller != component.controller) {
      _adopt(component.controller);
    }
  }

  void _adopt(SessionController controller) {
    _updates?.cancel();
    _controller = controller;
    _registry = SlashRegistry(config: controller.config);
    _theme = ChatlTheme.forName(controller.config.ui.theme);
    _updates = controller.updates.listen((_) {
      _coalescer.schedule(() {
        if (mounted) setState(() {});
      });
    });
    setState(() {});
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
    switch (_registry.resolve(text)) {
      case NotACommand():
        if (_controller.streaming) return;
        // Errors surface as visible transcript turns; the stream never throws.
        _controller.send(text);
      case SendPrompt(:final prompt):
        if (_controller.streaming) return;
        _controller.send(prompt);
      case CommandMessage(:final text):
        _controller.addNotice(text);
      case CommandAction(:final action, :final payload):
        _run(action, payload);
    }
  }

  void _run(BuiltinAction action, String? payload) {
    switch (action) {
      case BuiltinAction.showHistory:
        setState(() => _historyOpen = true);
      case BuiltinAction.showContext:
        _controller.addNotice(_controller.describeContext());
      case BuiltinAction.copyLastReply:
        _copyLastReply();
      case BuiltinAction.rename:
        _rename(payload!);
      case BuiltinAction.editLastUserTurn:
        _editLastUserTurn(payload!);
      case BuiltinAction.setModel:
        _switchProfile(payload, isModel: true);
      case BuiltinAction.setPersona:
        _switchProfile(payload, isModel: false);
      case BuiltinAction.newSession:
        _newSession();
    }
  }

  /// `/model [name]` and `/persona [name]`: list when bare, switch when named
  /// (validation live in the controller; unknown names fail visibly).
  void _switchProfile(String? name, {required bool isModel}) {
    if (name == null) {
      _controller.addNotice(
        isModel ? _controller.describeModels() : _controller.describePersonas(),
      );
      return;
    }
    try {
      if (isModel) {
        _controller.setModel(name);
        _controller.addNotice('/model: now using profile "$name"');
      } else {
        _controller.setPersona(name);
        _controller.addNotice('/persona: now using "$name"');
      }
    } on ArgumentError {
      final available = isModel
          ? _controller.config.models.keys.join(', ')
          : _controller.config.personas.keys.join(', ');
      _controller.addNotice(
        'unknown ${isModel ? 'model' : 'persona'} "$name" — available: $available',
      );
    }
  }

  void _copyLastReply() {
    final last = _controller.transcript.lastWhere(
      (t) => t.role == 'assistant' && t.content.isNotEmpty,
      orElse: () => Turn(role: 'assistant', content: ''),
    );
    if (last.content.isEmpty) {
      _controller.addNotice('/copy: no reply to copy yet');
      return;
    }
    final copy =
        component.copyToClipboard ?? (text) => ClipboardManager.copy(text);
    final ok = copy(last.content);
    _controller.addNotice(
      ok
          ? '/copy: ${last.content.length} chars copied'
          : '/copy: clipboard unavailable',
    );
  }

  void _rename(String title) {
    _controller
        .renameSession(title)
        .then(
          (_) => _controller.addNotice('/rename: session is now "$title"'),
          onError: (_) => _controller.addNotice(
            '/rename: this session is not persisted yet',
          ),
        );
  }

  /// `/edit <new text>`: forks the most recent user turn and regenerates the
  /// reply (fork-on-edit, spec §MVP Scope).
  void _editLastUserTurn(String newText) {
    if (_controller.streaming) return;
    final index = _controller.transcript.lastIndexWhere(
      (t) => t.role == 'user',
    );
    if (index < 0) return;
    final turn = _controller.transcript[index];
    if (turn.id == null) {
      _controller.addNotice('/edit: this conversation is not persisted');
      return;
    }
    _controller.editTurn(turn.id!, newText);
  }

  void _newSession() {
    final factory = component.newSession;
    if (factory == null) {
      _controller.addNotice(
        '/new: restart with `chatl` for a fresh session (in-memory run)',
      );
      return;
    }
    factory().then(
      _adopt,
      onError: (Object e) {
        _controller.addNotice('/new failed: $e');
      },
    );
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
    final c = _controller;

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
            child: MessageList(
              transcript: c.transcript,
              scrollController: _scroll,
              markdown: c.config.ui.markdown,
              theme: _theme,
            ),
          ),
          InputBar(
            promptPrefix: c.promptPrefix,
            controller: _input,
            theme: _theme,
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
              ' · /model /persona /history /context /new',
              style: TextStyle(color: _theme.status),
            ),
          ),
        ],
      ),
    );
  }
}
