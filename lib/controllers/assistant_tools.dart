import '../models/activities_model.dart';
import '../models/activity_stats.dart';
import '../models/feeding_model.dart';
import '../models/feeding_stats.dart';
import '../models/health_model.dart';
import '../models/health_stats.dart';
import '../models/pets_model.dart';
import '../models/reminder.dart';
import '../models/reminder_exception.dart';
import 'reminders_controller.dart';

/// Résultat d'un outil : la réponse envoyée au modèle et les rappels à
/// afficher en cartes sous le message.
typedef ToolResult = ({Map<String, Object?> response, List<Reminder> cards});

/// Outils mis à disposition de Gemini (function calling).
///
/// Les lectures portent sur les cinq modules ; les actions concernent
/// uniquement les rappels et passent par le [RemindersController] (mêmes
/// règles métier, même base SQLite, mêmes notifications que l'écran).
class AssistantTools {
  AssistantTools({
    required this.reminders,
    required this.pets,
    required this.health,
    required this.feeding,
    required this.activities,
  });

  final RemindersController reminders;
  final PetsModel pets;
  final HealthModel health;
  final FeedingModel feeding;
  final ActivitiesModel activities;

  DateTime get now => reminders.model.now;

  /// Suppression demandée, en attente de la confirmation de l'utilisateur.
  int? pendingDeleteId;

  /// Vrai si le dernier message de l'utilisateur confirme la suppression.
  bool userConfirmed = false;

  // ---------------------------------------------------------- Déclarations

  static const _petName = {
    'type': 'STRING',
    'description': 'Nom de l\'animal (facultatif : tous les animaux sinon).',
  };

