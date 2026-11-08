import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqliteActivityRepository repo;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() {
    db = memoryDatabase();
    repo = SqliteActivityRepository(db, clock: clock.call);
  });
  tearDown(() => db.close());

  Activity draft({
    int petId = rexId,
    DateTime? date,
    ActivityType type = ActivityType.walk,
    int durationMin = 45,
    double distanceKm = 3.2,
    double? weightKg = 28,
    String? description,
    List<GeoPoint>? route,
  }) =>
      Activity(
        petId: petId,
        date: date ?? DateTime(2026, 11, 2, 18),
        type: type,
        durationMin: durationMin,
        distanceKm: distanceKm,
        weightKg: weightKg,
        description: description,
        route: route,
      );

  test('create : calories calculées, trajet GPS conservé', () async {
    final route = ActivitiesController.demoRoute(DateTime(2026, 11, 2, 18));
    final a = await repo.create(draft(description: '  Parc  ', route: route));
    expect(a.calories, closeTo(63, 1e-9));
    expect(a.description, 'Parc');

    final read = await repo.getById(a.id!);
    expect(read.route, hasLength(route.length));
    expect(read.hasRoute, isTrue);
    expect(read.distanceKm, 3.2);
    expect(read.calories, closeTo(63, 1e-9));
    expect(read.speedKmh, closeTo(4.27, 0.01));
    expect(read.createdAt, clock.now);
  });

  test('le jeu n\'a pas de distance ; sans poids, pas de calories', () async {
    final play = await repo.create(
        draft(type: ActivityType.play, distanceKm: 2, weightKg: 4.5, durationMin: 20));
    expect(play.distanceKm, 0);
    expect(play.calories, closeTo(4.5 * 4.5 * 20 / 60, 1e-9));
    expect((await repo.create(draft(weightKg: null))).calories, 0);
  });

  test('règles métier : durée, distance, poids, date, description', () async {
    Future<void> rejects(Activity a, String message) => expectLater(
        repo.create(a),
        throwsA(isA<RecordException>()
            .having((e) => e.message, 'message', contains(message))));

    await rejects(draft(durationMin: 0), 'durée');
    await rejects(draft(durationMin: 24 * 60 + 1), '24 heures');
    await rejects(draft(distanceKm: -1), 'négative');
    await rejects(draft(distanceKm: 250), 'Distance trop élevée');
    await rejects(draft(weightKg: 0), 'poids');
    await rejects(draft(date: DateTime(2026, 11, 3, 15)), 'futur');
    await rejects(draft(description: 'x' * 501), 'description');
    expect(await repo.getAll(), isEmpty);
  });

  test('tri, filtre, modification, suppression', () async {
    final a = await repo.create(draft(date: DateTime(2026, 11, 1, 8)));
    final b = await repo.create(
        draft(petId: miaId, type: ActivityType.play, date: DateTime(2026, 11, 3, 9)));
    expect((await repo.getAll()).map((x) => x.id), [b.id, a.id]);
    expect((await repo.getAll(petId: rexId)).single.id, a.id);

    clock.now = DateTime(2026, 11, 3, 15);
    final updated = await repo.update(a.copyWith(durationMin: 60));
    expect(updated.calories, closeTo(84, 1e-9), reason: 'recalculées');
    expect(updated.createdAt, DateTime(2026, 11, 3, 14));

    await repo.delete(a.id!);
    await expectLater(repo.delete(a.id!), throwsA(isA<RecordException>()));
    await expectLater(repo.getById(a.id!), throwsA(isA<RecordException>()));
    expect(await repo.deleteByPet(miaId), 1);
    expect(await repo.getAll(), isEmpty);
  });
}
