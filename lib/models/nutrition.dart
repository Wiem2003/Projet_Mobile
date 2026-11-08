import 'dart:math' as math;

import '../core/pets/pet_directory.dart';
import 'activity.dart';
import 'activity_guidelines.dart';
import 'feeding_record.dart';
import 'pet.dart';
import 'validation.dart';

/// Ration conseillée d'un animal (indicative, à confirmer avec le
/// vétérinaire).
class RationAdvice {
  const RationAdvice({
    required this.restingKcal,
    required this.factor,
    required this.factorLabel,
    required this.foodType,
    required this.kcalPer100g,
    required this.kcalEstimated,
    this.actualGramsPerDay,
    this.actualKcalPerDay,
  });

  /// Besoin au repos : 70 × poids^0,75.
  final double restingKcal;

  /// Facteur selon l'espèce, l'âge, la stérilisation et l'activité.
  final double factor;
  final String factorLabel;

  /// Aliment principal (le plus donné sur 14 jours, hors friandises).
  final FoodType foodType;
  final double kcalPer100g;

  /// Calories typiques du type d'aliment (emballage non saisi).
  final bool kcalEstimated;

  /// Moyenne réelle par jour de repas saisi (14 derniers jours).
  final double? actualGramsPerDay;
  final double? actualKcalPerDay;

  double get dailyKcal => restingKcal * factor;
  double get recommendedGrams => dailyKcal / kcalPer100g * 100;

  /// Écart entre la quantité donnée et la ration (0,27 = +27 %).
  double? get gap =>
      actualGramsPerDay == null ? null : actualGramsPerDay! / recommendedGrams - 1;
}

/// Part des calories apportées par les friandises.
class TreatsCheck {
  const TreatsCheck({required this.treatKcal, required this.totalKcal});

  final double treatKcal;
  final double totalKcal;

  double get share => totalKcal == 0 ? 0 : treatKcal / totalKcal;
  bool get tooMuch => share > Nutrition.maxTreatsShare;
}

/// Baisse d'appétit : moyenne des 7 derniers jours par rapport aux 30
/// précédents.
class AppetiteDrop {
  const AppetiteDrop({required this.recentPerDay, required this.previousPerDay});

  final double recentPerDay;
  final double previousPerDay;

  /// Variation (−0,30 = 30 % de moins).
  double get change => recentPerDay / previousPerDay - 1;
}

/// Nombre de repas conseillé par jour.
class MealAdvice {
  const MealAdvice({required this.min, required this.max, required this.stage});

  final int min;
  final int max;

  /// « chaton de 4 mois », « adulte », « senior ».
  final String stage;

  bool accepts(int meals) => meals >= min && meals <= max;
  String get range => min == max ? '$min repas' : '$min à $max repas';
}

/// Règles nutritionnelles du module Alimentation. Fonctions pures.
abstract final class Nutrition {
  /// Les friandises ne doivent pas dépasser 10 % des calories.
  static const maxTreatsShare = 0.10;

  /// Baisse d'appétit à partir de 25 % de moins.
  static const appetiteDrop = 0.25;

  /// Bonus de facteur quand l'objectif d'activité de la semaine est atteint.
  static const activeBonus = 0.2;

