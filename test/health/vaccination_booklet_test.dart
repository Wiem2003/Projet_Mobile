import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/health_booklet_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/health_booklet_pdf.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/vaccination_booklet.dart';
import 'package:smart_pet/models/validation.dart';
import 'package:smart_pet/views/screens/pet_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../dashboard/dashboard_test.dart' show FakeSharer;
import '../reminders/test_helpers.dart';

/// Carnet de vaccination, voyage, carnet de santé PDF et allergies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final now = DateTime(2026, 11, 6, 14);
  final rex = Pet(id: 1, name: 'Rex', species: Species.dog, weightKg: 28,
      identification: '250269812345678', allergies: 'Amoxicilline');
  final mia = Pet(id: 2, name: 'Mia', species: Species.cat);

  HealthRecord shot(Pet pet, DateTime date, String name, {DateTime? nextDue}) => HealthRecord(
      petId: pet.id!, type: HealthType.vaccination, date: date, medication: name,
      nextDue: nextDue, cost: 60, vet: 'Dr Ben Ali');

  test('vaccins reconnus dans le nom saisi', () {
    expect(Vaccine.detect('CHPPi + rage'), {Vaccine.chppi, Vaccine.rabies});
    expect(Vaccine.detect('Typhus + Coryza'), {Vaccine.typhus, Vaccine.coryza});
    expect(Vaccine.detect('Leucose (FeLV)'), {Vaccine.leukemia});
    expect(Vaccine.detect('Rabisin'), {Vaccine.rabies});
    expect(Vaccine.detect('Hépatite + parvo'), {Vaccine.chppi}, reason: 'accents ignorés');
    expect(Vaccine.detect('Nobivac KC'), {Vaccine.other});
  });

  group('statut des vaccins', () {
    test('à jour, bientôt expiré, expiré ; l\'échéance saisie est prioritaire', () {
      final b = VaccinationBooklet.compute(rex, [
        shot(rex, DateTime(2025, 12, 3), 'CHPPi + rage'), // expire le 03/12/2026
        shot(rex, DateTime(2025, 10, 1), 'Leptospirose'), // expirée le 01/10/2026
      ], now);
      expect([for (final e in b.entries) (e.vaccine, e.status)], [
        (Vaccine.rabies, VaccineStatus.expiringSoon),
        (Vaccine.chppi, VaccineStatus.expiringSoon),
        (Vaccine.leptospirosis, VaccineStatus.expired),
      ]);
      expect(b.of(Vaccine.rabies)!.daysLeft, 27);
      expect((b.summary, b.worst), ('1 vaccin expiré', VaccineStatus.expired));

      // Rage valable 3 ans (échéance saisie au dossier).
      final rage3 = VaccinationBooklet.compute(rex, [
        shot(rex, DateTime(2025, 1, 10), 'Rage', nextDue: DateTime(2028, 1, 10)),
        shot(rex, DateTime(2026, 3, 1), 'CHPPi'),
      ], now);
      expect(rage3.summary, 'Vaccins à jour');
      expect(rage3.of(Vaccine.rabies)!.expiresOn, DateTime(2028, 1, 10));
    });

    test('carnet vide, vaccins conseillés manquants, autre animal ignoré', () {
      final b = VaccinationBooklet.compute(mia, [shot(rex, DateTime(2026, 5, 1), 'Rage')], now);
      expect(b.summary, 'Aucun vaccin enregistré');
      expect(b.missingCore, [Vaccine.typhus, Vaccine.coryza]);
      final soon = VaccinationBooklet.compute(mia, [shot(mia, DateTime(2025, 11, 20), 'Typhus + coryza')], now);
      expect(soon.summary, '2 vaccins bientôt expirés');
    });
  });

  group('voyage ou pension', () {
    TravelCheck check(List<HealthRecord> shots, DateTime departure) =>
        VaccinationBooklet.compute(rex, shots, now).checkTravel(departure, now);

    test('rage valide le jour du départ', () {
      final c = check([shot(rex, DateTime(2025, 12, 3), 'CHPPi + rage')], DateTime(2026, 11, 20));
      expect(c.ok, isTrue);
      expect(c.message, 'Rex peut voyager le 20/11 : rage valable jusqu\'au 03/12.');
    });

    test('rage expirée avant le départ, ou déjà expirée', () {
      expect(check([shot(rex, DateTime(2025, 12, 3), 'Rage')], DateTime(2026, 12, 15)).message,
          'Rex ne peut pas voyager le 15/12 : rage expire le 03/12, avant le départ.');
      expect(check([shot(rex, DateTime(2025, 10, 3), 'Rage')], DateTime(2026, 12, 15)).message,
          'Rex ne peut pas voyager le 15/12 : rage expirée le 03/10.');
    });

    test('première injection : 21 jours d\'attente, sauf rappel fait à temps', () {
      final primo = check([shot(rex, DateTime(2026, 11, 1), 'Rage')], DateTime(2026, 11, 15));
      expect(primo.ok, isFalse);
      expect(primo.message, contains('valable à partir du 22/11'));
      final booster = check([
        shot(rex, DateTime(2025, 11, 10), 'Rage'),
        shot(rex, DateTime(2026, 11, 2), 'Rage'),
      ], DateTime(2026, 11, 15));
      expect(booster.ok, isTrue, reason: 'rappel avant l\'expiration du précédent');
    });

    test('aucune rage, date passée, autres vaccins signalés', () {
      final none = check([shot(rex, DateTime(2026, 6, 1), 'CHPPi')], DateTime(2026, 12, 1));
      expect(none.message, 'Rex ne peut pas voyager le 01/12 : aucun vaccin contre la rage enregistré.');
      expect(check(const [], DateTime(2026, 11, 1)).message, 'La date de départ est déjà passée.');
      final warn = check([
        shot(rex, DateTime(2026, 6, 1), 'Rage'),
        shot(rex, DateTime(2025, 12, 1), 'CHPPi'),
      ], DateTime(2026, 12, 15));
      expect(warn.ok, isTrue);
      expect(warn.warnings, ['CHPPi expiré à cette date (souvent exigé par les pensions)']);
    });
  });

  group('carnet de santé PDF et allergies', () {
    final health = [
      shot(rex, DateTime(2025, 12, 3), 'CHPPi + rage'),
      HealthRecord(petId: 1, type: HealthType.treatment, date: DateTime(2026, 10, 1),
          medication: 'Milbemax', nextDue: DateTime(2027, 1, 1)),
      HealthRecord(petId: 1, type: HealthType.consultation, date: DateTime(2026, 8, 1), weightKg: 27),
      HealthRecord(petId: 1, type: HealthType.consultation, date: DateTime(2026, 10, 20), weightKg: 28.1),
    ];

    test('PDF : en-tête, police intégrée ; partage par le Controller', () async {
      final bytes = await HealthBookletPdf.build(
          pet: rex, booklet: VaccinationBooklet.compute(rex, health, now), health: health, now: now);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(String.fromCharCodes(bytes), contains('Roboto'));
      expect(HealthBookletPdf.fileName(Pet(name: 'Coco Bé', species: Species.bird)),
          'carnet_sante_coco_b_.pdf');

      final sharer = FakeSharer();
      await HealthBookletController(reportSharer: sharer, clock: () => now).shareBooklet(rex, health);
      expect((sharer.fileName, sharer.subject), ('carnet_sante_rex.pdf', 'Carnet de santé de Rex'));
      expect(String.fromCharCodes(sharer.bytes!.take(4)), '%PDF');
    });

    test('allergies : contrôle de saisie et enregistrement', () async {
      expect(Pet.validate(Pet(name: 'Rex', species: Species.dog, allergies: '<b>'), now),
          contains('non autorisés'));
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = SqlitePetRepository(db, clock: () => now);
      final saved = await repo.create(Pet(name: 'Rex', species: Species.dog, allergies: '  Poulet  '));
      expect((await repo.getById(saved.id!)).allergies, 'Poulet');
    });

    test('migration v4 → v7 : allergies, stérilisation, calories et photo de profil', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('smart_pet_v4_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'v4.db');
      final v4 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, _) async {
              await db.execute(
                  'CREATE TABLE pets (id INTEGER PRIMARY KEY, user_id INTEGER, name TEXT, '
                  'species TEXT, sex TEXT, created_at INTEGER, updated_at INTEGER)');
              await db.execute('CREATE TABLE feeding_records (id INTEGER PRIMARY KEY, pet_id INTEGER)');
              await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
            },
          ));
      await v4.insert('pets', {'name': 'Rex', 'species': 'dog', 'sex': 'male', 'created_at': 0, 'updated_at': 0});
      await v4.close();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);
      final raw = await db.database;
      expect(await raw.getVersion(), AppDatabase.version);
      final pet = (await SqlitePetRepository(db).getAll()).single;
      expect((pet.name, pet.allergies, pet.sterilized), ('Rex', null, false));
      final cols = [for (final c in await raw.rawQuery('PRAGMA table_info(feeding_records)')) c['name']];
      expect(cols, contains('kcal_per_100g'));
      final userCols = [for (final c in await raw.rawQuery('PRAGMA table_info(users)')) c['name']];
      expect(userCols, contains('photo_path'));
      expect(formatDecimal(1.5), '1,5');
    });
  });

  testWidgets('fiche de l\'animal : carnet, voyage et PDF', (tester) async {
    tester.view.physicalSize = const Size(412, 1800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pets = PetsModel(clock: () => now)..setPets([rex]);
    final health = HealthModel(clock: () => now)
      ..setRecords([
        shot(rex, DateTime(2025, 12, 3), 'CHPPi + rage'),
        shot(rex, DateTime(2025, 10, 1), 'Leptospirose'),
      ]);
    final sharer = FakeSharer();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: pets),
        ChangeNotifierProvider.value(value: health),
        Provider.value(value: HealthBookletController(reportSharer: sharer, clock: () => now)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const PetDetailScreen(petId: 1),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Amoxicilline'), findsOneWidget, reason: 'allergies');
    expect(find.text('Carnet de vaccination'), findsOneWidget);
    expect(find.text('1 vaccin expiré'), findsOneWidget);
    expect(find.text('J-27'), findsNWidgets(2), reason: 'rage et CHPPi');
    expect(find.text('Expiré'), findsOneWidget);

    // Départ proposé dans 7 jours (13/11) : rage encore valable.
    await tester.tap(find.text('Vérifier un voyage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Voyage possible'), findsOneWidget);
    expect(find.text('Rex peut voyager le 13/11 : rage valable jusqu\'au 03/12.'), findsOneWidget);
    expect(find.text('• Leptospirose expiré à cette date (souvent exigé par les pensions)'),
        findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Carnet de santé PDF'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(sharer.fileName, 'carnet_sante_rex.pdf');
  });
}
