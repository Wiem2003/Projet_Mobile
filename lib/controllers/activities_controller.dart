import 'dart:math' as math;

import '../core/pets/pet_directory.dart';
import '../models/activities_model.dart';
import '../models/activity.dart';
import '../models/activity_insights.dart';
import '../models/notifications/achievement_notifier.dart';
import '../models/activity_repository.dart';
import '../models/activity_stats.dart';

/// Controller du module Activités.
///
/// Reçoit les actions de la View (filtres, ajout, modification, suppression),
/// applique les règles via le repository SQLite (dont le calcul des
/// calories) puis met à jour l'[ActivitiesModel] que la View observe.
/// Les erreurs métier remontent en `RecordException` à la View.
class ActivitiesController {
  ActivitiesController({
    required this.model,
    required ActivityRepository repository,
    required PetDirectory pets,
    AchievementNotifier? recordNotifier,
  })  : _repo = repository,
        _petDirectory = pets,
        _achievements = recordNotifier;

  final ActivitiesModel model;
  final ActivityRepository _repo;
  final PetDirectory _petDirectory;
  final AchievementNotifier? _achievements;

  // --------------------------------------------------------------- Filtres

  void setPetFilter(int? id) => model.setPetFilter(id);
  void setTypeFilter(ActivityType? t) => model.setTypeFilter(t);
  void setPeriod(ActivityPeriod p) => model.setPeriod(p);

  // --------------------------------------------------------------- Actions

  Future<void> load() async {
    try {
      // Toujours relus : le module Animaux a pu les modifier.
      model.setPets(await _petDirectory.getPets());
      model.setActivities(await _repo.getAll());
    } on Exception catch (e) {
      model.setError('Impossible de charger les activités : $e');
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final result = await action();
    await load();
    return result;
  }

  /// Enregistre ; une nouvelle activité qui bat un record de l'animal
  /// déclenche une notification « Nouveau record pour Rex : 6,2 km ! ».
  Future<Activity> save(Activity a) async {
    final before = model.all;
    final saved = await _mutate(() => a.id == null ? _repo.create(a) : _repo.update(a));
    if (a.id == null) {
      final name = model.petOf(saved.petId)?.name ?? 'votre animal';
      final records = ActivityInsights.newRecords(before, saved, name);
      model.setLastRecords(saved.petId, records);
      if (records.isNotEmpty) {
        await _achievements?.showAchievement(
            title: '🏆 ${records.first}', body: records.join(' · '));
      }
    }
    return saved;
  }

  Future<void> delete(Activity a) => _mutate(() => _repo.delete(a.id!));

  // ------------------------------------------------------------------ Démo

  /// Six semaines d'activités pour les animaux de démonstration, dont une
  /// promenade enregistrée au GPS. Ne crée pas de doublon (animal + heure).
  Future<int> seedDemo() async {
    final pets = model.pets;
    if (pets.isEmpty) return 0;
    final (rex, mia) = pets.demoPair;
    final now = model.now;
    final today = DateTime(now.year, now.month, now.day);

    final existing = {for (final a in model.all) (a.petId, a.date)};
    var count = 0;
    Future<void> add(Activity a) async {
      if (a.date.isAfter(now) || !existing.add((a.petId, a.date))) return;
      await _repo.create(a);
      count++;
    }

    for (var i = 41; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day - i);
      final week = (41 - i) ~/ 7; // 0 = il y a 6 semaines.
      final jitter = (i * 37 % 11) / 10; // 0 à 1, reproductible.
      if (i % 7 != 2) {
        final km = 2.0 + week * 0.15 + jitter * 1.4;
        await add(Activity(
          petId: rex.id,
          date: day.add(const Duration(hours: 7, minutes: 30)),
          type: ActivityType.walk,
          durationMin: (km * 13).round(),
          distanceKm: double.parse(km.toStringAsFixed(1)),
          weightKg: rex.weightKg,
        ));
      }
      if (day.weekday == DateTime.sunday) {
        await add(Activity(
          petId: rex.id,
          date: day.add(const Duration(hours: 17)),
          type: ActivityType.run,
          durationMin: 30 + week * 2,
          distanceKm: 5 + week * 0.3,
          weightKg: rex.weightKg,
          description: 'Footing au parc',
        ));
      }
      if (i.isEven) {
        await add(Activity(
          petId: mia.id,
          date: day.add(const Duration(hours: 20)),
          type: ActivityType.play,
          durationMin: 12 + (jitter * 10).round(),
          weightKg: mia.weightKg,
          description: 'Canne à pêche et balle',
        ));
      }
    }
    await add(Activity(
      petId: rex.id,
      date: today.subtract(const Duration(days: 6)).add(const Duration(hours: 10)),
      type: ActivityType.swim,
      durationMin: 20,
      distanceKm: 0.4,
      weightKg: rex.weightKg,
      description: 'Baignade à la plage',
    ));

    // Promenade GPS de démonstration (boucle autour du parc du Belvédère).
    final start = today.subtract(const Duration(days: 1)).add(const Duration(hours: 18));
    final route = demoRoute(start);
    await add(Activity(
      petId: rex.id,
      date: start,
      type: ActivityType.walk,
      durationMin: 42,
      distanceKm: double.parse(Geo.pathKm(route).toStringAsFixed(2)),
      weightKg: rex.weightKg,
      description: 'Promenade enregistrée au GPS',
      route: route,
    ));

    await load();
    return count;
  }

  /// Boucle d'environ 3 km utilisée par la démonstration.
  static List<GeoPoint> demoRoute(DateTime start) {
    const lat = 36.8195, lng = 10.1760, points = 60;
    return [
      for (var i = 0; i <= points; i++)
        () {
          final t = 2 * math.pi * i / points;
          final wobble = 1 + 0.12 * math.sin(5 * t);
          return GeoPoint(
            lat + 0.0042 * wobble * math.sin(t),
            lng + 0.0058 * wobble * (1 - math.cos(t)),
            start.add(Duration(seconds: 42 * i)),
          );
        }(),
    ];
  }
}
