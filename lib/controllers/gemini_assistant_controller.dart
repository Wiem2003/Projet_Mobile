import 'package:intl/intl.dart';

import '../models/assistant/assistant_parser.dart';
import '../models/assistant/chat_message.dart';
import '../models/assistant/conversation_model.dart';
import '../models/assistant/gemini_client.dart';
import '../models/reminder.dart';
import 'assistant_controller.dart';
import 'assistant_tools.dart';
import 'reminder_assistant_controller.dart';

/// Controller de l'assistant Smart Pet propulsé par Gemini.
///
/// Envoie la conversation au modèle avec les outils [AssistantTools],
/// exécute les appels d'outils demandés (lecture des cinq modules, actions
/// sur les rappels), puis ajoute la réponse au [ConversationModel].
/// Sans connexion ou si Gemini est indisponible, l'assistant hors ligne
/// ([offline]) répond à sa place.
class GeminiAssistantController implements AssistantController {
  GeminiAssistantController({
    required LlmClient llm,
    required this.tools,
    required this.offline,
    this.maxToolRounds = 6,
    this.answerBudget = const Duration(seconds: 45),
  }) : _client = llm {
    model.restart(_welcome());
  }

  final LlmClient _client;
  final AssistantTools tools;
  final ReminderAssistantController offline;
  final int maxToolRounds;

  /// Taille maximale de l'historique envoyé (tours de parole).
  static const maxHistory = 40;

  /// Au-delà, plus de nouvel appel à Gemini pour cette question : l'assistant
  /// hors ligne répond.
  final Duration answerBudget;

  @override
  final model = ConversationModel();

  /// Contenus bruts échangés avec Gemini (renvoyés tels quels).
  final _history = <Map<String, Object?>>[];
  bool _offlineMode = false;
  bool _disposed = false;

  @override
  String get title => 'Assistant Smart Pet';

  @override
  String get modeLabel => _offlineMode
      ? 'Gemini indisponible · mode hors ligne'
      : 'Gemini · santé, repas, activités, rappels';

  DateTime get _now => tools.now;

  List<String> get _suggestions {
    final pet = tools.pets.all.firstOrNull?.name ?? 'mon chien';
    return [
      'Fais le point sur mes animaux',
      'Combien ai-je dépensé chez le véto cette année ?',
      'Comment évolue le poids de $pet ?',
      'Rappelle-moi le vermifuge de $pet samedi à 9h',
    ];
  }

  // --------------------------------------------------------------- Actions

  @override
  Future<void> send(String text) async {
    final input = text.trim();
    if (input.isEmpty || model.typing) return;
    model
      ..add(ChatMessage(author: ChatAuthor.user, text: input, at: _now))
      ..setTyping(true);
    tools.userConfirmed = AssistantParser.isYes(input);

    ChatMessage reply;
    try {
      reply = await _ask(input);
      _offlineMode = false;
    } on LlmException catch (e) {
      _offlineMode = true;
      final fallback = await offline.reply(input);
      reply = ChatMessage(
        author: ChatAuthor.assistant,
        text: '📴 ${e.message} Je réponds en mode hors ligne :\n\n'
            '${fallback.text}',
        at: _now,
        reminders: fallback.reminders,
        suggestions: fallback.suggestions,
      );
    }
    if (_disposed) return;
    model
      ..setTyping(false)
      ..add(reply);
  }

  Future<ChatMessage> _ask(String input) async {
    final start = _history.length;
    _history.add(_userText(input));
    final cards = <int?, Reminder>{};
    final watch = Stopwatch()..start();
    try {
      for (var round = 0; round < maxToolRounds; round++) {
        // Gemini surchargé : on ne fait pas attendre l'utilisateur.
        if (round > 0 && watch.elapsed > answerBudget) {
          throw const LlmException(LlmFailure.unavailable, 'réponse trop lente');
        }
        final turn = await _client.generate(
          system: _system(),
          contents: _history,
          tools: AssistantTools.declarations,
        );
        _history.add(turn.content);
        if (turn.calls.isEmpty) {
          _trimHistory();
          return _bot(
            turn.text.isEmpty ? 'Je n\'ai pas de réponse à cette question.' : _clean(turn.text),
            reminders: cards.values.take(4).toList(),
            suggestions: tools.pendingDeleteId != null
                ? const ['Oui, supprimer', 'Non']
                : const [],
          );
        }
        final responses = <Map<String, Object?>>[];
        for (final call in turn.calls) {
          final result = await tools.run(call.name, call.args);
          for (final r in result.cards) {
            cards[r.id] = r;
          }
          responses.add({
            'functionResponse': {
              'name': call.name,
              'id': ?call.id,
              'response': result.response,
            },
          });
        }
        _history.add({'role': 'user', 'parts': responses});
      }
      return _bot('Je n\'ai pas réussi à terminer cette demande. '
          'Pouvez-vous la reformuler plus simplement ?');
    } on LlmException {
      // Historique remis dans l'état d'avant la question.
      _history.removeRange(start, _history.length);
      rethrow;
    }
  }

