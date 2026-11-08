import 'dart:math' as math;

import 'feeding_plan.dart';
import 'feeding_record.dart';
import 'health_record.dart';
import 'pet.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// État d'un sac : reste, consommation et date à laquelle il sera vide.
class StockStatus {
  const StockStatus({
    required this.bag,
    required this.consumedG,
    required this.dailyG,
    required this.today,
  });

  final FoodBag bag;

  /// Grammes pris dans le sac depuis l'ouverture.
  final double consumedG;

  /// Consommation moyenne par jour saisi (14 derniers jours), `null` sans
  /// repas récent.
  final double? dailyG;
  final DateTime today;

  double get remainingG => math.max(0, bag.weightG - consumedG);
  double get remainingShare => remainingG / bag.weightG;
  bool get empty => remainingG <= 0;

  /// Jours restants, `null` si la consommation est inconnue.
  double? get daysLeft => empty ? 0 : (dailyG == null || dailyG! <= 0 ? null : remainingG / dailyG!);

  /// Jour où le sac sera vide.
  DateTime? get emptyOn {
    final d = daysLeft;
    return d == null ? null : today.add(Duration(days: d.floor()));
  }

  /// Jour du rappel « Racheter » : 3 jours avant, pas avant aujourd'hui.
  DateTime? get restockOn {
    final e = emptyOn;
    if (e == null) return null;
    final r = e.subtract(const Duration(days: FeedingInsights.restockDaysBefore));
    return r.isBefore(today) ? today : r;
  }

  /// À signaler : vide ou vide dans 7 jours au plus.
  bool get low => empty || (daysLeft != null && daysLeft! <= FeedingInsights.lowStockDays);
}

enum DietPace {
  onTrack('Dans les temps'),
  behind('En retard sur la courbe'),
  ahead('En avance sur la courbe'),
  reached('Objectif atteint');

  const DietPace(this.label);
  final String label;
}

/// Pesée du programme (date, kg).
typedef DietWeight = ({DateTime date, double kg});

/// Suivi d'un programme de perte de poids.
class DietProgress {
  const DietProgress({
    required this.plan,
    required this.weights,
    required this.weeklyLoss,
    required this.isCat,
  });

  final DietPlan plan;

  /// Pesées depuis le début, la première étant le poids de départ.
  final List<DietWeight> weights;

  /// Perte mesurée par semaine (0,015 = 1,5 %), `null` sans 2 pesées
  /// espacées d'au moins 7 jours.
  final double? weeklyLoss;
  final bool isCat;

  DietWeight get current => weights.last;
  double get lostKg => plan.startKg - current.kg;

  /// Part du chemin parcouru (0 à 1).
  double get progress =>
      ((plan.startKg - current.kg) / (plan.startKg - plan.targetKg)).clamp(0, 1).toDouble();

  double get plannedNow => plan.plannedKgAt(current.date);

  /// Perte plus rapide que 2 % par semaine.
  bool get tooFast => weeklyLoss != null && weeklyLoss! > DietPlan.maxRate + 1e-9;

  DietPace get pace {
    if (current.kg <= plan.targetKg) return DietPace.reached;
    final gap = current.kg / plannedNow - 1;
    if (gap > FeedingInsights.dietTolerance) return DietPace.behind;
    if (gap < -FeedingInsights.dietTolerance) return DietPace.ahead;
    return DietPace.onTrack;
  }
}

/// État du budget alimentaire d'un mois.
class BudgetStatus {
  const BudgetStatus({required this.spent, required this.projected, this.cap});

  final double spent;

  /// Dépense prévue à la fin du mois.
  final double projected;
  final double? cap;

  double get share => cap == null || cap == 0 ? 0 : spent / cap!;
  bool get exceeded => cap != null && spent > cap!;
  bool get willExceed => cap != null && !exceeded && projected > cap!;
}

/// Règles métier : stock des sacs, perte de poids, budget. Fonctions pures.
abstract final class FeedingInsights {
  /// Sac signalé quand il sera vide dans 7 jours au plus.
  static const lowStockDays = 7;

