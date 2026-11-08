import '../models/assistant/conversation_model.dart';

/// Controller d'un assistant conversationnel : hors ligne (règles en Dart)
/// ou Gemini. L'écran de l'assistant fonctionne avec l'un ou l'autre.
abstract interface class AssistantController {
  ConversationModel get model;

  /// Titre affiché dans la barre de l'écran.
  String get title;

  /// Sous-titre : mode de fonctionnement (« Gemini », « Hors ligne »...).
  String get modeLabel;

  Future<void> send(String text);

  /// Efface la conversation.
  void reset();

  void dispose();
}