  static Map<String, Object?> _userText(String text) => {
        'role': 'user',
        'parts': [
          {'text': text},
        ],
      };

  /// Garde les derniers échanges, en commençant par une question de
  /// l'utilisateur (jamais par une réponse d'outil isolée).
  void _trimHistory() {
    if (_history.length <= maxHistory) return;
    var cut = _history.length - maxHistory;
    while (cut < _history.length && !_isUserText(_history[cut])) {
      cut++;
    }
    _history.removeRange(0, cut);
  }

  static bool _isUserText(Map<String, Object?> content) =>
      content['role'] == 'user' &&
      ((content['parts'] as List?)?.first as Map?)?.containsKey('text') == true;

  /// Le texte des bulles n'est pas du Markdown : gras et puces simplifiés.
  static String _clean(String text) => text
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^\s*[*-]\s+', multiLine: true), '• ')
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .trim();

  String _system() {
    final when = DateFormat("EEEE d MMMM y, 'il est' HH:mm", 'fr_FR').format(_now);
    final pets = tools.pets.all.isEmpty
        ? 'aucun animal enregistré'
        : tools.pets.all.map((p) => '${p.name} (${p.species.label})').join(', ');
    return '''
Tu es l'assistant de l'application mobile Smart Pet Manager, qui gère la vie et les dépenses des animaux de compagnie.
Nous sommes le $when (heure locale). Animaux enregistrés : $pets.

Règles :
- Réponds toujours en français, brièvement et clairement : quelques phrases, des puces « • » si besoin. Pas de tableau ni de titre.
- Pour toute information sur les animaux, leurs rappels, leur santé, leurs repas ou leurs activités, appelle les outils. N'invente jamais de chiffres ni de rappels. Montants en DT, poids en kg.
- Pour créer un rappel, déduis la date et l'heure de la demande (09:00 si l'heure n'est pas donnée). S'il manque la date, demande-la. Ne crée jamais de rappel dans le passé.
- Pour terminer, reporter ou supprimer un rappel, trouve d'abord son id avec get_reminders. Si plusieurs rappels correspondent, demande lequel.
- Suppression : appelle delete_reminder sans confirmed ; l'application demande alors confirmation. Appelle-le avec confirmed=true seulement si l'utilisateur répond oui.
- Après une action, confirme en une phrase ce qui a été fait (titre, date, animal).
- Tu ne remplaces pas un vétérinaire : pour un symptôme, une maladie ou une urgence, conseille de consulter un vétérinaire. Tu peux donner des conseils généraux d'entretien.
- Si la question ne concerne pas les animaux, explique poliment que tu es spécialisé dans Smart Pet.
''';
  }

  ChatMessage _welcome() => ChatMessage(
        author: ChatAuthor.assistant,
        text: 'Bonjour 👋 Je suis l\'assistant Smart Pet, propulsé par Gemini.\n'
            'Je connais vos animaux, leur santé, leurs repas, leurs activités '
            'et leurs rappels, et je peux créer, reporter ou terminer des '
            'rappels.\n'
            'Vos questions et les données utiles à la réponse sont envoyées '
            'à Google Gemini.',
        at: _now,
        suggestions: _suggestions,
      );

  ChatMessage _bot(String text,
          {List<Reminder> reminders = const [],
          List<String> suggestions = const []}) =>
      ChatMessage(
        author: ChatAuthor.assistant,
        text: text,
        at: _now,
        reminders: reminders,
        suggestions: suggestions,
      );

  @override
  void reset() {
    _history.clear();
    tools.pendingDeleteId = null;
    offline.reset();
    model.restart(_welcome());
  }

  @override
  void dispose() {
    _disposed = true;
    offline.dispose();
    model.dispose();
  }
}
