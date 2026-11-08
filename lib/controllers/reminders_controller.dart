import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import '../models/notifications/reminder_notifier.dart';
import '../models/health_record.dart';
import '../models/reminder.dart';
import '../models/reminder_planning.dart';
import '../models/reminder_exception.dart';
import '../models/reminder_repository.dart';
import '../models/reminders_model.dart';

/// Demande d'ouverture venant d'une notification (détail ou report).
typedef ReminderIntent = ({Reminder reminder, NotificationAction action});

/// Controller du module Rappels.
///
/// Reçoit les actions de la View (filtres, fait, report, suppression...),
/// applique les règles via le repository SQLite, reprogramme les
/// notifications puis met à jour le [RemindersModel] que la View observe.
/// Les erreurs métier remontent en [ReminderException] à la View.
class RemindersController {
  RemindersController({
    required this.model,
    required ReminderRepository repository,
    required ReminderNotifier notifier,
    required PetDirectory pets,
    Stream<ReminderNotificationEvent>? notificationEvents,
    Duration? refreshEvery = const Duration(minutes: 1),
    PlanningSettingsStore? planning,
    this.healthRecords,
  })  : _repo = repository,
        _notifications = notifier,
        _petDirectory = pets,
        _planning = planning ?? MemoryPlanningSettingsStore() {
    _eventsSub = notificationEvents?.listen(handleNotificationEvent);
    if (refreshEvery != null) {
      _ticker = Timer.periodic(refreshEvery, (_) => model.refresh());
    }
  }

  final RemindersModel model;
  final ReminderRepository _repo;
  final ReminderNotifier _notifications;
  final PetDirectory _petDirectory;
  final PlanningSettingsStore _planning;

  /// Dossiers de santé (module Santé), pour estimer le budget des soins.
  Future<List<HealthRecord>> Function()? healthRecords;
  StreamSubscription<ReminderNotificationEvent>? _eventsSub;
  Timer? _ticker;

  /// Écouté par l'écran Rappels et par la navigation principale.
  final intent = ValueNotifier<ReminderIntent?>(null);

  // --------------------------------------------------------------- Filtres

  void setTab(ReminderTab t) => model.setTab(t);
  void setTypeFilter(ReminderType? t) => model.setTypeFilter(t);
  void setPetFilter(int? id) => model.setPetFilter(id);
  void setDayFilter(DateTime? day) => model.setDayFilter(day);
  void setQuery(String q) => model.setQuery(q);
  void clearFilters() => model.clearFilters();

  // --------------------------------------------------------------- Actions

  /// Recharge les rappels depuis SQLite et reprogramme les notifications.
  Future<void> load() async {
    try {
      // Toujours relus : le module Animaux a pu les modifier.
      model.setPets(await _petDirectory.getPets());
      model.setPlanningData(
          await _planning.load(), await healthRecords?.call() ?? const []);
      final all = await _repo.getAll();
      model.setReminders(all);
      await _notifications.syncAll(all, petNames: {
        for (final p in model.pets) p.id: p.name,
      });
    } on Exception catch (e) {
      model.setError('Impossible de charger les rappels : $e');
    }
  }

  /// Exécute une action puis recharge le Model depuis la base.
  Future<T> _mutate<T>(Future<T> Function() action) async {
    final result = await action();
    await load();
    return result;
  }

  Future<Reminder> save(Reminder r) =>
      _mutate(() => r.id == null ? _repo.create(r) : _repo.update(r));

  Future<void> delete(Reminder r) => _mutate(() => _repo.delete(r.id!));

  Future<CompletionResult> markDone(Reminder r) =>
      _mutate(() => _repo.markDone(r.id!));

  Future<void> undoDone(CompletionResult result) => _mutate(() =>
      _repo.reopen(result.done.id!, removeNextId: result.next?.id));

  Future<Reminder> postpone(Reminder r, DateTime newDate) =>
      _mutate(() => _repo.postpone(r.id!, newDate));

  Future<void> reopen(Reminder r) => _mutate(() => _repo.reopen(r.id!));

