import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/controllers/activity_form_controller.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_repository.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

/// Base inaccessible : toute lecture échoue.
class _BrokenActivities implements ActivityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('base inaccessible'));
}

class _BrokenFeeding implements FeedingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('base inaccessible'));
}

/// Enregistrement refusé par la base.
class _Rejecting implements ActivityRepository {
  @override
  Future<List<Activity>> getAll({int? petId}) async => const [];

  @override
  Future<Activity> create(Activity activity) async =>
      throw const RecordException('Refusé par la base.');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final clock = FakeClock(DateTime(2026, 11, 4, 14));

  test('Activités et Repas : base inaccessible, message d\'erreur', () async {
    final activities = ActivitiesModel(clock: clock.call);
    await ActivitiesController(
            model: activities, repository: _BrokenActivities(), pets: const DemoPetDirectory())
        .load();
    expect(activities.loading, isFalse);
    expect(activities.error, contains('Impossible de charger les activités'));

    final feeding = FeedingModel(clock: clock.call);
    await FeedingController(
            model: feeding, repository: _BrokenFeeding(), pets: const DemoPetDirectory())
        .load();
    expect(feeding.error, contains('Impossible de charger les repas'));
  });

  test('formulaire : date et heure, erreur de la base affichée', () async {
    final controller = ActivitiesController(
        model: ActivitiesModel(clock: clock.call),
        repository: _Rejecting(),
        pets: const DemoPetDirectory());
    await controller.load();
    final form = ActivityFormController(controller)
      ..setDay(DateTime(2026, 11, 3, 23, 59))
      ..setTime(7, 45)
      ..setDuration('30');
    expect(form.model.date, DateTime(2026, 11, 3, 7, 45));
    expect(await form.save(), isNull);
    expect(form.model.error, 'Refusé par la base.');
    expect(form.model.saving, isFalse);

    // Une nouvelle saisie efface l'erreur affichée.
    form.setTime(8, 0);
    expect(form.model.error, isNull);
    form.dispose();
  });
}