  /// Objectif d'activité par semaine (minutes), comme l'indice Smart Pet.
  static int? weeklyGoalMinutes(Species s, double? kg) =>
      ActivityGuidelines.weeklyGoalMinutes(s, kg);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Âge en mois révolus.
  static int? ageMonths(DateTime? birth, DateTime now) {
    if (birth == null) return null;
    var m = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) m--;
    return m < 0 ? 0 : m;
  }

  /// Calories d'un repas : celles de l'emballage, sinon la valeur typique.
  static double kcalOf(FeedingRecord r) =>
      r.quantityG * (r.kcalPer100g ?? r.foodType.typicalKcalPer100g) / 100;

  /// Besoin au repos : 70 × poids^0,75 (kcal par jour).
  static double restingKcal(double kg) => 70 * math.pow(kg, 0.75).toDouble();

  /// Facteur et son explication. `null` pour une espèce sans référence.
  static (double, String)? factor(Species s,
      {required int? ageMonths, required bool sterilized, required bool active}) {
    (double, String)? base;
    final age = ageMonths;
    switch (s) {
      case Species.dog:
        base = age != null && age < 4
            ? (3.0, 'chiot de moins de 4 mois')
            : age != null && age < 12
                ? (2.0, 'chiot de 4 à 12 mois')
                : age != null && age >= 84
                    ? (1.4, 'chien senior')
                    : sterilized
                        ? (1.4, 'chien adulte stérilisé')
                        : (1.6, 'chien adulte');
      case Species.cat:
        base = age != null && age < 12
            ? (2.5, 'chaton')
            : age != null && age >= 120
                ? (1.1, 'chat senior')
                : sterilized
                    ? (1.0, 'chat adulte stérilisé')
                    : (1.2, 'chat adulte');
      default:
        return null;
    }
    if (!active) return base;
    return (base.$1 + activeBonus, '${base.$2}, actif cette semaine');
  }

  static List<FeedingRecord> _since(int petId, Iterable<FeedingRecord> feeding, DateTime from,
          DateTime to) =>
      [
        for (final f in feeding)
          if (f.petId == petId && !f.date.isBefore(from) && !f.date.isAfter(to)) f,
      ];

  /// Ration conseillée, `null` sans poids ou pour une espèce sans référence.
  /// Pendant un programme de perte de poids, le besoin est calculé sur le
  /// poids cible ([targetKg]) et non sur le poids actuel.
  static RationAdvice? ration({
    required PetSummary pet,
    required Iterable<FeedingRecord> feeding,
    required Iterable<Activity> activities,
    required DateTime now,
    double? targetKg,
  }) {
    final kg = targetKg ?? pet.weightKg;
    final species = Species.fromLabel(pet.species);
    if (kg == null || kg <= 0 || species == null) return null;

    final today = _day(now);
    final weekAgo = today.subtract(const Duration(days: 6));
    final minutes = activities
        .where((a) => a.petId == pet.id && !a.date.isBefore(weekAgo) && !a.date.isAfter(now))
        .fold(0, (s, a) => s + a.durationMin);
    final goal = weeklyGoalMinutes(species, kg);
    final f = factor(species,
        ageMonths: ageMonths(pet.birthDate, now),
        sterilized: pet.sterilized,
        active: goal != null && minutes >= goal);
    if (f == null) return null;

    // Aliment principal et consommation réelle sur 14 jours.
    final recent = _since(pet.id, feeding, today.subtract(const Duration(days: 13)), today);
    final meals = [for (final r in recent) if (r.foodType != FoodType.treats) r];
    final grams = <FoodType, double>{};
    for (final r in meals) {
      grams[r.foodType] = (grams[r.foodType] ?? 0) + r.quantityG;
    }
    final main = grams.isEmpty
        ? FoodType.kibble
        : grams.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final withKcal = [
      for (final r in meals)
        if (r.foodType == main && r.kcalPer100g != null) r,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final kcal100 = withKcal.isEmpty ? main.typicalKcalPer100g : withKcal.first.kcalPer100g!;
    final days = {for (final r in recent) _day(r.date)}.length;

    return RationAdvice(
      restingKcal: restingKcal(kg),
      factor: f.$1,
      factorLabel: targetKg == null
          ? f.$2
          : '${f.$2}, calculé sur le poids cible de ${decimal(targetKg)} kg',
      foodType: main,
      kcalPer100g: kcal100,
      kcalEstimated: withKcal.isEmpty,
      actualGramsPerDay:
          days == 0 ? null : meals.where((r) => r.foodType == main).fold(0.0, (s, r) => s + r.quantityG) / days,
      actualKcalPerDay: days == 0 ? null : recent.fold(0.0, (s, r) => s + kcalOf(r)) / days,
    );
  }

  /// « Rex mange 454 g par jour, la ration conseillée est de 358 g (+27 %) ».
  static String rationSentence(String name, RationAdvice a) {
    final rec = '${a.recommendedGrams.round()} g';
    final gap = a.gap;
    if (a.actualGramsPerDay == null) {
      return 'Ration conseillée pour $name : $rec de ${a.foodType.label.toLowerCase()} par jour.';
    }
    final pct = (gap! * 100).round();
    final sign = pct > 0 ? '+$pct' : (pct < 0 ? '−${-pct}' : '0');
    return '$name mange ${a.actualGramsPerDay!.round()} g par jour, la ration conseillée '
        'est de $rec ($sign %).';
  }

  /// Friandises sur les 7 derniers jours, `null` sans repas.
  static TreatsCheck? treats(int petId, Iterable<FeedingRecord> feeding, DateTime now) {
    final today = _day(now);
    final recent = _since(petId, feeding, today.subtract(const Duration(days: 6)), today);
    if (recent.isEmpty) return null;
    final total = recent.fold(0.0, (s, r) => s + kcalOf(r));
    final treat =
        recent.where((r) => r.foodType == FoodType.treats).fold(0.0, (s, r) => s + kcalOf(r));
    return TreatsCheck(treatKcal: treat, totalKcal: total);
  }

  /// Baisse d'appétit (grammes par jour de repas saisi), `null` sinon. Il
  /// faut au moins 3 jours saisis cette semaine et 7 les 30 jours d'avant :
  /// un oubli de saisie n'est pas une baisse d'appétit.
  static AppetiteDrop? appetite(int petId, Iterable<FeedingRecord> feeding, DateTime now) {
    final today = _day(now);
    final weekStart = today.subtract(const Duration(days: 6));
    final recent = _since(petId, feeding, weekStart, today);
    final before = _since(petId, feeding, weekStart.subtract(const Duration(days: 30)),
        weekStart.subtract(const Duration(days: 1)));
    double perDay(List<FeedingRecord> list) =>
        list.fold(0.0, (s, r) => s + r.quantityG) / {for (final r in list) _day(r.date)}.length;
    final recentDays = {for (final r in recent) _day(r.date)}.length;
    final beforeDays = {for (final r in before) _day(r.date)}.length;
    if (recentDays < 3 || beforeDays < 7) return null;
    final drop = AppetiteDrop(recentPerDay: perDay(recent), previousPerDay: perDay(before));
    return drop.change <= -appetiteDrop ? drop : null;
  }

  /// « Mia mange 30 % de moins depuis une semaine : surveillez son état ou
  /// consultez. »
  static String appetiteSentence(String name, AppetiteDrop d) =>
      '$name mange ${(-d.change * 100).round()} % de moins depuis une semaine '
      '(${d.recentPerDay.round()} g par jour au lieu de ${d.previousPerDay.round()} g) : '
      'surveillez son état ou consultez.';

  /// Repas conseillés par jour (chiens et chats). Moins de 6 mois : 3 à 4 ;
  /// adulte : 2 ; senior (chien 7 ans, chat 10 ans) : 2 à 3.
  static MealAdvice? meals(Species? s, int? ageMonths) {
    if (ageMonths == null || (s != Species.dog && s != Species.cat)) return null;
    final young = s == Species.dog ? 'chiot' : 'chaton';
    if (ageMonths < 6) return MealAdvice(min: 3, max: 4, stage: '$young de $ageMonths mois');
    final seniorFrom = s == Species.dog ? 84 : 120;
    if (ageMonths >= seniorFrom) {
      return const MealAdvice(min: 2, max: 3, stage: 'senior, en plus petits repas');
    }
    return const MealAdvice(min: 2, max: 2, stage: 'adulte');
  }

  /// Avertissement du formulaire si le nombre de repas s'écarte du conseil.
  static String? mealsWarning(PetSummary? pet, int meals, DateTime now) {
    if (pet == null) return null;
    final advice = Nutrition.meals(Species.fromLabel(pet.species), ageMonths(pet.birthDate, now));
    if (advice == null || advice.accepts(meals)) return null;
    return 'Conseil pour ${pet.name} (${advice.stage}) : ${advice.range} par jour.';
  }

  /// « 18 % ».
  static String percent(double share) => '${(share * 100).round()} %';

  /// « 1 360 kcal ».
  static String kcal(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b kcal';
  }

  static String decimal(double v) => formatDecimal(v, decimals: 1);
}