  Future<void> handleNotificationEvent(ReminderNotificationEvent e) async {
    Reminder r;
    try {
      r = model.byId(e.reminderId) ?? await _repo.getById(e.reminderId);
    } on ReminderException {
      return; // Rappel supprimé entre-temps.
    }
    if (e.action == NotificationAction.done && !r.isDone) {
      await markDone(r);
    }
    intent.value = (reminder: r, action: e.action);
  }

  // ------------------------------------------- Échéances des autres modules

  /// Crée, met à jour ou supprime (si [dueDate] est null) le rappel lié à un
  /// enregistrement d'un autre module (ex. prochaine échéance d'un
  /// HealthRecord), puis reprogramme les notifications.
  Future<SyncOutcome> syncDeadline({
    required ReminderSource source,
    required int sourceId,
    required DateTime? dueDate,
    int? petId,
    ReminderType type = ReminderType.other,
    String? title,
    List<AlertOffset>? alertOffsets,
  }) async {
    final (outcome, _) = await _mutate(() => alertOffsets == null
        ? _repo.syncFromSource(
            source: source,
            sourceId: sourceId,
            dueDate: dueDate,
            petId: petId,
            type: type,
            title: title,
          )
        : _repo.syncFromSource(
            source: source,
            sourceId: sourceId,
            dueDate: dueDate,
            petId: petId,
            type: type,
            title: title,
            alertOffsets: alertOffsets,
          ));
    return outcome;
  }

  /// L'enregistrement source a été supprimé : ses rappels aussi.
  Future<void> removeDeadlines(ReminderSource source, int sourceId) =>
      _mutate(() => _repo.deleteBySource(source, sourceId));

  // ----------------------------------------------- Planification et budget

  /// Enregistre les délais minimaux et le budget mensuel.
  Future<void> savePlanning(PlanningSettings settings) async {
    await _planning.save(settings);
    model.setPlanning(settings);
  }

  /// Applique les déplacements acceptés (journée chargée, budget). Ce n'est
  /// pas un report : le compteur de reports ne change pas. Renvoie le
  /// nombre de rappels déplacés.
  Future<int> applyMoves(List<ReminderMove> moves) async {
    var count = 0;
    for (final m in moves) {
      final current = model.byId(m.reminder.id) ?? m.reminder;
      if (current.isDone) continue;
      try {
        await _repo.update(current.copyWith(dueDate: m.to));
        count++;
      } on ReminderException {
        // Doublon à la nouvelle date : ce rappel reste en place.
      }
    }
    await load();
    return count;
  }

  // --------------------------------------------------------- Notifications

  Future<bool> requestNotificationPermission() =>
      _notifications.requestPermissions();

  Future<void> sendTestNotification() => _notifications.showTest();

  // ------------------------------------------------------------------ Démo

  /// HealthRecord fictif utilisé par les démonstrations (id négatif : jamais
  /// celui d'un vrai dossier de santé).
  static const demoHealthRecordId = -42;

  /// Jeu de données inspiré des exemples du cahier des charges.
  Future<int> seedDemo() async {
    final t = model.now;
    DateTime at(int days, [int hour = 9]) =>
        DateTime(t.year, t.month, t.day + days, hour);
    var vetDay = DateTime(t.year, 11, 20, 10, 30);
    if (!vetDay.isAfter(t)) vetDay = DateTime(t.year + 1, 11, 20, 10, 30);
    final pets = model.pets;
    final pair = pets.isEmpty ? null : pets.demoPair;
    final rex = pair?.$1.id;
    final mia = pair?.$2.id;

    final drafts = [
      Reminder(petId: rex, title: 'Vermifuge', type: ReminderType.deworming,
          dueDate: at(1, 8), repeat: ReminderRepeat.monthly),
      Reminder(petId: mia, title: 'Antipuces', type: ReminderType.treatment,
          dueDate: at(-2, 19), alertOffsets: const [AlertOffset.atTime]),
      Reminder(petId: mia, title: 'Rendez-vous vétérinaire',
          type: ReminderType.vetAppointment, dueDate: vetDay,
          notes: 'Clinique des Lilas — apporter le carnet de santé',
          alertOffsets: const [AlertOffset.oneDay, AlertOffset.oneHour]),
      Reminder(title: 'Acheter des croquettes', type: ReminderType.purchase,
          dueDate: at(5, 18), alertOffsets: const [AlertOffset.oneDay]),
      Reminder(petId: rex, title: 'Contrôle médical',
          type: ReminderType.checkup, dueDate: at(30, 11),
          alertOffsets: const [AlertOffset.oneWeek, AlertOffset.oneDay]),
      Reminder(petId: rex, title: 'Détartrage', type: ReminderType.other,
          dueDate: at(0, 23)),
    ];
    var count = 0;
    for (final d in drafts) {
      try {
        await _repo.create(d);
        count++;
      } on ReminderException catch (e) {
        if (!e.isConflict) rethrow; // Déjà présent : on ignore.
      }
    }
    // Les rappels automatiques viennent du module Santé (ses exemples).
    await load();
    return count;
  }

