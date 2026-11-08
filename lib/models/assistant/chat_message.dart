import 'package:intl/intl.dart';

import '../reminder.dart';
import '../reminder_calculator.dart';

enum ChatAuthor { user, assistant }

/// Un message de la conversation avec l'assistant Rappels.
class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    required this.at,
    this.reminders = const [],
    this.suggestions = const [],
    this.isError = false,
  });

  final ChatAuthor author;
  final String text;
  final DateTime at;

  /// Rappels affichés sous le message (cartes cliquables).
  final List<Reminder> reminders;

  /// Réponses rapides proposées (puces).
  final List<String> suggestions;
  final bool isError;

  bool get fromUser => author == ChatAuthor.user;
}

/// Formulations françaises utilisées dans les réponses de l'assistant.
abstract final class AssistantFormat {
  static final _day = DateFormat('EEEE d MMMM', 'fr_FR');
  static final _dayYear = DateFormat('EEEE d MMMM y', 'fr_FR');
  static final _short = DateFormat('d MMM', 'fr_FR');
  static final _time = DateFormat('HH:mm', 'fr_FR');

  /// « demain à 08:00 », « lundi 10 novembre à 09:00 ».
  static String when(DateTime d, DateTime now) =>
      '${day(d, now)} à ${_time.format(d)}';

  /// « aujourd'hui », « demain », « hier », « lundi 10 novembre ».
  static String day(DateTime d, DateTime now) {
    switch (ReminderCalculator.daysUntil(d, now)) {
      case 0:
        return 'aujourd\'hui';
      case 1:
        return 'demain';
      case -1:
        return 'hier';
    }
    return (d.year == now.year ? _day : _dayYear).format(d);
  }

  static String short(DateTime d) => _short.format(d);

  /// « 1 rappel », « 3 rappels ».
  static String count(int n, String singular, [String? plural]) =>
      '$n ${n > 1 ? (plural ?? '${singular}s') : singular}';
}