  /// Rappel « Racheter » 3 jours avant que le sac soit vide.
  static const restockDaysBefore = 3;

  /// Fenêtre de la consommation moyenne.
  static const stockWindowDays = 14;

  /// Écart toléré avec la courbe prévue (1 %).
  static const dietTolerance = 0.01;

  static StockStatus stock(FoodBag bag, Iterable<FeedingRecord> feeding, DateTime now) {
    final today = _day(now);
    final from = today.subtract(const Duration(days: stockWindowDays - 1));
    var consumed = 0.0, recent = 0.0;
    final days = <DateTime>{};
    for (final r in feeding) {
      if (!bag.contains(r) || r.date.isAfter(today)) continue;
      consumed += r.quantityG;
      if (!r.date.isBefore(from)) {
        recent += r.quantityG;
        days.add(r.date);
      }
    }
    return StockStatus(
        bag: bag, consumedG: consumed, dailyG: days.isEmpty ? null : recent / days.length, today: today);
  }

  /// « Sac de Rex et Mia vide dans environ 5 jours ».
  static String stockSentence(StockStatus s, List<String> petNames) {
    final who = switch (petNames.length) {
      0 => '',
      1 => ' de ${petNames.first}',
      _ => ' de ${petNames.sublist(0, petNames.length - 1).join(', ')} et ${petNames.last}',
    };
    final d = s.daysLeft;
    if (s.empty) return 'Sac$who vide : pensez à en racheter.';
    if (d == null) return 'Sac$who : ajoutez des repas pour estimer quand il sera vide.';
    if (d < 1) return 'Sac$who vide d\'ici demain.';
    final n = d.round();
    return 'Sac$who vide dans environ $n jour${n > 1 ? 's' : ''}.';
  }

  static DietProgress diet(DietPlan plan, Species? species, Iterable<HealthRecord> health) {
    final measured = [
      for (final h in health)
        if (h.petId == plan.petId && h.weightKg != null && !_day(h.date).isBefore(plan.startDate))
          (date: _day(h.date), kg: h.weightKg!),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final weights = <DietWeight>[(date: plan.startDate, kg: plan.startKg), ...measured];

    // Perte par semaine : dernière pesée comparée à la plus récente
    // pesée d'au moins 7 jours avant.
    double? loss;
    final last = weights.last;
    for (final w in weights.reversed) {
      final days = last.date.difference(w.date).inDays;
      if (days >= 7) {
        loss = (w.kg - last.kg) / w.kg / (days / 7);
        break;
      }
    }
    return DietProgress(
        plan: plan, weights: weights, weeklyLoss: loss, isCat: species == Species.cat);
  }

  /// Message d'alerte, `null` si tout va bien.
  static String? dietWarning(String name, DietProgress p) {
    if (!p.tooFast) return null;
    final pct = (p.weeklyLoss! * 100).toStringAsFixed(1).replaceAll('.', ',');
    return p.isCat
        ? '$name perd $pct % par semaine : au-delà de 2 %, un chat risque une maladie '
            'grave du foie (lipidose). Augmentez un peu la ration et parlez-en au vétérinaire.'
        : '$name perd $pct % par semaine, plus que les 2 % conseillés : augmentez un peu la ration.';
  }

  /// Projection : dépense ÷ jours écoulés × jours du mois (mois en cours) ;
  /// la dépense réelle pour un mois terminé.
  static double projection(double spent, DateTime month, DateTime now) {
    final m = DateTime(month.year, month.month);
    if (m != DateTime(now.year, now.month)) return spent;
    final length = DateTime(m.year, m.month + 1, 0).day;
    return spent / now.day * length;
  }

  static BudgetStatus budget(
          {required double spent, required DateTime month, required DateTime now, double? cap}) =>
      BudgetStatus(spent: spent, projected: projection(spent, month, now), cap: cap);
}
