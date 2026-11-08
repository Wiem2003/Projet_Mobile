enum ReminderErrorKind { validation, conflict, notFound, postponeLimit }

/// Erreur métier du module Rappels, affichable telle quelle à l'utilisateur.
class ReminderException implements Exception {
  const ReminderException(this.message,
      [this.kind = ReminderErrorKind.validation]);

  const ReminderException.conflict(
      [this.message = 'Un rappel identique existe déjà pour cette date.'])
      : kind = ReminderErrorKind.conflict;

  const ReminderException.notFound([this.message = 'Rappel introuvable.'])
      : kind = ReminderErrorKind.notFound;

  final String message;
  final ReminderErrorKind kind;

  bool get isConflict => kind == ReminderErrorKind.conflict;
  bool get isNotFound => kind == ReminderErrorKind.notFound;

  /// Limite de reports atteinte : proposer un rendez-vous.
  bool get isPostponeLimit => kind == ReminderErrorKind.postponeLimit;

  @override
  String toString() => message;
}
