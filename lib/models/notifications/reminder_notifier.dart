import '../reminder.dart';

/// Planificateur des notifications locales (étape 3 du cycle de vie).
///
/// Les notifications sont une projection de la table `reminders` : [syncAll]
/// est appelé après chaque chargement et reprogramme / annule ce qu'il faut,
/// y compris pour les rappels créés par un autre module (ex. Santé).
abstract interface class ReminderNotifier {
  Future<void> syncAll(List<Reminder> reminders,
      {Map<int, String> petNames = const {}});

  /// Demande l'autorisation d'afficher des notifications.
  Future<bool> requestPermissions();

  /// Affiche immédiatement une notification de démonstration.
  Future<void> showTest();
}

enum NotificationAction { open, done, postpone }

/// Interaction de l'utilisateur avec une notification (étape 5 du cycle).
class ReminderNotificationEvent {
  const ReminderNotificationEvent(this.reminderId, this.action);

  final int reminderId;
  final NotificationAction action;
}

class NoopReminderNotifier implements ReminderNotifier {
  const NoopReminderNotifier();

  @override
  Future<void> syncAll(List<Reminder> reminders,
      {Map<int, String> petNames = const {}}) async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> showTest() async {}
}

/// Identifiant de notification : un emplacement par délai d'alerte
/// (`id * 16 + index`), ce qui permet de tout retrouver sans table en plus.
int notificationIdFor(int reminderId, AlertOffset offset) =>
    reminderId * 16 + offset.index;
