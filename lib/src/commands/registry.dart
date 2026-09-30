import '../config/config.dart';

/// Built-in `/` verbs the UI performs itself (spec §Interaction Model).
enum BuiltinAction { newSession, rename, copyLastReply, showContext, showHistory, editLastUserTurn }

/// What a `/` input resolved to.
sealed class CommandOutcome {
  const CommandOutcome();
}

/// Plain text — send it to the model.
class NotACommand extends CommandOutcome {
  const NotACommand();
}

/// A config-defined command: submit [prompt] against the conversation.
class SendPrompt extends CommandOutcome {
  const SendPrompt(this.prompt);

  final String prompt;
}

/// A built-in verb for the UI to perform; [payload] is the raw argument text.
class CommandAction extends CommandOutcome {
  const CommandAction(this.action, {this.payload});

  final BuiltinAction action;
  final String? payload;
}

/// A visible notice (spec §Interaction Model: failures are never silent).
class CommandMessage extends CommandOutcome {
  const CommandMessage(this.text);

  final String text;
}

/// Parses `/` verbs: built-ins + config-defined commands (spec §Interaction
/// Model; config entries never shadow built-ins).
class SlashRegistry {
  SlashRegistry({required Config config})
    : _configCommands = {for (final command in config.commands) command.name: command.prompt};

  final Map<String, String> _configCommands;

  static const _usage = {
    BuiltinAction.rename: 'usage: /rename <title>',
    BuiltinAction.editLastUserTurn: 'usage: /edit <new text>',
  };

  CommandOutcome resolve(String input) {
    if (!input.startsWith('/')) return const NotACommand();

    final space = input.indexOf(' ');
    final name = (space < 0 ? input : input.substring(0, space)).substring(1);
    final payload = space < 0 ? null : input.substring(space + 1).trim();

    if (name.isEmpty) {
      return const CommandMessage('that is not a command — see /context for this session\'s state');
    }

    switch (name) {
      case 'new':
        return const CommandAction(BuiltinAction.newSession);
      case 'history':
        return const CommandAction(BuiltinAction.showHistory);
      case 'context':
        return const CommandAction(BuiltinAction.showContext);
      case 'copy':
        return const CommandAction(BuiltinAction.copyLastReply);
      case 'rename':
        if (payload == null || payload.isEmpty) {
          return CommandMessage(_usage[BuiltinAction.rename]!);
        }
        return CommandAction(BuiltinAction.rename, payload: payload);
      case 'edit':
        if (payload == null || payload.isEmpty) {
          return CommandMessage(_usage[BuiltinAction.editLastUserTurn]!);
        }
        return CommandAction(BuiltinAction.editLastUserTurn, payload: payload);
    }

    final prompt = _configCommands[name];
    if (prompt != null) return SendPrompt(prompt);

    return CommandMessage('unknown command /$name');
  }
}
