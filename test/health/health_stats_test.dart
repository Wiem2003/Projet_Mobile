import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/health_stats.dart';

import '../reminders/test_helpers.dart';

void main() {
  // Mardi 3 novembre 2026.
  final now = DateTime(2026, 11, 3, 14);

  HealthRecord rec(DateTime date, HealthType type,
          {double cost = 0, double? kg, int pet = rexId, DateTime? next}) =>
      HealthRecord(
          petId: pet, type: type, date: date, cost: cost, weightKg: kg, nextDue: next);

  final records = [
    rec(DateTime(2026, 10, 20), HealthType.consultation, cost: 40, kg: 28.1),
    rec(DateTime(2026, 8, 3), HealthType.analysis, cost: 80, kg: 27.8),
    rec(DateTime(2026, 5, 1), HealthType.dental, cost: 120, kg: 27.4),
    rec(DateTime(2026, 3, 1), HealthType.consultation, cost: 45, kg: 27),
    rec(DateTime(2025, 6, 1), HealthType.vaccination, cost: 60, kg: 26),
  ];

  test('consultations, dépenses médicales, poids moyen et évolution', () {
    final s = HealthStats.compute(records, now: now); // 12 mois.
    expect(s.recordCount, 4);
    expect(s.consultations, 2);
    expect(s.spending, 285);
    expect(s.spendingByType[HealthType.dental], 120);
    expect(s.weights.map((w) => w.kg), [27, 27.4, 27.8, 28.1]);
    expect(s.averageWeight, closeTo(27.575, 1e-9));
    expect(s.weightChangeKg, closeTo(1.1, 1e-9));
    expect(s.weightChangeRatio, closeTo(1.1 / 27, 1e-9));
  });

  test('périodes', () {
    final q = HealthStats.compute(records, now: now, period: HealthPeriod.quarter);
    expect((q.recordCount, q.spending), (2, 120));
    expect(q.weightChangeKg, closeTo(0.3, 1e-9));
    final all = HealthStats.compute(records, now: now, period: HealthPeriod.all);
    expect((all.recordCount, all.spending, all.weights.first.kg), (5, 345, 26));
    final one = HealthStats.compute(records.take(1), now: now);
    expect(one.weightChangeKg, isNull, reason: 'une seule pesée');
    expect(HealthStats.compute(const [], now: now).averageWeight, isNull);
  });

  test('plusieurs animaux : le poids n\'est pas mélangé', () {
    final model = HealthModel(clock: () => now)
      ..setPets(DemoPetDirectory.pets)
      ..setRecords([
        ...records,
        rec(DateTime(2026, 9, 1), HealthType.vaccination,
            pet: miaId, kg: 4.2, cost: 55, next: DateTime(2027, 9, 1)),
        rec(DateTime(2026, 10, 1), HealthType.treatment,
            pet: miaId, next: DateTime(2026, 11, 1)), // Échéance passée.
      ]);
    expect(model.weightPetId, isNull);
    expect(model.stats.weights, isEmpty);
    expect(model.stats.spending, 340);
    expect(model.upcoming.single.nextDue, DateTime(2027, 9, 1));

    model.setPetFilter(miaId);
    expect(model.stats.weights.single.kg, 4.2);
    expect(model.history, hasLength(2));

    // Le filtre de type ne cache pas les pesées.
    model
      ..setPetFilter(rexId)
      ..setTypeFilter(HealthType.consultation);
    expect(model.stats.consultations, 2);
    expect(model.stats.recordCount, 2);
    expect(model.stats.weights, hasLength(4));
    expect(model.lastWeighing(rexId)!.weightKg, 28.1);
  });

  test('règles métier', () {
    String? check(HealthRecord r) => HealthRecord.validate(r, now);
    expect(check(rec(DateTime(2026, 11, 3), HealthType.other)), isNull);
    expect(check(rec(DateTime(2026, 11, 4), HealthType.other)), contains('futur'));
    expect(check(rec(DateTime(2026, 11, 1), HealthType.vaccination,
            next: DateTime(2026, 11, 1))),
        contains('postérieure'));
    expect(check(rec(DateTime(2026, 11, 1), HealthType.other, cost: -1)),
        contains('négatif'));
    expect(check(rec(DateTime(2026, 11, 1), HealthType.other, kg: 0)),
        contains('poids'));
  });
}
