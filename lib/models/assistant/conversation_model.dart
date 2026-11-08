import 'package:flutter/foundation.dart';

import 'chat_message.dart';

/// Model de la conversation avec l'assistant : messages et indicateur
/// « en train d'écrire ». Observé par l'écran ; modifié par le
/// `ReminderAssistantController`.
class ConversationModel extends ChangeNotifier {
  final _messages = <ChatMessage>[];
  bool _typing = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get typing => _typing;

  /// Réponses rapides proposées par le dernier message de l'assistant.
  List<String> get suggestions => _typing || _messages.isEmpty ||
          _messages.last.fromUser
      ? const []
      : _messages.last.suggestions;

  void add(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void setTyping(bool value) {
    _typing = value;
    notifyListeners();
  }

  /// Recommence la conversation avec un premier message.
  void restart(ChatMessage first) {
    _messages
      ..clear()
      ..add(first);
    _typing = false;
    notifyListeners();
  }
}
