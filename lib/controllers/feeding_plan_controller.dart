import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import '../models/feeding_insights.dart';
import '../models/feeding_plan.dart';
import '../models/feeding_record.dart';
import '../models/reminder.dart';
import '../models/validation.dart';
import 'reminders_controller.dart';

/// État des sacs, programmes de perte de poids et budget, observé par
/// l'écran Alimentation.
class FeedingPlanModel extends ChangeNotifier {
  FeedingPlan _plan = const FeedingPlan();

  FeedingPlan get plan => _plan;

  void setPlan(FeedingPlan p) {
    _plan = p;
    notifyListeners();
  }
}

/// Controller des sacs (stock et rappel « Racheter »), des programmes de
/// perte de poids et du budget alimentaire.
class FeedingPlanController {
  FeedingPlanController({
    required this.model,
    required FeedingPlanStore planStore,
    required List<PetSummary> Function() petList,
    required List<FeedingRecord> Function() feedingRecords,
    this.reminders,
    DateTime Function()? clock,
  })  : _store = planStore,
        _pets = petList,
        _feeding = feedingRecords,
        _clock = clock ?? DateTime.now;

  final FeedingPlanModel model;
  final FeedingPlanStore _store;
  final List<PetSummary> Function() _pets;
  final List<FeedingRecord> Function() _feeding;
  final DateTime Function() _clock;

  /// Module Rappels : rappel « Racheter » automatique.
  final RemindersController? reminders;

  /// Heure du rappel « Racheter ».
  static const restockHour = 9;

  FeedingPlan get _plan => model.plan;

  /// Relit les réglages (animaux supprimés retirés) puis met à jour les
  /// rappels « Racheter ».
  Future<void> load() async {
    final ids = {for (final p in _pets()) p.id};
    final loaded = await _store.load();
    final kept = loaded.only(ids);
    for (final b in loaded.bags) {
      if (kept.bag(b.id) == null) await _removeRestock(b.id);
    }
    model.setPlan(kept);
    await syncRestock();
  }

  Future<void> _save(FeedingPlan p) async {
    model.setPlan(p);
    await _store.save(p);
  }

  // ------------------------------------------------------------------ Sacs

  /// Ajoute (id 0) ou modifie un sac. Lève une [RecordException].
  Future<FoodBag> saveBag(FoodBag draft) async {
    final error = FoodBag.validate(draft, _clock());
    if (error != null) throw RecordException(error);
    final isNew = _plan.bag(draft.id) == null;
    final bag = isNew
        ? FoodBag(
            id: _plan.nextBagId,
            petIds: draft.petIds,
            foodType: draft.foodType,
            brand: draft.brand,
            weightG: draft.weightG,
            price: draft.price,
            openedOn: draft.openedOn)
        : draft;
    await _save(_plan.copyWith(
      bags: [for (final b in _plan.bags) if (b.id != bag.id) b, bag],
      nextBagId: isNew ? _plan.nextBagId + 1 : null,
    ));
    await syncRestock();
    return bag;
  }

  /// Sac terminé ou retiré : son rappel « Racheter » disparaît.
  Future<void> removeBag(FoodBag bag) async {
    await _save(_plan.copyWith(bags: [for (final b in _plan.bags) if (b.id != bag.id) b]));
    await _removeRestock(bag.id);
  }

  Future<void> _removeRestock(int bagId) async =>
      reminders?.removeDeadlines(ReminderSource.feeding, bagId);

  /// Crée, déplace ou supprime le rappel « Racheter » de chaque sac (3 jours
  /// avant la date où il sera vide). Un rappel déjà marqué fait n'est pas
  /// recréé : il faut enregistrer le nouveau sac.
  Future<void> syncRestock() async {
    final r = reminders;
    if (r == null) return;
    final now = _clock();
    final names = {for (final p in _pets()) p.id: p.name};
    final feeding = _feeding();
    for (final bag in _plan.bags) {
      final bought = r.model.all.any((x) =>
          x.source == ReminderSource.feeding && x.sourceId == bag.id && x.isDone);
      if (bought) continue;
      final due = FeedingInsights.stock(bag, feeding, now).restockOn;
      final who = [for (final id in bag.petIds) ?names[id]].join(', ');
      await r.syncDeadline(
        source: ReminderSource.feeding,
        sourceId: bag.id,
        dueDate: due?.add(const Duration(hours: restockHour)),
        petId: bag.petIds.length == 1 ? bag.petIds.first : null,
        type: ReminderType.purchase,
        title: 'Racheter : ${bag.label.toLowerCase()}${who.isEmpty ? '' : ' ($who)'}',
        alertOffsets: const [AlertOffset.atTime],
      );
    }
  }

  // -------------------------------------------------------- Perte de poids

  Future<void> startDiet(DietPlan plan) async {
    final error = DietPlan.validate(plan);
    if (error != null) throw RecordException(error);
    await _save(_plan.copyWith(diets: {..._plan.diets, plan.petId: plan}));
  }

  Future<void> stopDiet(int petId) => _save(_plan.copyWith(
      diets: {for (final e in _plan.diets.entries) if (e.key != petId) e.key: e.value}));

  // ---------------------------------------------------------------- Budget

  /// Plafond mensuel d'un animal, ou de tous si [petId] est `null` ;
  /// [cap] `null` retire le plafond.
  Future<void> setBudget(int? petId, double? cap) async {
    if (cap != null && (cap <= 0 || cap > FoodBudget.maxAmount)) {
      throw const RecordException('Le plafond doit être compris entre 0 et 100 000 DT.');
    }
    await _save(_plan.copyWith(budget: _plan.budget.withCap(petId, cap)));
  }
}
