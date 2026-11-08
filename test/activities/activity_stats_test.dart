import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_stats.dart';

void main() {
  // Mardi 3 novembre 2026, 14 h.
  final now = DateTime(2026, 11, 3, 14);

  Activity act(DateTime date, {int min = 30, double km = 0}) => Activity(
      petId: 1,
      date: date,
      type: ActivityType.walk,
      durationMin: min,
      distanceKm: km);

  test('calories estimées : MET × poids × durée', () {
    expect(estimateCalories(ActivityType.walk, 28, 45), closeTo(63, 1e-9));
    expect(estimateCalories(ActivityType.run, 10, 60), 70);
    expect(estimateCalories(ActivityType.walk, null, 45), 0);
    expect(estimateCalories(ActivityType.walk, 28, 0), 0);
  });

  test('distance hebdomadaire et évolution (semaines glissantes)', () {
    final s = ActivityStats.compute([
      act(DateTime(2026, 11, 3, 8), km: 3, min: 40), // Semaine actuelle.
      act(DateTime(2026, 10, 28), km: 2, min: 20), // 1er jour de la semaine.
      act(DateTime(2026, 10, 27, 23), km: 4, min: 60), // Semaine précédente.
      act(DateTime(2026, 10, 21), km: 1, min: 20),
      act(DateTime(2026, 9, 1), km: 10, min: 90), // Hors des 6 semaines.
    ], now: now);

    expect(s.weeks, hasLength(6));
    expect(s.weeks.first.start, DateTime(2026, 9, 23));
    expect(s.thisWeek.start, DateTime(2026, 10, 28));
    expect(s.weeklyDistanceKm, 5);
    expect((s.thisWeek.minutes, s.thisWeek.count), (60, 2));
    expect((s.lastWeek!.distanceKm, s.lastWeek!.minutes), (5, 80));
    expect(s.distanceChange, 0);
    expect(s.minutesChange, closeTo(-0.25, 1e-9));
  });

  test('période choisie : nombre d\'activités et durée moyenne', () {
    final list = [
      act(DateTime(2026, 11, 3, 9), min: 30),
      act(DateTime(2026, 10, 30), min: 60),
      act(DateTime(2026, 10, 10), min: 90),
      act(DateTime(2026, 7, 1), min: 10),
    ];
    ActivityStats on(ActivityPeriod p) =>
        ActivityStats.compute(list, now: now, period: p);

    expect((on(ActivityPeriod.week).count, on(ActivityPeriod.week).averageDurationMin),
        (2, 45));
    expect((on(ActivityPeriod.month).count, on(ActivityPeriod.month).averageDurationMin),
        (3, 60));
    expect(on(ActivityPeriod.all).averageDurationMin, 47.5);
    expect(on(ActivityPeriod.all).totalMinutes, 190);

    final empty = ActivityStats.compute(const [], now: now);
    expect(empty.averageDurationMin, 0);
    expect(empty.distanceChange, isNull);
  });

  test('GPS : distance haversine et stockage du trajet', () {
    expect(Geo.distanceKm(const GeoPoint(0, 0), const GeoPoint(1, 0)),
        closeTo(111.19, 0.01));
    final route = [
      GeoPoint(36.8, 10.18, DateTime(2026, 11, 3, 8)),
      GeoPoint(36.809, 10.18, DateTime(2026, 11, 3, 8, 10)),
    ];
    expect(Geo.pathKm(route), closeTo(1.0, 0.01));

    final back = Geo.decode(Geo.encode(route));
    expect(back, hasLength(2));
    expect((back[1].lat, back[1].lng), (36.809, 10.18));
    expect(back[1].at, DateTime(2026, 11, 3, 8, 10));
    expect(Geo.encode(const []), isNull);
    expect(Geo.decode('pas du json'), isEmpty);
  });
}
