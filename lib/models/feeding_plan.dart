import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'feeding_record.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _num(Object? v) => (v as num).toDouble();

/// Sac d'aliment ouvert (stock de croquettes, de pâtée…), partagé par un ou
/// plusieurs animaux.
class FoodBag {
  FoodBag({
    required this.id,
    required List<int> petIds,
    required this.foodType,
    required this.weightG,
    required this.price,
    required DateTime openedOn,
    String? brand,
  })  : petIds = List.unmodifiable({...petIds}.toList()..sort()),
        openedOn = _day(openedOn),
        brand = (brand ?? '').trim().isEmpty ? null : brand!.trim();

  static const maxWeightG = 50000.0;
  static const maxPrice = 10000.0;

  final int id;

  /// Animaux qui mangent ce sac (leurs repas sont additionnés).
  final List<int> petIds;
  final FoodType foodType;
  final String? brand;

  /// Poids du sac plein (g).
  final double weightG;
  final double price;

  /// Jour d'ouverture : seuls les repas saisis depuis ce jour vident le sac.
  final DateTime openedOn;

  String get label => brand == null ? foodType.label : '${foodType.label} ${brand!}';

  /// Message d'erreur, ou `null` si le sac est valide.
  static String? validate(FoodBag b, DateTime now) {
    if (b.petIds.isEmpty) return 'Choisissez au moins un animal.';
    if (b.weightG <= 0) return 'Le poids du sac doit être supérieur à 0.';
    if (b.weightG > maxWeightG) return 'Sac trop lourd (50 kg maximum).';
    if (b.price < 0) return 'Le prix ne peut pas être négatif.';
    if (b.price > maxPrice) return 'Prix trop élevé.';
    if ((b.brand ?? '').length > FeedingRecord.maxBrandLength) {
      return 'La marque ne doit pas dépasser ${FeedingRecord.maxBrandLength} caractères.';
    }
    if (b.openedOn.isAfter(_day(now))) {
      return 'La date d\'ouverture ne peut pas être dans le futur.';
    }
    return null;
  }

  /// Ce repas est pris dans ce sac : même animal, même type d'aliment,
  /// depuis l'ouverture et, si les deux marques sont connues, même marque.
  bool contains(FeedingRecord r) =>
      petIds.contains(r.petId) &&
      r.foodType == foodType &&
      !r.date.isBefore(openedOn) &&
      (brand == null ||
          (r.brand ?? '').trim().isEmpty ||
          r.brand!.trim().toLowerCase() == brand!.toLowerCase());

  FoodBag withPets(List<int> ids) => FoodBag(
      id: id,
      petIds: ids,
      foodType: foodType,
      weightG: weightG,
      price: price,
      openedOn: openedOn,
      brand: brand);

  Map<String, Object?> toJson() => {
        'id': id,
        'pets': petIds,
        'type': foodType.name,
        'brand': ?brand,
        'weight_g': weightG,
        'price': price,
        'opened': openedOn.millisecondsSinceEpoch,
      };

  factory FoodBag.fromJson(Map<String, Object?> j) => FoodBag(
        id: j['id'] as int,
        petIds: [for (final p in j['pets'] as List) p as int],
        foodType: FoodType.parse(j['type'] as String?),
        brand: j['brand'] as String?,
        weightG: _num(j['weight_g']),
        price: _num(j['price'] ?? 0),
        openedOn: DateTime.fromMillisecondsSinceEpoch(j['opened'] as int),
      );
}

/// Programme de perte de poids d'un animal.
class DietPlan {
  DietPlan({
    required this.petId,
    required this.startKg,
    required this.targetKg,
    required DateTime startDate,
    this.weeklyRate = 0.01,
  }) : startDate = _day(startDate);

  /// Rythme conseillé : 1 à 2 % du poids par semaine.
  static const minRate = 0.01;
  static const maxRate = 0.02;

  /// Pas plus de 40 % du poids à perdre dans un même programme.
  static const maxLoss = 0.4;

  final int petId;
  final double startKg;
  final double targetKg;
  final DateTime startDate;

  /// Perte visée par semaine (0,01 = 1 %).
  final double weeklyRate;

  static String? validate(DietPlan p) {
    if (p.targetKg <= 0) return 'Le poids cible doit être supérieur à 0.';
    if (p.targetKg >= p.startKg) {
      return 'Le poids cible doit être inférieur au poids actuel.';
    }
    if (p.targetKg < p.startKg * (1 - maxLoss)) {
      return 'Objectif trop bas : 40 % de perte maximum, à voir avec le vétérinaire.';
    }
    if (p.weeklyRate < minRate - 1e-9 || p.weeklyRate > maxRate + 1e-9) {
      return 'Le rythme doit être compris entre 1 et 2 % par semaine.';
    }
    return null;
  }

  /// Semaines nécessaires au rythme choisi.
  int get weeks => (math.log(targetKg / startKg) / math.log(1 - weeklyRate)).ceil();

  /// Date d'arrivée estimée.
  DateTime get arrival => startDate.add(Duration(days: weeks * 7));

  /// Poids prévu à une date (jamais sous le poids cible).
  double plannedKgAt(DateTime d) {
    final w = _day(d).difference(startDate).inDays / 7;
    if (w <= 0) return startKg;
    return math.max(targetKg, startKg * math.pow(1 - weeklyRate, w).toDouble());
  }

  Map<String, Object?> toJson() => {
        'pet': petId,
        'start_kg': startKg,
        'target_kg': targetKg,
        'start': startDate.millisecondsSinceEpoch,
        'rate': weeklyRate,
      };

