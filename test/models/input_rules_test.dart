import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_form_model.dart';
import 'package:smart_pet/models/feeding_form_model.dart';
import 'package:smart_pet/models/health_form_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pet_form_model.dart';
import 'package:smart_pet/models/reminder_form_model.dart';
import 'package:smart_pet/models/validation.dart';
import 'package:smart_pet/views/widgets/input_formatters.dart';

/// Contrôles de saisie : règles partagées, règles de chaque formulaire et
/// filtres de frappe.
void main() {
  final now = DateTime(2026, 11, 4, 14);
  DateTime clock() => now;

  /// Animaux avec poids et date de naissance (contrôles contextuels).
  final pets = [
    PetSummary(id: 1, name: 'Rex', species: 'Chien', weightKg: 28,
        birthDate: DateTime(2023, 9, 12)),
    PetSummary(id: 2, name: 'Mia', species: 'Chat', weightKg: 4.5,
        birthDate: DateTime(2024, 6, 1)),
  ];

  group('règles partagées (InputRules)', () {
    test('noms : obligatoire, longueur, lettres, caractères autorisés', () {
      String? name(String v) => InputRules.name(v, 'Le nom', required: true);
      expect(name('  '), 'Le nom est obligatoire');
      expect(name('Rex'), isNull);
      expect(name("Hô-Chi d'Or Jr."), isNull, reason: 'accents, tiret, apostrophe, point');
      expect(name('R2D2'), isNull);
      expect(name('1234'), contains('au moins une lettre'));
      expect(name('Rex!!'), contains('lettres, chiffres, espaces'));
      expect(name('x' * 41), contains('40 caractères'));
      expect(InputRules.name('', 'La race'), isNull, reason: 'facultatif');
    });

    test('textes libres : longueur, caractères interdits, contenu', () {
      String? text(String v) => InputRules.text(v, 'La description', max: 20);
      expect(text(''), isNull);
      expect(text('Otite, 2×/jour'), isNull);
      expect(text('<script>'), contains('non autorisés'));
      expect(text('...!!!'), contains('lettres ou des chiffres'));
      expect(text('x' * 21), contains('20 caractères'));
      expect(InputRules.text(' ', 'Le titre', required: true), 'Le titre est obligatoire');
    });

    test('numéro d\'identification : puce 15 chiffres ou tatouage', () {
      String? id(String v) => InputRules.identification(v);
      expect(id(''), isNull);
      expect(id('250 2698 1234 5678'), isNull, reason: 'puce avec espaces');
      expect(id('2ABC123'), isNull, reason: 'tatouage');
      expect(id('abc1'), isNull, reason: 'minuscules acceptées');
      expect(id('25026981234'), 'Une puce électronique compte 15 chiffres (11 saisis)');
      expect(id('AB'), contains('Numéro invalide'));
      expect(id('AB-123'), contains('Numéro invalide'));
    });

    test('date antérieure à la naissance', () {
      final birth = DateTime(2024, 6, 1);
      expect(InputRules.notBeforeBirth(DateTime(2024, 6, 1, 8), birth, 'Mia'), isNull);
      expect(InputRules.notBeforeBirth(DateTime(2024, 5, 31), birth, 'Mia'),
          'La date est antérieure à la naissance de Mia (01/06/2024).');
      expect(InputRules.notBeforeBirth(DateTime(2000), null, 'Mia'), isNull);
    });

    test('poids plausible selon l\'espèce', () {
      expect(Species.cat.weightError(4.5), isNull);
      expect(Species.cat.weightError(300), contains('peu plausible pour un chat'));
      expect(Species.bird.weightError(0.04), isNull);
      expect(Species.horse.weightError(5), isNotNull);
      expect(Species.fromLabel('Chien'), Species.dog);
      expect(Species.fromLabel('Dragon'), isNull);
    });
  });

  group('formulaire Animal', () {
    test('poids selon l\'espèce, numéro, date de naissance', () {
      final form = PetFormModel(clock: clock)..name = 'Mia';
      form.species = Species.cat;
      expect(form.weightError('300'), contains('chat'));
      expect(form.weightError('4,5'), isNull);
      expect(form.weightError('abc'), 'Poids invalide');
      form.birthDate = DateTime(2027, 1, 1);
      expect(form.birthDateError, contains('futur'));
      form.birthDate = DateTime(1949, 1, 1);
      expect(form.birthDateError, 'Date de naissance invalide');
      form
        ..birthDate = DateTime(2024, 6, 1)
        ..identification = '12345';
      expect(form.validate(), contains('15 chiffres'));
      form.identification = '';
      expect(form.validate(), isNull);
    });

    test('l\'entité refuse aussi un poids ou un numéro impossible', () {
      expect(Pet.validate(Pet(name: 'Mia', species: Species.cat, weightKg: 300), now),
          contains('peu plausible'));
      expect(Pet.validate(Pet(name: 'Mia', species: Species.cat, identification: '12'), now),
          contains('15 chiffres'));
      expect(Pet.validate(Pet(name: '***', species: Species.cat), now),
          contains('au moins une lettre'));
    });
  });

  group('formulaire Repas', () {
    FeedingFormModel form({int pet = 2}) =>
        FeedingFormModel(clock: clock, pets: pets, defaultPetId: pet);

    test('quantité plausible pour l\'animal (30 % de son poids par jour)', () {
      final mia = form();
      expect(mia.maxDailyQuantityG, 1350);
      expect(mia.quantityError('1200'), isNull);
      expect(mia.quantityError('5000'),
          'Quantité peu plausible pour Mia : 1350 g maximum par jour');
      expect(mia.quantityError(''), 'Indiquez la quantité en grammes');
    });

    test('prix, marque et date avant la naissance', () {
      final mia = form()
        ..quantity = '100'
        ..price = '20000';
      expect(mia.validate(), 'Prix trop élevé (10 000 DT maximum)');
      mia
        ..price = '2'
        ..brand = '<<>>';
      expect(mia.validate(), contains('non autorisés'));
      mia
        ..brand = 'Felix'
        ..day = DateTime(2024, 1, 1);
      expect(mia.validate(), contains('antérieure à la naissance de Mia'));
      mia.day = DateTime(2026, 11, 3);
      expect(mia.validate(), isNull);
    });
  });

  group('formulaire Activité', () {
    ActivityFormModel form() =>
        ActivityFormModel(clock: clock, pets: pets, defaultPetId: 1)
          ..duration = '30';

    test('vitesse plausible selon le type', () {
      final f = form()..distance = '3';
      expect(f.speedError, isNull, reason: '6 km/h');
      f.distance = '20';
      expect(f.speedError, contains('40 km/h'));
      expect(f.validate(), contains('Vitesse peu plausible'));
      f.type = ActivityType.run;
      expect(f.speedError, isNull, reason: 'une course à 40 km/h est possible');
      f.type = ActivityType.play;
      expect(f.validate(), isNot(contains('Vitesse')), reason: 'pas de distance');
    });

    test('poids selon l\'espèce, date future ou avant la naissance', () {
      final f = form();
      expect(f.weightError('300'), contains('chien'));
      f.hour = 18; // Aujourd'hui à 18 h, il est 14 h.
      expect(f.dateError, 'L\'activité ne peut pas être dans le futur');
      f
        ..day = DateTime(2023, 1, 1)
        ..hour = 9;
      expect(f.dateError, contains('naissance de Rex'));
      f.description = '{}';
      f.day = DateTime(2026, 11, 3);
      expect(f.validate(), contains('non autorisés'));
    });
  });

  group('formulaire Santé', () {
    HealthFormModel form() =>
        HealthFormModel(clock: clock, pets: pets, defaultPetId: 2);

    test('vaccin et traitement : médicament obligatoire', () {
      final f = form()..type = HealthType.vaccination;
      expect(f.medicationError(''), 'Indiquez le nom du vaccin');
      expect(f.validate(), 'Indiquez le nom du vaccin');
      f.type = HealthType.treatment;
      expect(f.medicationError(' '), 'Indiquez le médicament');
      f.type = HealthType.consultation;
      expect(f.medicationError(''), isNull);
      expect(f.validate(), isNull);
    });

    test('échéance, coût, poids, date avant la naissance', () {
      final f = form()..day = DateTime(2026, 10, 1);
      f.nextDue = DateTime(2040, 1, 1);
      expect(f.nextDueError, 'Échéance trop lointaine (10 ans maximum)');
      f.nextDue = DateTime(2026, 9, 1);
      expect(f.nextDueError, contains('postérieure'));
      f.nextDue = DateTime(2027, 10, 1);
      expect(f.nextDueError, isNull);
      expect(HealthFormModel.validateCost('200000'), contains('100 000 DT'));
      expect(f.weightError('40'), contains('chat'));
      expect(f.weightError(''), isNull, reason: 'facultatif');
      f.day = DateTime(2024, 1, 1);
      expect(f.dateError, contains('naissance de Mia'));
    });
  });

  test('formulaire Rappel : titre avec du texte, notes limitées', () {
    expect(ReminderFormModel.validateTitle('!!!'), contains('lettres ou des chiffres'));
    expect(ReminderFormModel.validateTitle('Vermifuge'), isNull);
    expect(ReminderFormModel.validateNotes('x' * 501), contains('500 caractères'));
  });

  group('filtres de frappe', () {
    TextEditingValue type(TextInputFormatter f, String before, String after) =>
        f.formatEditUpdate(TextEditingValue(text: before),
            TextEditingValue(
                text: after, selection: TextSelection.collapsed(offset: after.length)));

    test('nombre décimal : chiffres, une virgule, décimales limitées', () {
      final f = DecimalInputFormatter(decimals: 2, maxDigits: 3);
      expect(type(f, '12', '12.5').text, '12,5', reason: 'point remplacé');
      expect(type(f, '12', '12a').text, '12', reason: 'lettre refusée');
      expect(type(f, '1,5', '1,5,').text, '1,5', reason: 'une seule virgule');
      expect(type(f, '1,25', '1,255').text, '1,25', reason: '2 décimales');
      expect(type(f, '999', '9999').text, '999', reason: '3 chiffres');
      expect(type(f, '-', '-').text, '-', reason: 'signe refusé : ancien texte gardé');
      expect(type(f, '', '').text, '');
    });

    test('entier et numéro d\'identification', () {
      final digits = integerInput(maxDigits: 3);
      var v = const TextEditingValue(text: '12a3');
      for (final f in digits) {
        v = f.formatEditUpdate(TextEditingValue.empty, v);
      }
      expect(v.text, '123');
      final id = IdentificationInputFormatter();
      expect(type(id, '', '2abc').text, '2ABC');
      expect(type(id, '2AB', '2AB-').text, '2AB');
    });
  });
}
