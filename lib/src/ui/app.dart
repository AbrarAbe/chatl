import 'package:nocterm/nocterm.dart';

import '../config/config.dart';
import '../providers/openai_compat.dart';
import '../session/session_controller.dart';
import 'chat_screen.dart';

/// Root application shell: config → session controller → chat screen.
class ChatlApp extends StatelessComponent {
  const ChatlApp({super.key, required this.config});

  final Config config;

  @override
  Component build(BuildContext context) {
    return ChatScreen(
      controller: SessionController(
        config: config,
        providerFor: (profile) => OpenAiCompatProvider(
          baseUrl: profile.baseUrl ?? 'https://api.openai.com/v1',
          apiKey: profile.apiKey,
        ),
      ),
    );
  }
}