  factory DietPlan.fromJson(Map<String, Object?> j) => DietPlan(
        petId: j['pet'] as int,
        startKg: _num(j['start_kg']),
        targetKg: _num(j['target_kg']),
        startDate: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        weeklyRate: _num(j['rate'] ?? 0.01),
      );
}

/// Plafonds de dépense alimentaire par mois.
class FoodBudget {
  const FoodBudget({this.all, this.pets = const {}});

  static const maxAmount = 100000.0;

  /// Plafond pour tous les animaux ensemble.
  final double? all;

  /// Plafond par animal.
  final Map<int, double> pets;

  /// Plafond de l'animal, ou de tous les animaux si [petId] est `null`.
  double? capFor(int? petId) => petId == null ? all : pets[petId];

  FoodBudget withCap(int? petId, double? cap) => petId == null
      ? FoodBudget(all: cap, pets: pets)
      : FoodBudget(all: all, pets: {
          for (final e in pets.entries)
            if (e.key != petId) e.key: e.value,
          petId: ?cap,
        });

  Map<String, Object?> toJson() => {
        'all': ?all,
        if (pets.isNotEmpty) 'pets': {for (final e in pets.entries) '${e.key}': e.value},
      };

  factory FoodBudget.fromJson(Map<String, Object?> j) => FoodBudget(
        all: (j['all'] as num?)?.toDouble(),
        pets: {
          for (final e in ((j['pets'] as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): _num(e.value),
        },
      );
}

/// Réglages du module Alimentation d'un compte : sacs ouverts, programmes
/// de perte de poids et budget. Valeur immuable.
class FeedingPlan {
  const FeedingPlan({
    this.bags = const [],
    this.diets = const {},
    this.budget = const FoodBudget(),
    this.nextBagId = 1,
  });

  final List<FoodBag> bags;
  final Map<int, DietPlan> diets;
  final FoodBudget budget;
  final int nextBagId;

  FeedingPlan copyWith({
    List<FoodBag>? bags,
    Map<int, DietPlan>? diets,
    FoodBudget? budget,
    int? nextBagId,
  }) =>
      FeedingPlan(
        bags: bags ?? this.bags,
        diets: diets ?? this.diets,
        budget: budget ?? this.budget,
        nextBagId: nextBagId ?? this.nextBagId,
      );

  FoodBag? bag(int id) => bags.where((b) => b.id == id).firstOrNull;

  /// Sacs mangés par un animal (tous si [petId] est `null`).
  List<FoodBag> bagsOf(int? petId) =>
      petId == null ? bags : [for (final b in bags) if (b.petIds.contains(petId)) b];

  /// Retire les animaux supprimés (un sac sans animal disparaît).
  FeedingPlan only(Set<int> petIds) {
    final kept = <FoodBag>[];
    for (final b in bags) {
      final ids = [for (final id in b.petIds) if (petIds.contains(id)) id];
      if (ids.isNotEmpty) kept.add(ids.length == b.petIds.length ? b : b.withPets(ids));
    }
    return copyWith(
      bags: kept,
      diets: {for (final e in diets.entries) if (petIds.contains(e.key)) e.key: e.value},
      budget: FoodBudget(all: budget.all, pets: {
        for (final e in budget.pets.entries) if (petIds.contains(e.key)) e.key: e.value,
      }),
    );
  }

  Map<String, Object?> toJson() => {
        'bags': [for (final b in bags) b.toJson()],
        'diets': [for (final d in diets.values) d.toJson()],
        'budget': budget.toJson(),
        'next_bag': nextBagId,
      };

  factory FeedingPlan.fromJson(Map<String, Object?> j) => FeedingPlan(
        bags: [
          for (final b in (j['bags'] as List?) ?? const [])
            FoodBag.fromJson((b as Map).cast<String, Object?>()),
        ],
        diets: {
          for (final p in [
            for (final d in (j['diets'] as List?) ?? const [])
              DietPlan.fromJson((d as Map).cast<String, Object?>()),
          ])
            p.petId: p,
        },
        budget: FoodBudget.fromJson(((j['budget'] as Map?) ?? const {}).cast<String, Object?>()),
        nextBagId: (j['next_bag'] as int?) ?? 1,
      );
}

abstract interface class FeedingPlanStore {
  Future<FeedingPlan> load();
  Future<void> save(FeedingPlan plan);
}

class MemoryFeedingPlanStore implements FeedingPlanStore {
  MemoryFeedingPlanStore([this.plan = const FeedingPlan()]);

  FeedingPlan plan;

  @override
  Future<FeedingPlan> load() async => plan;

  @override
  Future<void> save(FeedingPlan p) async => plan = p;
}

/// Table `app_settings`, une ligne JSON par compte (`feeding_plan:<id>`).
class SqliteFeedingPlanStore implements FeedingPlanStore {
  SqliteFeedingPlanStore(this._appDb, {this.ownerId});

  final AppDatabase _appDb;
  final int? ownerId;

  String get _key => ownerId == null ? 'feeding_plan' : 'feeding_plan:$ownerId';

  @override
  Future<FeedingPlan> load() async {
    final rows = await (await _appDb.database)
        .query('app_settings', where: 'key = ?', whereArgs: [_key]);
    final raw = rows.firstOrNull?['value'] as String?;
    if (raw == null) return const FeedingPlan();
    try {
      return FeedingPlan.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return const FeedingPlan();
    }
  }

  @override
  Future<void> save(FeedingPlan plan) async {
    await (await _appDb.database).insert(
      'app_settings',
      {'key': _key, 'value': jsonEncode(plan.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
