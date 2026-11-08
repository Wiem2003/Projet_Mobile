import 'reminder.dart';
import 'reminder_calculator.dart';
import 'reminder_rules.dart';

/// Délai minimal entre deux types de soins pour un même animal (dans les
/// deux sens). Exemple : 7 jours entre un vaccin et un vermifuge.
class IntervalRule {
  const IntervalRule(this.first, this.second, this.days);

  static const maxDays = 90;

  final ReminderType first;
  final ReminderType second;
  final int days;

  bool concerns(ReminderType a, ReminderType b) =>
      (a == first && b == second) || (a == second && b == first);

  bool sameTypes(IntervalRule o) => concerns(o.first, o.second);

  Map<String, Object> toJson() => {'a': first.name, 'b': second.name, 'days': days};

  static IntervalRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final days = json['days'];
    if (days is! int || days < 1 || days > maxDays) return null;
    return IntervalRule(ReminderType.parse(json['a'] as String?),
        ReminderType.parse(json['b'] as String?), days);
  }

  @override
  bool operator ==(Object other) =>
      other is IntervalRule && sameTypes(other) && other.days == days;

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered([first, second]), days);
}

/// Réglages de planification d'un compte : délais minimaux entre soins et
/// budget mensuel des soins.
class PlanningSettings {
  const PlanningSettings({this.intervals = defaultIntervals, this.monthlyBudget});

  /// Réglage par défaut, à adapter selon l'avis du vétérinaire.
  static const defaultIntervals = [
    IntervalRule(ReminderType.vaccination, ReminderType.deworming, 7),
  ];
  static const maxBudget = 100000.0;

  final List<IntervalRule> intervals;

  /// Budget mensuel en DT (`null` = pas de plafond).
  final double? monthlyBudget;

  PlanningSettings copyWith({
    List<IntervalRule>? intervals,
    double? Function()? monthlyBudget,
  }) =>
      PlanningSettings(
        intervals: List.unmodifiable(intervals ?? this.intervals),
        monthlyBudget: monthlyBudget != null ? monthlyBudget() : this.monthlyBudget,
      );

  /// Ajoute la règle, ou remplace celle qui concerne les mêmes types.
  PlanningSettings withInterval(IntervalRule rule) => copyWith(intervals: [
        for (final r in intervals)
          if (!r.sameTypes(rule)) r,
        rule,
      ]);

  PlanningSettings withoutInterval(IntervalRule rule) =>
      copyWith(intervals: [for (final r in intervals) if (!r.sameTypes(rule)) r]);

  Map<String, Object?> toJson() => {
        'intervals': [for (final r in intervals) r.toJson()],
        'monthly_budget': monthlyBudget,
      };

  /// Lecture tolérante : une valeur invalide est ignorée.
  factory PlanningSettings.fromJson(Object? json) {
    if (json is! Map) return const PlanningSettings();
    final raw = json['intervals'];
    final budget = json['monthly_budget'];
    return PlanningSettings(
      intervals: raw is List
          ? List.unmodifiable(raw.map(IntervalRule.fromJson).whereType<IntervalRule>())
          : defaultIntervals,
      monthlyBudget: budget is num && budget > 0 && budget <= maxBudget
          ? budget.toDouble()
          : null,
    );
  }
}

/// Enregistrement des réglages (SQLite en production, mémoire en test).
abstract interface class PlanningSettingsStore {
  Future<PlanningSettings> load();
  Future<void> save(PlanningSettings settings);
}

class MemoryPlanningSettingsStore implements PlanningSettingsStore {
  MemoryPlanningSettingsStore([this.settings = const PlanningSettings()]);

  PlanningSettings settings;

  @override
  Future<PlanningSettings> load() async => settings;

  @override
  Future<void> save(PlanningSettings s) async => settings = s;
}

/// Délai non respecté entre deux soins d'un même animal.
class IntervalConflict {
  const IntervalConflict({required this.other, required this.rule, required this.earliest});

  /// Soin trop proche.
  final Reminder other;
  final IntervalRule rule;

  /// Première date qui respecte toutes les règles (même heure).
  final DateTime earliest;
}

/// Déplacement proposé d'un rappel (journée surchargée, budget dépassé).
class ReminderMove {
  const ReminderMove({required this.reminder, required this.to, required this.reason});

  final Reminder reminder;
  final DateTime to;
  final String reason;

  DateTime get from => reminder.dueDate;
}

/// Planification de la semaine : journées surchargées et délais minimaux
/// entre soins. Fonctions pures, `now` toujours injecté.
abstract final class ReminderPlanner {
  /// Au-delà, la journée est surchargée.
  static const maxPerDay = 3;

  /// Seuls les rappels peu graves (achats, « Autre ») sont déplacés.
  static const maxMovableSeverity = 2;

