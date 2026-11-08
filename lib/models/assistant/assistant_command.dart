import '../reminder.dart';
import '../reminder_calculator.dart';

/// Moment exprimé par l'utilisateur : « demain », « vendredi à 18h »,
/// « dans 2 heures », « le 20/11 »...
class AssistantWhen {
  const AssistantWhen(this.day, {this.hour, this.minute, this.exact});

  /// Jour concerné (heure ignorée).
  final DateTime day;

  /// Heure donnée explicitement (« à 9h », « ce soir »), sinon null.
  final int? hour;
  final int? minute;

  /// Instant précis (« dans 2 heures »).
  final DateTime? exact;

  bool get hasTime => exact != null || hour != null;

  /// Date complète ; l'heure par défaut est utilisée si aucune n'est donnée.
  DateTime resolve({int defaultHour = 9, int defaultMinute = 0}) {
    if (exact != null) return exact!;
    return DateTime(day.year, day.month, day.day, hour ?? defaultHour,
        hour != null ? (minute ?? 0) : defaultMinute);
  }
}

/// Critères permettant de retrouver un rappel cité dans une phrase
/// (« le vermifuge de Rex », « le rendez-vous »).
class ReminderQuery {
  const ReminderQuery({this.words = const [], this.petId, this.type});

  /// Mots significatifs, normalisés (minuscules, sans accents).
  final List<String> words;
  final int? petId;
  final ReminderType? type;

  bool get isEmpty => words.isEmpty && petId == null && type == null;

  /// Rappels correspondants, les plus pertinents d'abord.
  ///
  /// Sans critère, propose les rappels en retard ou du jour.
  List<Reminder> match(Iterable<Reminder> reminders, DateTime now) {
    final pool = reminders
        .where((r) => petId == null || r.petId == petId)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (words.isEmpty && type == null) {
      if (petId != null) return pool;
      return pool
          .where((r) =>
              r.isOverdue(now) ||
              ReminderCalculator.daysUntil(r.dueDate, now) == 0)
          .toList();
    }
    final scored = <(Reminder, int)>[];
    for (final r in pool) {
      final score = _score(r);
      if (score > 0) scored.add((r, score));
    }
    if (scored.isEmpty) return const [];
    final best = scored.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    return [
      for (final (r, s) in scored)
        if (s == best) r,
    ];
  }

  int _score(Reminder r) {
    final titleWords = normalizeFr(r.title)
        .split(RegExp(r"[^a-z0-9]+"))
        .where((w) => w.length >= 3)
        .toList();
    var score = 0;
    for (final w in words) {
      if (titleWords.any((t) => t.startsWith(w) || w.startsWith(t))) {
        score += 2;
      }
    }
    if (type != null && r.type == type) score += 2;
    return score;
  }
}

/// Période demandée par une question (« qu'est-ce qui est en retard ? »).
enum ListScope { overdue, day, week, month, next, upcoming, done }

/// Intention reconnue dans un message de l'utilisateur.
sealed class AssistantCommand {
  const AssistantCommand();
}

class HelpCommand extends AssistantCommand {
  const HelpCommand();
}

class GreetingCommand extends AssistantCommand {
  const GreetingCommand();
}

class ThanksCommand extends AssistantCommand {
  const ThanksCommand();
}

class SummaryCommand extends AssistantCommand {
  const SummaryCommand();
}

/// « annuler » juste après une action.
class UndoCommand extends AssistantCommand {
  const UndoCommand();
}

class UnknownCommand extends AssistantCommand {
  const UnknownCommand();
}

/// Sujet traité par un autre module (dépenses, poids, repas, activité).
enum OtherTopic { healthSpending, foodSpending, spending, weight, petInfo, food, activity }

/// Question hors du périmètre des rappels : l'assistant oriente vers le
/// bon onglet au lieu de répondre à côté.
class OutOfScopeCommand extends AssistantCommand {
  const OutOfScopeCommand(this.topic);

  final OtherTopic topic;
}

class ListCommand extends AssistantCommand {
  const ListCommand(this.scope, {this.day, this.petId, this.type});

  final ListScope scope;

  /// Jour demandé quand [scope] vaut [ListScope.day].
  final DateTime? day;
  final int? petId;
  final ReminderType? type;
}

class CreateCommand extends AssistantCommand {
  const CreateCommand({
    required this.title,
    required this.type,
    this.petId,
    this.when,
    this.repeat,
  });

  final String title;
  final ReminderType type;
  final int? petId;

  /// Null : la date doit encore être demandée.
  final AssistantWhen? when;

  /// Null : répétition par défaut du type (annuelle pour un vaccin).
  final ReminderRepeat? repeat;
}

class DoneCommand extends AssistantCommand {
  const DoneCommand(this.query);

  final ReminderQuery query;
}

class PostponeCommand extends AssistantCommand {
  const PostponeCommand(this.query, {this.when, this.delta});

  final ReminderQuery query;

  /// Nouvelle date (« à vendredi »).
  final AssistantWhen? when;

  /// Décalage (« de 3 jours »). Sans [when] ni [delta], la date est demandée.
  final Duration? delta;
}

class DeleteCommand extends AssistantCommand {
  const DeleteCommand(this.query);

  final ReminderQuery query;
}

/// Minuscules, sans accents, apostrophes droites.
///
/// Chaque caractère donne exactement un caractère : les positions restent
/// alignées avec le texte d'origine (utile pour extraire un titre).
String normalizeFr(String input) {
  final out = StringBuffer();
  for (final ch in input.split('')) {
    final lower = ch.toLowerCase();
    final c = lower.length == 1 ? lower : ch;
    out.write(_accents[c] ?? c);
  }
  return out.toString();
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'æ': 'a', //
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'œ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y',
  '’': "'", '‘': "'", '`': "'",
};
