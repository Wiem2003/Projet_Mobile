import '../core/pets/pet_directory.dart';
import '../models/health_model.dart';
import '../models/health_record.dart';
import '../models/health_repository.dart';
import '../models/health_stats.dart';
import '../models/reminder_enums.dart';
import 'reminders_controller.dart';

/// Controller du module Santé.
///
/// Reçoit les actions de la View, applique les règles via le repository
/// SQLite puis met à jour le [HealthModel]. Il prévient aussi :
/// - le module Rappels : la prochaine échéance du dossier le plus récent de
///   chaque type (par animal) devient un rappel ; les échéances des dossiers
///   plus anciens sont retirées ;
/// - le module Animaux ([onWeightMeasured]) : la dernière pesée devient le
///   poids de l'animal.
class HealthController {
  HealthController({
    required this.model,
    required HealthRepository repository,
    required PetDirectory pets,
    this.reminders,
    this.onWeightMeasured,
  })  : _repo = repository,
        _petDirectory = pets;

  final HealthModel model;
  final HealthRepository _repo;
  final PetDirectory _petDirectory;
  final RemindersController? reminders;

  /// Branché dans `main.dart` : met à jour la fiche de l'animal.
  Future<void> Function(int petId, double weightKg)? onWeightMeasured;

  // --------------------------------------------------------------- Filtres

  void setPetFilter(int? id) => model.setPetFilter(id);
  void setTypeFilter(HealthType? t) => model.setTypeFilter(t);
  void setPeriod(HealthPeriod p) => model.setPeriod(p);

  // --------------------------------------------------------------- Actions

  Future<void> load() async {
    try {
      model.setPets(await _petDirectory.getPets());
      model.setRecords(await _repo.getAll());
    } on Exception catch (e) {
      model.setError('Impossible de charger les dossiers de santé : $e');
    }
  }

  Future<HealthRecord> save(HealthRecord r) async {
    final previous = r.id == null ? null : model.byId(r.id);
    final saved = r.id == null ? await _repo.create(r) : await _repo.update(r);
    await load();
    await _syncReminders(saved.petId, saved.type);
    if (previous != null &&
        (previous.petId != saved.petId || previous.type != saved.type)) {
      await _syncReminders(previous.petId, previous.type);
    }
    await _syncWeight(saved.petId);
    if (previous != null && previous.petId != saved.petId) {
      await _syncWeight(previous.petId);
    }
    return saved;
  }

  Future<void> delete(HealthRecord r) async {
    await _repo.delete(r.id!);
    await load();
    await reminders?.removeDeadlines(ReminderSource.health, r.id!);
    await _syncReminders(r.petId, r.type);
    await _syncWeight(r.petId);
  }

  /// Seul le dossier le plus récent d'un type garde son échéance : un vaccin
  /// refait remplace le rappel du précédent.
  Future<void> _syncReminders(int petId, HealthType type) async {
    final rem = reminders;
    if (rem == null) return;
    final sameKind =
        model.all.where((x) => x.petId == petId && x.type == type).toList();
    for (final (i, x) in sameKind.indexed) {
      final due = i == 0 ? x.nextDue : null;
      await rem.syncDeadline(
        source: ReminderSource.health,
        sourceId: x.id!,
        dueDate: due == null
            ? null
            : DateTime(due.year, due.month, due.day, HealthRecord.reminderHour),
        petId: x.petId,
        type: x.type.reminderType,
        title: x.reminderTitle,
      );
    }
  }

  Future<void> _syncWeight(int petId) async {
    final last = model.lastWeighing(petId);
    if (last != null) await onWeightMeasured?.call(petId, last.weightKg!);
  }

  // ------------------------------------------------------------------ Démo

  /// Un an de suivi vétérinaire pour les deux premiers animaux.
  /// Les dossiers déjà présents (même animal, type et jour) sont ignorés.
  Future<int> seedDemo() async {
    final pets = model.pets;
    if (pets.isEmpty) return 0;
    final (dog, cat) = pets.demoPair;
    final first = dog.id, second = cat.id;
    final t = model.now;
    DateTime ago(int months, [int days = 0]) =>
        DateTime(t.year, t.month - months, t.day - days);
    DateTime inMonths(DateTime from, int months) =>
        DateTime(from.year, from.month + months, from.day);
    const vet = 'Dr Ben Salah — Clinique des Lilas';

    final drafts = [
      HealthRecord(petId: first, type: HealthType.vaccination, date: ago(11),
          vet: vet, medication: 'CHPPi + rage', cost: 60, weightKg: 26.5,
          nextDue: inMonths(ago(11), 12), description: 'Rappel annuel'),
      HealthRecord(petId: first, type: HealthType.consultation, date: ago(8),
          vet: vet, medication: 'Otomax', cost: 45, weightKg: 27,
          description: 'Otite de l\'oreille gauche'),
      HealthRecord(petId: first, type: HealthType.dental, date: ago(6),
          vet: vet, cost: 120, weightKg: 27.4, nextDue: inMonths(ago(6), 12)),
      HealthRecord(petId: first, type: HealthType.analysis, date: ago(3),
          vet: vet, cost: 80, weightKg: 27.8, description: 'Bilan sanguin : RAS'),
      HealthRecord(petId: first, type: HealthType.consultation, date: ago(1),
          vet: vet, cost: 40, weightKg: 28.1, description: 'Contrôle de routine',
          nextDue: inMonths(ago(1), 6)),
      HealthRecord(petId: first, type: HealthType.treatment, date: ago(0, 10),
          medication: 'Milbemax (vermifuge)', cost: 25,
          nextDue: inMonths(ago(0, 10), 3)),
      HealthRecord(petId: second, type: HealthType.vaccination, date: ago(5),
          vet: vet, medication: 'Typhus + coryza', cost: 55, weightKg: 4.2,
          nextDue: inMonths(ago(5), 12)),
      HealthRecord(petId: second, type: HealthType.consultation, date: ago(2),
          vet: vet, cost: 35, weightKg: 4.4, description: 'Suivi de stérilisation'),
      HealthRecord(petId: second, type: HealthType.treatment, date: ago(0, 20),
          medication: 'Frontline (antipuces)', cost: 30, weightKg: 4.5,
          nextDue: inMonths(ago(0, 20), 1)),
    ];
    final existing = {for (final r in model.all) (r.petId, r.type, r.date)};
    var count = 0;
    for (final d in drafts) {
      if (existing.contains((d.petId, d.type, d.date))) continue;
      await _repo.create(d);
      count++;
    }
    await load();
    if (count > 0) {
      for (final pet in {first, second}) {
        for (final type in HealthType.values) {
          await _syncReminders(pet, type);
        }
        await _syncWeight(pet);
      }
    }
    return count;
  }
}
