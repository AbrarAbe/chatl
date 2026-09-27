import 'package:nocterm/nocterm.dart';

/// Input line with the configured prompt prefix.
class InputBar extends StatefulComponent {
  const InputBar({
    super.key,
    required this.promptPrefix,
    required this.onSubmitted,
    this.enabled = true,
  });

  final String promptPrefix;
  final ValueChanged<String> onSubmitted;
  final bool enabled;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !component.enabled) return;
    _controller.clear();
    component.onSubmitted(trimmed);
  }

  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      ),
      child: Row(
        children: [
          Text('${component.promptPrefix} ', style: const TextStyle(color: Colors.green)),
          Expanded(
            child: TextField(
              controller: _controller,
              focused: true,
              placeholder: 'type a message…',
              onSubmitted: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
