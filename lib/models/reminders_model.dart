import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'reminder.dart';
import 'reminder_calculator.dart';
import 'health_record.dart';
import 'reminder_budget.dart';
import 'reminder_compliance.dart';
import 'reminder_planning.dart';
import 'reminder_rules.dart';

enum ReminderTab { upcoming, overdue, done }

/// Model observable du module Rappels : rappels chargés depuis SQLite,
/// animaux, filtres d'affichage et indicateurs calculés.
///
/// Les Views l'écoutent (`context.watch<RemindersModel>()`) ; seul le
/// [RemindersController] le modifie.
class RemindersModel extends ChangeNotifier {
  RemindersModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  List<Reminder> _all = const [];
  List<PetSummary> _pets = const [];
  PlanningSettings _planning = const PlanningSettings();
  List<HealthRecord> _healthRecords = const [];
  bool _loading = true;
  String? _error;

  ReminderTab _tab = ReminderTab.upcoming;
  ReminderType? _typeFilter;
  int? _petFilter;
  DateTime? _dayFilter;
  String _query = '';

  // ---------------------------------------------------------------- Données

  DateTime get now => _clock();
  bool get loading => _loading;

  /// Dernière erreur de chargement.
  String? get error => _error;
  bool get isEmpty => _all.isEmpty;

  /// Tous les rappels, sans filtre d'écran (assistant, Dashboard).
  List<Reminder> get all => List.unmodifiable(_all);
  List<PetSummary> get pets => _pets;
  ReminderTab get tab => _tab;
  ReminderType? get typeFilter => _typeFilter;
  int? get petFilter => _petFilter;
  DateTime? get dayFilter => _dayFilter;
  String get query => _query;
  bool get hasActiveFilters =>
      _typeFilter != null || _dayFilter != null || _query.isNotEmpty;

  PetSummary? petOf(Reminder r) {
    for (final p in _pets) {
      if (p.id == r.petId) return p;
    }
    return null;
  }

  Reminder? byId(int? id) {
    for (final r in _all) {
      if (r.id == id) return r;
    }
    return null;
  }

  Iterable<Reminder> get _forPet =>
      _petFilter == null ? _all : _all.where((r) => r.petId == _petFilter);

  Iterable<Reminder> get _filtered {
    final q = _query.trim().toLowerCase();
    return _forPet.where((r) {
      if (_typeFilter != null && r.type != _typeFilter) return false;
      if (_dayFilter != null &&
          ReminderCalculator.daysUntil(r.dueDate, _dayFilter!) != 0) {
        return false;
      }
      if (q.isNotEmpty &&
          !r.title.toLowerCase().contains(q) &&
          !(r.notes?.toLowerCase().contains(q) ?? false) &&
          !(petOf(r)?.name.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    });
  }

  /// En retard, du plus urgent au moins urgent (gravité × jours de retard).
  List<Reminder> get overdue {
    final t = now;
    return _filtered.where((r) => r.isOverdue(t)).toList()
      ..sort((a, b) => ReminderRules.compareByUrgency(a, b, t));
  }

  /// Rappels en retard depuis plus de 3 jours.
  int get criticalCount =>
      _forPet.where((r) => ReminderRules.isCritical(r, now)).length;

  // ------------------------------------------- Planification et budget

  /// Délais minimaux entre soins et budget mensuel du compte.
  PlanningSettings get planning => _planning;

  /// Dossiers de santé (coûts des soins passés), pour le budget.
  List<HealthRecord> get healthRecords => _healthRecords;

  /// Journées de plus de 3 rappels (tous les animaux).
  List<(DateTime, List<Reminder>)> get overloadedDays =>
      ReminderPlanner.overloadedDays(_all, now);

  /// Déplacements proposés pour alléger ces journées.
  List<ReminderMove> get lightenMoves =>
      ReminderPlanner.lighten(_all, now, _planning.intervals);

  /// Prévision des 3 prochains mois (tous les animaux).
  List<MonthForecast> get forecasts => ReminderBudget.forecast(
      _all, _healthRecords, now, budget: _planning.monthlyBudget);

  /// Premier mois prévu au-delà du budget, s'il y en a un.
  MonthForecast? get overBudgetMonth {
    for (final f in forecasts) {
      if (f.overBudget) return f;
    }
    return null;
  }

  /// Délai minimal non respecté par un soin prévu à [date].
  IntervalConflict? intervalConflict(
          {required int? petId, required ReminderType type, required DateTime date, int? selfId}) =>
      ReminderPlanner.intervalConflict(
          petId: petId, type: type, date: date, others: _all,
          rules: _planning.intervals, selfId: selfId);

  /// Observance (soins faits à temps), pour l'animal filtré ou tous.
  ComplianceReport get compliance => ComplianceReport.compute(_forPet, now);

  List<Reminder> get upcoming =>
      _filtered.where((r) => !r.isDone && !r.isOverdue(now)).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  List<Reminder> get done => _filtered.where((r) => r.isDone).toList()
    ..sort((a, b) => (b.completedAt ?? b.dueDate)
        .compareTo(a.completedAt ?? a.dueDate));

  int countFor(ReminderTab t) => switch (t) {
        ReminderTab.upcoming => upcoming.length,
        ReminderTab.overdue => overdue.length,
        ReminderTab.done => done.length,
      };

  /// Rappels à venir regroupés : Aujourd'hui, Demain, Cette semaine...
  List<(ReminderBucket, List<Reminder>)> get upcomingSections {
    final map = <ReminderBucket, List<Reminder>>{};
    for (final r in upcoming) {
      map.putIfAbsent(ReminderCalculator.bucketOf(r, now), () => []).add(r);
    }
    return [
      for (final b in ReminderBucket.values)
        if (map[b] != null) (b, map[b]!),
    ];
  }

  ReminderStats get stats => ReminderStats.compute(_forPet, now);

  /// Types de rappels non terminés par jour (pastilles du calendrier).
  List<ReminderType> typesOnDay(DateTime day) => _forPet
      .where((r) =>
          !r.isDone && ReminderCalculator.daysUntil(r.dueDate, day) == 0)
      .map((r) => r.type)
      .toList();

  // ------------------------------------------- Mises à jour (Controller)

  void setReminders(List<Reminder> reminders) {
    _all = List.unmodifiable(reminders);
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void setPets(List<PetSummary> pets) => _pets = List.unmodifiable(pets);

  /// Sans notification : suivi par [setReminders] au chargement.
  void setPlanningData(PlanningSettings planning, List<HealthRecord> health) {
    _planning = planning;
    _healthRecords = List.unmodifiable(health);
  }

  void setPlanning(PlanningSettings planning) {
    _planning = planning;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    _loading = false;
    notifyListeners();
  }

  void setTab(ReminderTab t) {
    if (_tab == t) return;
    _tab = t;
    notifyListeners();
  }

  void setTypeFilter(ReminderType? t) {
    _typeFilter = t;
    notifyListeners();
  }

  void setPetFilter(int? id) {
    _petFilter = id;
    notifyListeners();
  }

  void setDayFilter(DateTime? day) {
    _dayFilter = day;
    if (day != null) _tab = ReminderTab.upcoming;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void clearFilters() {
    _typeFilter = null;
    _dayFilter = null;
    _query = '';
    notifyListeners();
  }

  /// Rafraîchit les comptes à rebours et le statut « en retard ».
  void refresh() {
    if (_all.isNotEmpty) notifyListeners();
  }
}