  static final declarations = <Map<String, Object?>>[
    {
      'name': 'get_pets',
      'description': 'Liste les animaux : espèce, race, sexe, âge, poids.',
      'parameters': {'type': 'OBJECT', 'properties': <String, Object?>{}},
    },
    {
      'name': 'get_reminders',
      'description': 'Lit les rappels (vaccins, vermifuges, rendez-vous, achats...).',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'scope': {
            'type': 'STRING',
            'enum': ['overdue', 'today', 'week', 'upcoming', 'done'],
            'description': 'overdue = en retard, week = 7 prochains jours, '
                'upcoming = tous les rappels à venir, done = historique.',
          },
          'pet_name': _petName,
        },
        'required': ['scope'],
      },
    },
    {
      'name': 'get_health_summary',
      'description': 'Santé : consultations, dépenses médicales, poids moyen, '
          'évolution du poids, prochaines échéances, derniers soins.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'pet_name': _petName,
          'period': {
            'type': 'STRING',
            'enum': ['3_months', '12_months', 'all'],
          },
        },
      },
    },
    {
      'name': 'get_feeding_summary',
      'description': 'Alimentation d\'un mois : quantité consommée, dépense, '
          'moyenne quotidienne, évolution des dépenses.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'pet_name': _petName,
          'month': {'type': 'STRING', 'description': 'Mois au format YYYY-MM.'},
        },
      },
    },
    {
      'name': 'get_activity_summary',
      'description': 'Activités : distance hebdomadaire, durée moyenne, nombre '
          'd\'activités, évolution semaine actuelle / précédente, calories.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'pet_name': _petName,
          'period': {
            'type': 'STRING',
            'enum': ['7_days', '30_days', '3_months', 'all'],
          },
        },
      },
    },
    {
      'name': 'create_reminder',
      'description': 'Crée un rappel avec ses notifications.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING'},
          'type': {
            'type': 'STRING',
            'enum': [for (final t in ReminderType.values) t.name],
          },
          'date_time': {
            'type': 'STRING',
            'description': 'Date et heure locales, format YYYY-MM-DDTHH:MM.',
          },
          'pet_name': _petName,
          'repeat': {
            'type': 'STRING',
            'enum': [for (final r in ReminderRepeat.values) r.name],
          },
          'notes': {'type': 'STRING'},
        },
        'required': ['title', 'type', 'date_time'],
      },
    },
    {
      'name': 'mark_reminder_done',
      'description': 'Marque un rappel comme fait (crée la prochaine '
          'occurrence s\'il est répété).',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'reminder_id': {'type': 'INTEGER'},
        },
        'required': ['reminder_id'],
      },
    },
    {
      'name': 'postpone_reminder',
      'description': 'Reporte un rappel à une nouvelle date.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'reminder_id': {'type': 'INTEGER'},
          'new_date_time': {
            'type': 'STRING',
            'description': 'Format YYYY-MM-DDTHH:MM.',
          },
        },
        'required': ['reminder_id', 'new_date_time'],
      },
    },
    {
      'name': 'delete_reminder',
      'description': 'Supprime un rappel. Premier appel sans confirmed : '
          'l\'application demande confirmation à l\'utilisateur. Rappeler '
          'avec confirmed=true seulement après son « oui ».',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'reminder_id': {'type': 'INTEGER'},
          'confirmed': {'type': 'BOOLEAN'},
        },
        'required': ['reminder_id'],
      },
    },
  ];

  // ------------------------------------------------------------- Exécution

  Future<ToolResult> run(String name, Map<String, Object?> args) async {
    try {
      return switch (name) {
        'get_pets' => _ok(_pets()),
        'get_reminders' => _getReminders(args),
        'get_health_summary' => _ok(_health(args)),
        'get_feeding_summary' => _ok(_feeding(args)),
        'get_activity_summary' => _ok(_activities(args)),
        'create_reminder' => await _create(args),
        'mark_reminder_done' => await _markDone(args),
        'postpone_reminder' => await _postpone(args),
        'delete_reminder' => await _delete(args),
        _ => _error('Outil inconnu : $name'),
      };
    } on ReminderException catch (e) {
      return _error(e.message);
    } on _ToolError catch (e) {
      return _error(e.message);
    }
  }

  static ToolResult _ok(Map<String, Object?> response,
          [List<Reminder> cards = const []]) =>
      (response: response, cards: cards);

  static ToolResult _error(String message) =>
      (response: {'error': message}, cards: const []);

  // ------------------------------------------------------------ Arguments

  int? _petId(Map<String, Object?> args) {
    final name = (args['pet_name'] as String?)?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    for (final p in pets.all) {
      if (p.name.toLowerCase() == name) return p.id;
    }
    throw _ToolError('Animal inconnu : « ${args['pet_name']} ». '
        'Animaux : ${pets.all.map((p) => p.name).join(', ')}.');
  }

  static DateTime _date(Object? value, String field) {
    final d = value is String ? DateTime.tryParse(value) : null;
    if (d == null) throw _ToolError('$field invalide : attendu YYYY-MM-DDTHH:MM.');
    return d;
  }

  Reminder _reminder(Map<String, Object?> args) {
    final id = (args['reminder_id'] as num?)?.toInt();
    final r = reminders.model.byId(id);
    if (r == null) throw _ToolError('Rappel introuvable (id $id).');
    return r;
  }

  String _petNameOf(int? id) {
    for (final p in pets.all) {
      if (p.id == id) return p.name;
    }
    return 'tous';
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 16);
  static double _round(double v) => (v * 100).round() / 100;

  Map<String, Object?> _describe(Reminder r) => {
        'id': r.id,
        'title': r.title,
        'type': r.type.name,
        'date_time': _iso(r.dueDate),
        'pet': _petNameOf(r.petId),
        'status': r.isDone
            ? 'done'
            : r.isOverdue(now)
                ? 'overdue'
                : 'upcoming',
        if (r.repeat != ReminderRepeat.none) 'repeat': r.repeat.name,
        if (r.isAutomatic) 'source': r.source.label,
        if (r.notes != null) 'notes': r.notes,
      };

  // --------------------------------------------------------------- Lecture

  Map<String, Object?> _pets() => {
        'pets': [
          for (final p in pets.all)
            {
              'name': p.name,
              'species': p.species.label,
              'breed': ?p.breed,
              'sex': p.sex.label,
              'age': ?p.ageLabel(now),
              'weight_kg': ?p.weightKg,
              'color': ?p.color,
            },
        ],
      };

  ToolResult _getReminders(Map<String, Object?> args) {
    final pet = _petId(args);
    final n = now;
    final today = DateTime(n.year, n.month, n.day);
    final all = reminders.model.all
        .where((r) => pet == null || r.petId == pet)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final open = all.where((r) => !r.isDone);
    final list = switch (args['scope']) {
      'overdue' => open.where((r) => r.isOverdue(n)).toList(),
      'today' => open
          .where((r) => !r.dueDate.isBefore(today) &&
              r.dueDate.isBefore(today.add(const Duration(days: 1))))
          .toList(),
      'week' => open
          .where((r) => !r.isOverdue(n) &&
              r.dueDate.isBefore(today.add(const Duration(days: 8))))
          .toList(),
      'done' => all.where((r) => r.isDone).toList().reversed.toList(),
      _ => open.where((r) => !r.isOverdue(n)).toList(),
    };
    return _ok({
      'count': list.length,
      'reminders': [for (final r in list.take(15)) _describe(r)],
    }, list.take(4).toList());
  }

  Map<String, Object?> _health(Map<String, Object?> args) {
    final pet = _petId(args);
    final period = switch (args['period']) {
      '3_months' => HealthPeriod.quarter,
      'all' => HealthPeriod.all,
      _ => HealthPeriod.year,
    };
    final records = health.all.where((r) => pet == null || r.petId == pet);
    final s = HealthStats.compute(records,
        now: now, period: period, singlePet: pet != null);
    final today = DateTime(now.year, now.month, now.day);
    return {
      'pet': _petNameOf(pet),
      'period': period.label,
      'records': s.recordCount,
      'consultations': s.consultations,
      'medical_spending_dt': _round(s.spending),
      'spending_by_type_dt': {
        for (final e in s.spendingByType.entries) e.key.label: _round(e.value),
      },
      if (pet == null) 'weight_note': 'Préciser un animal pour le poids.',
      if (s.averageWeight != null) 'average_weight_kg': _round(s.averageWeight!),
      if (s.weightChangeKg != null) 'weight_change_kg': _round(s.weightChangeKg!),
      'weighings': [
        for (final w in s.weights) {'date': _iso(w.date).substring(0, 10), 'kg': w.kg},
      ],
      'upcoming_deadlines': [
        for (final r in records.where(
            (r) => r.nextDue != null && !r.nextDue!.isBefore(today)))
          {
            'type': r.type.label,
            'due': _iso(r.nextDue!).substring(0, 10),
            'pet': _petNameOf(r.petId),
          },
      ],
      'last_records': [
        for (final r in records.take(5))
          {
            'date': _iso(r.date).substring(0, 10),
            'type': r.type.label,
            'pet': _petNameOf(r.petId),
            'vet': ?r.vet,
            'medication': ?r.medication,
            'description': ?r.description,
            'cost_dt': r.cost,
          },
      ],
    };
  }

  Map<String, Object?> _feeding(Map<String, Object?> args) {
    final pet = _petId(args);
    final m = args['month'] is String
        ? DateTime.tryParse('${args['month']}-01')
        : null;
    final month = m ?? DateTime(now.year, now.month);
    final s = FeedingStats.compute(
        feeding.all.where((r) => pet == null || r.petId == pet),
        month: month,
        now: now);
    return {
      'pet': _petNameOf(pet),
      'month': _iso(s.month).substring(0, 7),
      'records': s.recordCount,
      'meals': s.meals,
      'quantity_g': _round(s.quantityG),
      'spending_dt': _round(s.spending),
      'daily_average_g': _round(s.dailyAverageG),
      'days_counted': s.days,
      if (s.spendingChange != null)
        'spending_change_vs_previous_month_percent':
            (s.spendingChange! * 100).round(),
      if (s.comparedDays != null)
        'spending_change_compares_days_1_to': s.comparedDays,
      'spending_by_month_dt': {
        for (final x in s.spendingByMonth)
          _iso(x.month).substring(0, 7): _round(x.value),
      },
    };
  }

  Map<String, Object?> _activities(Map<String, Object?> args) {
    final pet = _petId(args);
    final period = switch (args['period']) {
      '7_days' => ActivityPeriod.week,
      '3_months' => ActivityPeriod.quarter,
      'all' => ActivityPeriod.all,
      _ => ActivityPeriod.month,
    };
    final s = ActivityStats.compute(
        activities.all.where((a) => pet == null || a.petId == pet),
        now: now,
        period: period);
    return {
      'pet': _petNameOf(pet),
      'period': period.label,
      'activities': s.count,
      'average_duration_min': _round(s.averageDurationMin),
      'total_distance_km': _round(s.totalDistanceKm),
      'total_calories': s.totalCalories.round(),
      'weekly_distance_km_last_7_days': _round(s.weeklyDistanceKm),
      if (s.distanceChange != null)
        'distance_change_vs_previous_week_percent': (s.distanceChange! * 100).round(),
      if (s.minutesChange != null)
        'activity_time_change_vs_previous_week_percent':
            (s.minutesChange! * 100).round(),
      'weekly_distances_km': [for (final w in s.weeks) _round(w.distanceKm)],
    };
  }

  // --------------------------------------------------------------- Actions

  Future<ToolResult> _create(Map<String, Object?> args) async {
    final saved = await reminders.save(Reminder(
      petId: _petId(args),
      title: ((args['title'] as String?) ?? '').trim(),
      type: ReminderType.parse(args['type'] as String?),
      dueDate: _date(args['date_time'], 'date_time'),
      repeat: ReminderRepeat.parse(args['repeat'] as String?),
      notes: args['notes'] as String?,
    ));
    return _ok({'created': _describe(saved)}, [saved]);
  }

  Future<ToolResult> _markDone(Map<String, Object?> args) async {
    final result = await reminders.markDone(_reminder(args));
    return _ok({
      'done': _describe(result.done),
      if (result.next != null) 'next_occurrence': _describe(result.next!),
    }, [result.next ?? result.done]);
  }

  Future<ToolResult> _postpone(Map<String, Object?> args) async {
    final saved = await reminders.postpone(
        _reminder(args), _date(args['new_date_time'], 'new_date_time'));
    return _ok({'postponed': _describe(saved)}, [saved]);
  }

  /// La suppression n'a lieu qu'après un « oui » explicite de
  /// l'utilisateur, vérifié par l'application (pas seulement par le modèle).
  Future<ToolResult> _delete(Map<String, Object?> args) async {
    final r = _reminder(args);
    if (args['confirmed'] == true && pendingDeleteId == r.id && userConfirmed) {
      pendingDeleteId = null;
      await reminders.delete(r);
      return _ok({'deleted': _describe(r)});
    }
    pendingDeleteId = r.id;
    return _ok({
      'status': 'confirmation_required',
      'instruction': 'Demande à l\'utilisateur de confirmer la suppression de '
          'ce rappel. Ne rappelle delete_reminder avec confirmed=true que '
          's\'il répond oui.',
      'reminder': _describe(r),
    }, [r]);
  }
}

class _ToolError implements Exception {
  const _ToolError(this.message);

  final String message;
}
