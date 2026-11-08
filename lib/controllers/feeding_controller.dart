import '../core/pets/pet_directory.dart';
import '../models/feeding_model.dart';
import '../models/feeding_record.dart';
import '../models/feeding_repository.dart';

/// Controller du module Alimentation.
///
/// Reçoit les actions de la View (filtres, ajout, modification, suppression),
/// applique les règles via le repository SQLite puis met à jour le
/// [FeedingModel] que la View observe. Les erreurs métier remontent en
/// `RecordException` à la View.
class FeedingController {
  FeedingController({
    required this.model,
    required FeedingRepository repository,
    required PetDirectory pets,
  })  : _repo = repository,
        _petDirectory = pets;

  final FeedingModel model;
  final FeedingRepository _repo;
  final PetDirectory _petDirectory;

  /// Repas ajoutés, modifiés ou supprimés (stock des sacs à recalculer).
  Future<void> Function()? onRecordsChanged;

  // --------------------------------------------------------------- Filtres

  void setPetFilter(int? id) => model.setPetFilter(id);

  void previousMonth() =>
      model.setMonth(DateTime(model.month.year, model.month.month - 1));

  /// Pas au-delà du mois en cours.
  void nextMonth() {
    if (!model.isCurrentMonth) {
      model.setMonth(DateTime(model.month.year, model.month.month + 1));
    }
  }

  // --------------------------------------------------------------- Actions

  Future<void> load() async {
    try {
      // Toujours relus : le module Animaux a pu les modifier.
      model.setPets(await _petDirectory.getPets());
      model.setRecords(await _repo.getAll());
    } on Exception catch (e) {
      model.setError('Impossible de charger les repas : $e');
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final result = await action();
    await load();
    await onRecordsChanged?.call();
    return result;
  }

  Future<FeedingRecord> save(FeedingRecord r) =>
      _mutate(() => r.id == null ? _repo.create(r) : _repo.update(r));

  Future<void> delete(FeedingRecord r) => _mutate(() => _repo.delete(r.id!));

  // ------------------------------------------------------------------ Démo

  /// Cinq mois de repas pour les animaux de démonstration. Les repas déjà
  /// présents (même animal, jour et type) ne sont pas dupliqués.
  Future<int> seedDemo() async {
    final pets = model.pets;
    if (pets.isEmpty) return 0;
    final (dog, cat) = pets.demoPair;
    final rex = dog.id, mia = cat.id;
    final t = model.now;
    final today = DateTime(t.year, t.month, t.day);

    final existing = {for (final r in model.all) (r.petId, r.date, r.foodType)};
    final drafts = <FeedingRecord>[];
    void add(int petId, DateTime day, FoodType type, double grams, double price,
        int meals, String brand) {
      if (existing.add((petId, day, type))) {
        drafts.add(FeedingRecord(
          petId: petId,
          date: day,
          foodType: type,
          quantityG: grams,
          price: (price * 100).round() / 100,
          meals: meals,
          brand: brand,
        ));
      }
    }

    for (var i = 0; i < 150; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      // Prix en légère hausse d'un mois à l'autre.
      final monthsAgo =
          (today.year - day.year) * 12 + today.month - day.month;
      final rise = 1 + (5 - monthsAgo).clamp(0, 5) * 0.03;
      add(rex, day, FoodType.kibble, 340 + (i % 3) * 10.0, 2.6 * rise, 2,
          'Royal Canin Maxi');
      add(mia, day, FoodType.kibble, 55, 0.9 * rise, 2, 'Purina One');
      if (i.isEven) {
        add(mia, day, FoodType.wet, 85, 1.8 * rise, 1, 'Felix');
      }
      if (i % 7 == 3) {
        add(rex, day, FoodType.treats, 40, 1.5, 1, 'Dentastix');
      }
    }
    final count = drafts.isEmpty ? 0 : await _repo.createAll(drafts);
    await load();
    await onRecordsChanged?.call();
    return count;
  }
}
