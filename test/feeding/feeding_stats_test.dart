import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/feeding_stats.dart';
import 'package:smart_pet/models/validation.dart';

void main() {
  // Mardi 3 novembre 2026, 14 h.
  final now = DateTime(2026, 11, 3, 14);

  FeedingRecord meal(DateTime day, double grams, double price,
          {FoodType type = FoodType.kibble, int pet = 1}) =>
      FeedingRecord(
          petId: pet, date: day, foodType: type, quantityG: grams, price: price);

  final records = [
    meal(DateTime(2026, 11, 1), 300, 3),
    meal(DateTime(2026, 11, 2), 300, 3),
    meal(DateTime(2026, 11, 3), 100, 2, type: FoodType.wet, pet: 2),
    meal(DateTime(2026, 10, 15), 400, 10),
    meal(DateTime(2026, 10, 20), 400, 6),
    meal(DateTime(2026, 5, 10), 999, 99), // Hors des 6 derniers mois.
  ];

  test('mois en cours : quantité, dépense et moyenne sur les jours écoulés', () {
    final s = FeedingStats.compute(records, month: DateTime(2026, 11), now: now);
    expect(s.recordCount, 3);
    expect(s.meals, 3);
    expect(s.quantityG, 700);
    expect(s.spending, 8);
    expect(s.days, 3);
    expect(s.dailyAverageG, closeTo(233.33, 0.01));
    expect(s.dailyAverageSpending, closeTo(2.67, 0.01));
    expect(s.quantityByType, {FoodType.kibble: 600, FoodType.wet: 100});
  });

  test('évolution des dépenses sur 6 mois', () {
    final s =
        FeedingStats.compute(records, month: DateTime(2026, 11, 20), now: now);
    expect(s.spendingByMonth.map((m) => m.month), [
      for (var m = 6; m <= 11; m++) DateTime(2026, m),
    ]);
    expect(s.spendingByMonth.map((m) => m.value), [0, 0, 0, 0, 16, 8]);
    expect(s.previousSpending, 16);
    expect(s.spendingChange, isNull, reason: 'rien du 1er au 3 octobre');
  });

  test('mois en cours comparé au même nombre de jours du mois précédent', () {
    final s = FeedingStats.compute([
      ...records,
      meal(DateTime(2026, 10, 2), 300, 4),
    ], month: DateTime(2026, 11), now: now);
    expect(s.comparedDays, 3);
    expect(s.previousSamePeriod, 4, reason: 'seulement du 1er au 3 octobre');
    expect(s.spendingChange, 1.0, reason: '8 DT contre 4 DT');
  });

  test('mois passé : comparé au mois précédent complet', () {
    final s = FeedingStats.compute([
      ...records,
      meal(DateTime(2026, 9, 28), 300, 32),
    ], month: DateTime(2026, 10), now: now);
    expect(s.comparedDays, isNull);
    expect(s.spendingChange, -0.5);
  });

  test('mois passé : moyenne sur tout le mois', () {
    final s = FeedingStats.compute(records, month: DateTime(2026, 10), now: now);
    expect(s.days, 31);
    expect(s.quantityG, 800);
    expect(s.dailyAverageG, closeTo(25.81, 0.01));
    expect(s.spendingChange, isNull, reason: 'aucune dépense en septembre');
  });

  test('mois futur : pas de division par zéro', () {
    final s = FeedingStats.compute(records, month: DateTime(2026, 12), now: now);
    expect(s.days, 0);
    expect(s.recordCount, 0);
    expect(s.dailyAverageG, 0);
    expect(s.spendingChange, -1);
  });

  test('saisie des nombres', () {
    expect(parseDecimal('12,5'), 12.5);
    expect(parseDecimal(' 1 250.75 '), 1250.75);
    expect(parseDecimal(''), isNull);
    expect(parseDecimal('abc'), isNull);
    expect(formatDecimal(350), '350');
    expect(formatDecimal(2.6), '2,6');
    expect(formatDecimal(1 / 3), '0,33');
  });
}
