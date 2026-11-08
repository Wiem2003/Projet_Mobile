import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/controllers/activity_form_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_stats.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqliteActivityRepository repo;
  late ActivitiesModel model;
  late ActivitiesController controller;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() async {
    db = memoryDatabase();
    repo = SqliteActivityRepository(db, clock: clock.call);
    model = ActivitiesModel(clock: clock.call);
    controller = ActivitiesController(
        model: model, repository: repo, pets: const DemoPetDirectory());
    await controller.load();
  });
  tearDown(() async {
    model.dispose();
    await db.close();
  });

  test('filtres : animal, type et période', () async {
    Future<void> add(int pet, ActivityType type, DateTime date) => repo.create(
        Activity(petId: pet, date: date, type: type, durationMin: 30, weightKg: 10));
    await add(rexId, ActivityType.walk, DateTime(2026, 11, 3, 8));
    await add(rexId, ActivityType.run, DateTime(2026, 10, 20));
    await add(miaId, ActivityType.play, DateTime(2026, 11, 1));
    await add(rexId, ActivityType.walk, DateTime(2026, 8, 1));
    await controller.load();

    expect(model.period, ActivityPeriod.month);
    expect(model.visible, hasLength(3));
    expect(model.stats.count, 3);

    controller.setPeriod(ActivityPeriod.week);
    expect(model.visible, hasLength(2));
    controller.setPetFilter(rexId);
    expect(model.visible.single.type, ActivityType.walk);
    controller
      ..setPeriod(ActivityPeriod.all)
      ..setTypeFilter(ActivityType.walk);
    expect(model.visible, hasLength(2));
    expect(model.stats.count, 2);
  });

  test('formulaire : poids de l\'animal, calories, enregistrement', () async {
    final form = ActivityFormController(controller);
    expect(form.model.petId, rexId);
    expect(form.model.type, ActivityType.walk);
    expect(form.model.weight, '28');
    expect(await form.save(), isNull);
    expect(form.model.error, 'Indiquez la durée en minutes');

    form.setDuration('45');
    expect(form.model.estimatedCalories, closeTo(63, 1e-9));

    // Le poids suit l'animal tant qu'il n'est pas saisi à la main.
    form.setPet(miaId);
    expect(form.model.weight, '4,5');
    form
      ..setWeight('5')
      ..setPet(rexId);
    expect(form.model.weight, '5');

    form
      ..setType(ActivityType.play)
      ..setDistance('3')
      ..setDescription('Balle');
    final saved = await form.save();
    expect(saved!.distanceKm, 0, reason: 'pas de distance pour le jeu');
    expect(saved.calories, closeTo(4.5 * 5 * 0.75, 1e-9));
    expect(model.all.single.description, 'Balle');
    form.dispose();

    final edit = ActivityFormController(controller, initial: saved);
    expect(edit.model.isEdit, isTrue);
    expect(edit.model.weight, '5');
    edit.setDuration('60');
    expect((await edit.save())!.durationMin, 60);
    expect(model.all, hasLength(1));
    edit.dispose();
  });

  test('formulaire prérempli par une promenade GPS', () async {
    final start = DateTime(2026, 11, 3, 9);
    final route = ActivitiesController.demoRoute(start);
    final form = ActivityFormController(controller,
        walk: (start: start, durationMin: 42, distanceKm: 3.14, route: route));
    expect(form.model.fromGps, isTrue);
    expect(form.model.duration, '42');
    expect(form.model.distance, '3,14');
    expect((form.model.day, form.model.hour), (DateTime(2026, 11, 3), 9));

    final saved = await form.save();
    expect(saved!.route, hasLength(route.length));
    expect(model.all.single.hasRoute, isTrue);
    form.dispose();
  });

  test('exemples : 6 semaines d\'activités, une promenade GPS, sans doublon',
      () async {
    final count = await controller.seedDemo();
    expect(count, greaterThan(40));
    expect(model.all.where((a) => a.hasRoute), hasLength(1));
    expect(model.stats.weeks.where((w) => w.distanceKm > 0), hasLength(6));
    expect(model.all.every((a) => a.calories > 0), isTrue);
    expect(await controller.seedDemo(), 0);
  });
}
