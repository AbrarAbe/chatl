import 'package:nocterm/nocterm.dart';

import '../theme.dart';

/// Input line with the configured prompt prefix.
///
/// After each submit the local `TextField` key is bumped: nocterm's TextField
/// keeps an internal buffer that clearing the controller alone does not reset.
class InputBar extends StatefulComponent {
  const InputBar({
    super.key,
    required this.promptPrefix,
    required this.controller,
    required this.onSubmitted,
    this.theme = ChatlTheme.dark,
    this.enabled = true,
    this.hint = 'type a message…',
  });

  final String promptPrefix;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final ChatlTheme theme;
  final bool enabled;
  final String hint;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  int _localReset = 0;

  void _submit(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !component.enabled) return;
    component.controller.text = '';
    setState(() => _localReset++);
    component.onSubmitted(trimmed);
  }

  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: BoxBorder(top: BorderSide(color: component.theme.border)),
      ),
      child: Row(
        children: [
          Text(
            '${component.promptPrefix} ',
            style: TextStyle(
              color: component.enabled
                  ? component.theme.prompt
                  : component.theme.status,
            ),
          ),
          Expanded(
            child: TextField(
              key: ValueKey('input-$_localReset'),
              controller: component.controller,
              focused: true,
              placeholder: component.hint,
              style: TextStyle(color: component.theme.paragraph),
              onSubmitted: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
