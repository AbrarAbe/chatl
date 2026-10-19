import 'package:nocterm/nocterm.dart';

import '../config/config.dart';
import '../providers/openai_compat.dart';
import '../providers/provider.dart';
import '../session/session_controller.dart';
import 'chat_screen.dart';

/// Root application shell: an already-constructed [SessionController]
/// (in-memory for tests, persisted for the real CLI) rendered as the chat
/// screen.
class ChatlApp extends StatelessComponent {
  const ChatlApp({super.key, required this.controller, this.newSession});

  final SessionController controller;

  /// `/new` factory (CLI wiring); null in tests.
  final Future<SessionController> Function()? newSession;

  @override
  Component build(BuildContext context) =>
      ChatScreen(controller: controller, newSession: newSession);
}

/// Real provider for a model profile; the one place HTTP meets the seam
/// (spec §Seams).
Provider providerForProfile(ModelProfile profile) => OpenAiCompatProvider(
  baseUrl: profile.baseUrl ?? 'https://api.openai.com/v1',
  apiKey: profile.apiKey,
);
