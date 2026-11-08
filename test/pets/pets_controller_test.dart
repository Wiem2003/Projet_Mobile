import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/pet_form_controller.dart';
import 'package:smart_pet/controllers/pets_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pet_repository.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqlitePetRepository repo;
  late PetsModel model;
  late PetsController controller;
  late FakePhotoStore photos;
  late int changes;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() async {
    db = memoryDatabase();
    repo = SqlitePetRepository(db, clock: clock.call);
    model = PetsModel(clock: clock.call);
    photos = FakePhotoStore();
    changes = 0;
    controller = PetsController(
      model: model,
      repository: repo,
      photos: photos,
      onPetsChanged: () async => changes++,
    );
    await controller.load();
  });
  tearDown(() async {
    model.dispose();
    await db.close();
  });

  test('exemples, recherche et lien avec les autres modules', () async {
    expect(model.isEmpty, isTrue);
    expect(await controller.seedDemo(), 3);
    expect(changes, 1, reason: 'les autres modules relisent les animaux');
    expect(model.all.map((p) => p.name), ['Coco', 'Mia', 'Rex']);
    expect(await controller.seedDemo(), 0);
    expect(changes, 1);

    controller.setQuery('perruche');
    expect(model.visible.single.name, 'Coco');
    controller.setQuery('2502698876');
    expect(model.visible.single.name, 'Mia');
    controller.setQuery('');
    expect(model.countBySpecies, {Species.dog: 1, Species.cat: 1, Species.bird: 1});

    final directory = await PetRepositoryDirectory(repo).getPets();
    expect(directory.map((p) => (p.name, p.weightKg)),
        [('Coco', 0.04), ('Mia', 4.5), ('Rex', 28)]);
  });

  test('pesée du module Santé : poids mis à jour une seule fois', () async {
    final rex = await controller.save(Pet(name: 'Rex', species: Species.dog, weightKg: 28));
    changes = 0;
    await controller.updateWeight(rex.id!, 28);
    expect(changes, 0, reason: 'poids inchangé');
    await controller.updateWeight(rex.id!, 28.6);
    expect(model.byId(rex.id)!.weightKg, 28.6);
    expect(changes, 1);
  });

  test('suppression : fiche et photo', () async {
    final rex = await controller.save(Pet(
        name: 'Rex', species: Species.dog, photoPath: '/data/pet_photos/rex.jpg'));
    await controller.delete(rex);
    expect(model.isEmpty, isTrue);
    expect(photos.deleted, ['/data/pet_photos/rex.jpg']);
  });

  test('formulaire : validation, photo, enregistrement', () async {
    final form = PetFormController(controller);
    expect(form.model.species, Species.dog);
    expect(await form.save(), isNull);
    expect(form.model.error, 'Le nom est obligatoire');

    form
      ..setName('Filou')
      ..setSpecies(Species.cat)
      ..setSex(PetSex.female)
      ..setBirthDate(DateTime(2025, 5, 1))
      ..setWeight('3,8')
      ..setIdentification('250 269 800 000 001');
    expect(form.model.ageLabel, '1 an et 6 mois');

    await form.pickPhoto(camera: false); // photo_1, remplacée ensuite.
    await form.pickPhoto(camera: true); // photo_2, gardée.
    expect(form.model.photoPath, '/data/pet_photos/photo_2.jpg');
    final saved = await form.save();
    expect((saved!.name, saved.weightKg, saved.identification),
        ('Filou', 3.8, '250269800000001'));
    expect(saved.photoPath, '/data/pet_photos/photo_2.jpg');
    expect(photos.deleted, ['/data/pet_photos/photo_1.jpg']);
    form.dispose();
    expect(photos.deleted, hasLength(1), reason: 'enregistrée : rien à nettoyer');

    // Modifier : retirer la photo supprime le fichier.
    final edit = PetFormController(controller, initial: saved)..removePhoto();
    await edit.save();
    expect(model.byId(saved.id)!.photoPath, isNull);
    expect(photos.deleted.last, '/data/pet_photos/photo_2.jpg');
    edit.dispose();
  });

  test('formulaire abandonné : les photos prises sont supprimées', () async {
    final form = PetFormController(controller)..setName('Tom');
    await form.pickPhoto(camera: true);
    photos.cancel = true;
    await form.pickPhoto(camera: true); // Annulé : la photo reste.
    expect(form.model.photoPath, '/data/pet_photos/photo_1.jpg');
    form.dispose();
    expect(photos.deleted, ['/data/pet_photos/photo_1.jpg']);
    expect(model.isEmpty, isTrue);
  });

  test('formulaire : doublon refusé par la base', () async {
    await controller.save(Pet(name: 'Rex', species: Species.dog));
    final form = PetFormController(controller)..setName('REX');
    expect(await form.save(), isNull);
    expect(form.model.error, 'Un animal nommé « REX » existe déjà.');
    form.dispose();
  });
}
