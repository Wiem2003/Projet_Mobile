import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_stats.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/health_stats.dart';
import 'package:smart_pet/models/notifications/reminder_notifier.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_exception.dart';
import 'package:smart_pet/models/validation.dart';

/// Tests unitaires des Models : état observé par les Views (chargement,
/// erreur, filtres, recherche) et petites règles partagées.
void main() {
  final now = DateTime(2026, 11, 4, 14);
  DateTime clock() => now;

  /// Compte les notifications envoyées aux Views.
  int listen(Object model) {
    var count = 0;
    (model as dynamic).addListener(() => count++);
    return count;
  }

  group('états chargement / erreur', () {
    test('chaque Model passe de « chargement » à « erreur »', () {
      final models = <dynamic>[
        PetsModel(clock: clock),
        HealthModel(clock: clock),
        FeedingModel(clock: clock),
        ActivitiesModel(clock: clock),
      ];
      for (final m in models) {
        var notified = 0;
        m.addListener(() => notified++);
        expect(m.loading, isTrue, reason: '${m.runtimeType}');
        expect(m.error, isNull);
        m.setError('base inaccessible');
        expect((m.loading, m.error, notified), (false, 'base inaccessible', 1),
            reason: '${m.runtimeType}');
      }
    });
  });

  group('PetsModel', () {
    test('recherche sur le nom, la race, l\'espèce, la couleur et la puce', () {
      final model = PetsModel(clock: clock)
        ..setPets([
          Pet(id: 1, name: 'Rex', species: Species.dog, breed: 'Berger', color: 'Fauve'),
          Pet(id: 2, name: 'Mia', species: Species.cat, identification: '250ABC'),
        ]);
      expect(model.loading, isFalse);
      String names(String q) {
        model.setQuery(q);
        return model.visible.map((p) => p.name).join(',');
      }

      expect(names(''), 'Rex,Mia');
      expect(names('  berger '), 'Rex');
      expect(names('CHAT'), 'Mia');
      expect(names('fauve'), 'Rex');
      expect(names('250abc'), 'Mia');
      expect(names('zèbre'), '');
      expect(model.query, 'zèbre');
      expect(model.byId(2)!.name, 'Mia');
      expect(model.byId(9), isNull);
    });
  });

  group('HealthModel', () {
    test('un filtre sur un animal supprimé est retiré', () {
      final model = HealthModel(clock: clock)
        ..setPets(DemoPetDirectory.pets)
        ..setPetFilter(2);
      model.setPets([DemoPetDirectory.pets.first]);
      expect(model.petFilter, isNull);
      expect(model.weightPetId, 1, reason: 'un seul animal : son poids est suivi');
    });

    test('filtres de type et de période, recherche par id', () {
      final model = HealthModel(clock: clock)
        ..setPets(DemoPetDirectory.pets)
        ..setRecords([
          HealthRecord(id: 1, petId: 1, type: HealthType.vaccination, date: DateTime(2026, 10, 1)),
          HealthRecord(id: 2, petId: 1, type: HealthType.dental, date: DateTime(2025, 1, 1)),
        ]);
      expect(model.history.map((r) => r.id), [1], reason: '12 mois par défaut');
      model.setPeriod(HealthPeriod.all);
      expect(model.history.map((r) => r.id), [1, 2]);
      model.setTypeFilter(HealthType.dental);
      expect(model.history.single.id, 2);
      expect(model.byId(1)!.type, HealthType.vaccination);
      expect(model.byId(5), isNull);
      expect(model.petOf(9), isNull);
    });
  });

  group('FeedingModel', () {
    test('mois affiché, mois courant et dernier repas par animal', () {
      final model = FeedingModel(clock: clock)
        ..setPets(DemoPetDirectory.pets)
        ..setRecords([
          FeedingRecord(id: 1, petId: 1, date: DateTime(2026, 11, 1), foodType: FoodType.kibble, quantityG: 300, price: 3),
          FeedingRecord(id: 2, petId: 1, date: DateTime(2026, 11, 3), foodType: FoodType.wet, quantityG: 100, price: 2),
        ]);
      expect(model.month, DateTime(2026, 11));
      expect(model.isCurrentMonth, isTrue);
      expect(model.lastFor(1)!.id, 2, reason: 'le plus récent');
      expect(model.lastFor(2), isNull);
      expect(model.byId(1)!.quantityG, 300);
      expect(model.petOf(1)!.name, 'Rex');
      model.setMonth(DateTime(2026, 10, 15));
      expect((model.month, model.isCurrentMonth), (DateTime(2026, 10), false));
      expect(model.history, isEmpty);
    });
  });

  group('ActivitiesModel', () {
    test('recherche par id et par animal', () {
      final model = ActivitiesModel(clock: clock)
        ..setPets(DemoPetDirectory.pets)
        ..setActivities([
          Activity(id: 7, petId: 2, date: DateTime(2026, 11, 3), type: ActivityType.play, durationMin: 15),
        ]);
      expect(model.byId(7)!.type, ActivityType.play);
      expect(model.byId(8), isNull);
      expect(model.petOf(2)!.name, 'Mia');
      expect(model.petOf(3), isNull);
      expect(model.period, ActivityPeriod.month);
    });
  });

  group('règles partagées', () {
    test('lecture et écriture des nombres saisis', () {
      expect(parseDecimal('1e400'), isNull, reason: 'infini refusé');
      expect(parseDecimal('NaN'), isNull);
      expect(parseDecimal('-2,5'), -2.5);
      expect(formatDecimal(12.0), '12');
      expect(formatDecimal(0.04), '0,04');
      expect(const RecordException('x').toString(), 'x');
      expect(const RecordException.notFound().message, 'Enregistrement introuvable.');
    });

    test('erreurs du module Rappels', () {
      const conflict = ReminderException.conflict();
      expect((conflict.isConflict, conflict.isNotFound), (true, false));
      const missing = ReminderException.notFound();
      expect((missing.isNotFound, missing.toString()), (true, 'Rappel introuvable.'));
      const invalid = ReminderException('Titre requis');
      expect((invalid.kind, invalid.isConflict), (ReminderErrorKind.validation, false));
    });

    test('animaux des exemples : chien et chat, sinon les premiers', () {
      const dog = PetSummary(id: 1, name: 'Rex', species: 'Chien');
      const cat = PetSummary(id: 2, name: 'Mia', species: 'Chat');
      const bird = PetSummary(id: 3, name: 'Coco', species: 'Oiseau');
      expect([bird, cat, dog].demoPair, (dog, cat));
      expect([bird, cat].demoPair, (bird, cat), reason: 'pas de chien');
      expect([dog].demoPair, (dog, dog), reason: 'un seul animal');
      expect([bird, dog].demoPair, (dog, bird), reason: 'pas de chat');
      expect(bird.initial, 'C');
      expect(const PetSummary(id: 4, name: '').initial, '?');
    });

    test('notifications désactivées (NoopReminderNotifier)', () async {
      const noop = NoopReminderNotifier();
      await noop.syncAll([
        Reminder(title: 'X', type: ReminderType.other, dueDate: now),
      ]);
      expect(await noop.requestPermissions(), isFalse);
      await noop.showTest();
      // Un emplacement de notification par délai d'alerte, sans collision.
      expect(notificationIdFor(3, AlertOffset.atTime), 48);
      expect(notificationIdFor(3, AlertOffset.oneMonth),
          isNot(notificationIdFor(4, AlertOffset.atTime)));
    });

    test('point GPS lisible', () {
      expect(const GeoPoint(36.8, 10.18).toString(), 'GeoPoint(36.8, 10.18)');
    });
  });

  test('aucune notification aux Views sans changement d\'état', () {
    final model = PetsModel(clock: clock);
    expect(listen(model), 0);
  });
}