  /// Recherche d'un jour libre, de part et d'autre de la journée chargée.
  static const searchDays = 14;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _atDay(DateTime day, DateTime time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  /// Date d'un autre soin : celle où il a été fait, sinon son échéance.
  static DateTime _when(Reminder r) =>
      r.isDone ? (r.completedAt ?? r.dueDate) : r.dueDate;

  // --------------------------------------------- Délais minimaux entre soins

  /// Premier délai non respecté par un soin de [type] le [date] pour
  /// l'animal [petId], ou `null`. Un rappel général (sans animal) n'est
  /// jamais concerné.
  static IntervalConflict? intervalConflict({
    required int? petId,
    required ReminderType type,
    required DateTime date,
    required Iterable<Reminder> others,
    required List<IntervalRule> rules,
    int? selfId,
  }) {
    if (petId == null || rules.isEmpty) return null;
    final first = _conflictAt(petId, type, date, others, rules, selfId);
    if (first == null) return null;
    return IntervalConflict(
      other: first.$1,
      rule: first.$2,
      earliest: firstAllowedDate(
          petId: petId, type: type, date: date, others: others, rules: rules, selfId: selfId),
    );
  }

  static (Reminder, IntervalRule)? _conflictAt(int petId, ReminderType type,
      DateTime date, Iterable<Reminder> others, List<IntervalRule> rules, int? selfId) {
    for (final o in others) {
      if (o.petId != petId || (selfId != null && o.id == selfId)) continue;
      for (final rule in rules) {
        if (!rule.concerns(type, o.type)) continue;
        final gap = ReminderCalculator.daysUntil(date, _when(o)).abs();
        if (gap < rule.days) return (o, rule);
      }
    }
    return null;
  }

  /// Première date, à partir de [date] et à la même heure, qui respecte
  /// toutes les règles.
  static DateTime firstAllowedDate({
    required int petId,
    required ReminderType type,
    required DateTime date,
    required Iterable<Reminder> others,
    required List<IntervalRule> rules,
    int? selfId,
  }) {
    var d = date;
    for (var i = 0; i < 50; i++) {
      final c = _conflictAt(petId, type, d, others, rules, selfId);
      if (c == null) return d;
      final (other, rule) = c;
      final w = _when(other);
      d = _atDay(DateTime(w.year, w.month, w.day + rule.days), date);
    }
    return d;
  }

  // ------------------------------------------------- Journées surchargées

  /// Rappels non faits par jour, à partir d'aujourd'hui.
  static Map<DateTime, List<Reminder>> _byDay(Iterable<Reminder> all, DateTime now) {
    final today = _day(now);
    final map = <DateTime, List<Reminder>>{};
    for (final r in all) {
      if (r.isDone || _day(r.dueDate).isBefore(today)) continue;
      map.putIfAbsent(_day(r.dueDate), () => []).add(r);
    }
    return map;
  }

  /// Journées de plus de [maxPerDay] rappels, de la plus proche à la plus
  /// lointaine.
  static List<(DateTime day, List<Reminder> reminders)> overloadedDays(
      Iterable<Reminder> all, DateTime now) {
    final days = _byDay(all, now).entries.where((e) => e.value.length > maxPerDay).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final e in days)
        (e.key, e.value..sort((a, b) => a.dueDate.compareTo(b.dueDate))),
    ];
  }

  /// Déplacements proposés pour alléger les journées surchargées : les
  /// rappels peu graves vont vers le jour libre le plus proche (après, puis
  /// avant), sans créer de nouvelle surcharge ni enfreindre un délai minimal.
  static List<ReminderMove> lighten(
      Iterable<Reminder> all, DateTime now, List<IntervalRule> rules) {
    final load = {
      for (final e in _byDay(all, now).entries) e.key: e.value.length,
    };
    final moves = <ReminderMove>[];
    for (final (day, items) in overloadedDays(all, now)) {
      var excess = items.length - maxPerDay;
      final movable = items
          .where((r) => ReminderRules.severity(r.type) <= maxMovableSeverity)
          .toList()
        ..sort((a, b) {
          final s = ReminderRules.severity(a.type).compareTo(ReminderRules.severity(b.type));
          return s != 0 ? s : b.dueDate.compareTo(a.dueDate);
        });
      for (final r in movable) {
        if (excess <= 0) break;
        final to = _nearestFreeDay(r, day, now, load, all, rules);
        if (to == null) continue;
        moves.add(ReminderMove(
          reminder: r,
          to: to,
          reason: 'Journée chargée (${items.length} rappels)',
        ));
        load[day] = load[day]! - 1;
        load[_day(to)] = (load[_day(to)] ?? 0) + 1;
        excess--;
      }
    }
    return moves;
  }

  static DateTime? _nearestFreeDay(Reminder r, DateTime day, DateTime now,
      Map<DateTime, int> load, Iterable<Reminder> all, List<IntervalRule> rules) {
    for (var offset = 1; offset <= searchDays; offset++) {
      for (final sign in const [1, -1]) {
        final d = DateTime(day.year, day.month, day.day + sign * offset);
        final at = _atDay(d, r.dueDate);
        if (!at.isAfter(now) || (load[d] ?? 0) >= maxPerDay) continue;
        final conflict = r.petId == null
            ? null
            : _conflictAt(r.petId!, r.type, at, all, rules, r.id);
        if (conflict == null) return at;
      }
    }
    return null;
  }
}
