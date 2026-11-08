import 'reminder_enums.dart';

/// Type de soin d'un [HealthRecord].
enum HealthType {
  vaccination('Vaccination', ReminderType.vaccination),
  treatment('Traitement', ReminderType.treatment),
  consultation('Consultation', ReminderType.vetAppointment),
  dental('Détartrage', ReminderType.checkup),
  analysis('Analyse', ReminderType.checkup),
  other('Autre', ReminderType.other);

  const HealthType(this.label, this.reminderType);

  final String label;

  /// Type du rappel créé pour la prochaine échéance.
  final ReminderType reminderType;

  static HealthType parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => other);
}

/// Entité HealthRecord (Module 2), une ligne de la table SQLite
/// `health_records` : un soin, une visite ou une pesée chez le vétérinaire.
class HealthRecord {
  HealthRecord({
    this.id,
    required this.petId,
    required this.type,
    required DateTime date,
    this.vet,
    this.description,
    this.weightKg,
    this.medication,
    this.cost = 0,
    DateTime? nextDue,
    this.createdAt,
    this.updatedAt,
  })  : date = DateTime(date.year, date.month, date.day),
        nextDue = nextDue == null
            ? null
            : DateTime(nextDue.year, nextDue.month, nextDue.day);

  static const maxVetLength = 60;
  static const maxMedicationLength = 80;
  static const maxDescriptionLength = 500;
  static const maxCost = 100000.0;
  static const maxWeightKg = 1500.0;

  /// Heure du rappel créé pour la prochaine échéance.
  static const reminderHour = 9;

  /// Clé primaire (null tant que le dossier n'est pas en base).
  final int? id;

  /// Animal concerné (table `pets`).
  final int petId;
  final HealthType type;

  /// Jour du soin (minuit).
  final DateTime date;
  final String? vet;
  final String? description;

  /// Poids mesuré lors de la visite.
  final double? weightKg;
  final String? medication;
  final double cost;

  /// Prochaine échéance (rappel de vaccin, contrôle...) : un rappel est créé
  /// automatiquement dans le module Rappels.
  final DateTime? nextDue;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Titre du rappel lié à la prochaine échéance.
  String get reminderTitle =>
      medication == null ? 'Rappel ${type.label.toLowerCase()}' : '${type.label} : $medication';

  /// Règles métier, partagées par le formulaire et le repository.
  /// Renvoie le message d'erreur, ou `null` si le dossier est valide.
  static String? validate(HealthRecord r, DateTime now) {
    if (r.date.isAfter(DateTime(now.year, now.month, now.day))) {
      return 'La date du soin ne peut pas être dans le futur.';
    }
    final next = r.nextDue;
    if (next != null && !next.isAfter(r.date)) {
      return 'La prochaine échéance doit être postérieure à la date du soin.';
    }
    if (r.cost < 0) return 'Le coût ne peut pas être négatif.';
    if (r.cost > maxCost) return 'Coût trop élevé.';
    final w = r.weightKg;
    if (w != null && (w <= 0 || w > maxWeightKg)) {
      return 'Le poids doit être compris entre 0 et ${maxWeightKg.round()} kg.';
    }
    for (final (label, value, max) in [
      ('Le nom du vétérinaire', r.vet, maxVetLength),
      ('Le médicament', r.medication, maxMedicationLength),
      ('La description', r.description, maxDescriptionLength),
    ]) {
      if ((value ?? '').trim().length > max) {
        return '$label ne doit pas dépasser $max caractères.';
      }
    }
    return null;
  }

  HealthRecord copyWith({
    int? id,
    int? petId,
    HealthType? type,
    DateTime? date,
    String? Function()? vet,
    String? Function()? description,
    double? Function()? weightKg,
    String? Function()? medication,
    double? cost,
    DateTime? Function()? nextDue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HealthRecord(
      id: id ?? this.id,
      petId: petId ?? this.petId,
      type: type ?? this.type,
      date: date ?? this.date,
      vet: vet != null ? vet() : this.vet,
      description: description != null ? description() : this.description,
      weightKg: weightKg != null ? weightKg() : this.weightKg,
      medication: medication != null ? medication() : this.medication,
      cost: cost ?? this.cost,
      nextDue: nextDue != null ? nextDue() : this.nextDue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'pet_id': petId,
        'type': type.name,
        'date': date.millisecondsSinceEpoch,
        'vet': vet,
        'description': description,
        'weight_kg': weightKg,
        'medication': medication,
        'cost': cost,
        'next_due': nextDue?.millisecondsSinceEpoch,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory HealthRecord.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return HealthRecord(
      id: map['id'] as int?,
      petId: map['pet_id'] as int,
      type: HealthType.parse(map['type'] as String?),
      date: date('date')!,
      vet: map['vet'] as String?,
      description: map['description'] as String?,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      medication: map['medication'] as String?,
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      nextDue: date('next_due'),
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
    );
  }

  @override
  String toString() => 'HealthRecord(#$id pet $petId ${type.name} $date)';
}