  /// Historique de soins déjà faits (à temps ou en retard), pour les
  /// statistiques d'observance. Les entrées déjà présentes sont ignorées.
  Future<int> seedHistory() async {
    final t = model.now;
    final pets = model.pets;
    final pair = pets.isEmpty ? null : pets.demoPair;
    final rex = pair?.$1.id;
    final mia = pair?.$2.id;
    DateTime monthsAgo(int months, [int hour = 8]) =>
        DateTime(t.year, t.month - months, 10, hour);

    // (rappel, jours de retard, nombre de reports)
    final items = <(Reminder, int, int)>[
      // Rex : 8 vermifuges d'affilée faits à l'heure.
      for (var m = 8; m >= 1; m--)
        (
          Reminder(petId: rex, title: 'Vermifuge', type: ReminderType.deworming,
              dueDate: monthsAgo(m)),
          0,
          0,
        ),
      // Mia : antipuces mensuel, parfois oublié.
      for (var m = 6; m >= 1; m--)
        (
          Reminder(petId: mia, title: 'Antipuces', type: ReminderType.treatment,
              dueDate: monthsAgo(m, 19)),
          m == 4 ? 3 : (m == 2 ? 5 : 0),
          0,
        ),
      // Rex : vaccin annuel, en retard de 12 jours l'an dernier.
      (
        Reminder(petId: rex, title: 'Vaccin CHPPi + rage',
            type: ReminderType.vaccination, dueDate: monthsAgo(24, 10)),
        0,
        0,
      ),
      (
        Reminder(petId: rex, title: 'Vaccin CHPPi + rage',
            type: ReminderType.vaccination, dueDate: monthsAgo(12, 10)),
        12,
        1,
      ),
      // Mia : rendez-vous reporté une fois, puis honoré.
      (
        Reminder(petId: mia, title: 'Rendez-vous vétérinaire',
            type: ReminderType.vetAppointment, dueDate: monthsAgo(3, 11)),
        0,
        1,
      ),
      // Achats de nourriture, deux fois en retard.
      for (var m = 4; m >= 1; m--)
        (
          Reminder(title: 'Acheter des croquettes', type: ReminderType.purchase,
              dueDate: monthsAgo(m, 18)),
          m.isOdd ? 2 : 0,
          0,
        ),
    ];

    var count = 0;
    for (final (draft, lateDays, postponed) in items) {
      final exists = model.all.any((r) =>
          r.isDone &&
          r.title == draft.title &&
          r.petId == draft.petId &&
          r.dueDate == draft.dueDate);
      if (exists) continue;
      final created = await _repo.create(draft);
      await _repo.update(created.copyWith(
        status: ReminderStatus.done,
        completedAt: () => draft.dueDate.add(Duration(days: lateDays, hours: 1)),
        postponeCount: postponed,
      ));
      count++;
    }
    await load();
    return count;
  }

  /// Simule l'enregistrement d'une prochaine échéance par le module Santé.
  Future<SyncOutcome> simulateHealthDeadline(DateTime dueDate) async {
    final (outcome, _) = await _mutate(() => _repo.syncFromSource(
          source: ReminderSource.health,
          sourceId: demoHealthRecordId,
          petId: model.pets.isEmpty ? null : model.pets.first.id,
          type: ReminderType.vaccination,
          title: 'Vaccination (dossier santé de démo)',
          dueDate: dueDate,
        ));
    return outcome;
  }

  void dispose() {
    _eventsSub?.cancel();
    _ticker?.cancel();
    intent.dispose();
  }
}
