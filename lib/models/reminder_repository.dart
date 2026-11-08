import 'reminder.dart';

/// Résultat de « Marquer fait » : le rappel terminé et, s'il est répété,
/// l'occurrence suivante créée automatiquement.
class CompletionResult {
  const CompletionResult({required this.done, this.next});

  final Reminder done;
  final Reminder? next;
}

enum SyncOutcome { created, updated, unchanged, removed }

/// Accès aux rappels et règles métier (validation, anti-doublon,
/// répétition, report). Les erreurs sont des `ReminderException`.
abstract interface class ReminderRepository {
  Future<List<Reminder>> getAll({int? petId});
  Future<Reminder> getById(int id);
  Future<Reminder> create(Reminder reminder);
  Future<Reminder> update(Reminder reminder);
  Future<void> delete(int id);

  Future<CompletionResult> markDone(int id);

  /// Rouvre un rappel fait ; [removeNextId] supprime l'occurrence suivante
  /// créée par [markDone] (bouton « Annuler »).
  Future<Reminder> reopen(int id, {int? removeNextId});
  Future<Reminder> postpone(int id, DateTime dueDate);

  /// Crée / met à jour / supprime (si [dueDate] est null) le rappel lié à un
  /// enregistrement d'un autre module, sans jamais créer de doublon.
  Future<(SyncOutcome, Reminder?)> syncFromSource({
    required ReminderSource source,
    required int sourceId,
    required DateTime? dueDate,
    int? petId,
    ReminderType type = ReminderType.other,
    String? title,
    List<AlertOffset> alertOffsets = const [
      AlertOffset.tenDays,
      AlertOffset.oneDay,
      AlertOffset.atTime,
    ],
    ReminderRepeat repeat = ReminderRepeat.none,
  });

  /// À appeler quand un HealthRecord / FeedingRecord est supprimé.
  Future<List<int>> deleteBySource(ReminderSource source, int sourceId);

  /// À appeler par le module Animaux quand un animal est supprimé.
  Future<List<int>> deleteByPet(int petId);
}
