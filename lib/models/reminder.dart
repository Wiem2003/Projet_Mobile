import 'reminder_enums.dart';

export 'reminder_enums.dart';

/// Entité Reminder (Module 5), une ligne de la table SQLite `reminders`.
class Reminder {
  Reminder({
    this.id,
    this.petId,
    required this.title,
    required this.type,
    required this.dueDate,
    List<AlertOffset>? alertOffsets,
    this.repeat = ReminderRepeat.none,
    this.status = ReminderStatus.upcoming,
    this.notes,
    this.source = ReminderSource.manual,
    this.sourceId,
    this.postponeCount = 0,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  }) : alertOffsets = List.unmodifiable(alertOffsets ?? AlertOffset.defaults);

  /// Clé primaire (null tant que le rappel n'est pas enregistré).
  final int? id;

  /// Animal concerné (table `pets`) ; `null` = rappel général.
  final int? petId;
  final String title;
  final ReminderType type;
  final DateTime dueDate;
  final List<AlertOffset> alertOffsets;
  final ReminderRepeat repeat;
  final ReminderStatus status;
  final String? notes;
  final ReminderSource source;

  /// Id du HealthRecord / FeedingRecord d'origine.
  final int? sourceId;
  final int postponeCount;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDone => status == ReminderStatus.done;
  bool get isAutomatic => source != ReminderSource.manual;
  bool isOverdue(DateTime now) => !isDone && dueDate.isBefore(now);

  Reminder copyWith({
    int? id,
    int? Function()? petId,
    String? title,
    ReminderType? type,
    DateTime? dueDate,
    List<AlertOffset>? alertOffsets,
    ReminderRepeat? repeat,
    ReminderStatus? status,
    String? Function()? notes,
    ReminderSource? source,
    int? Function()? sourceId,
    int? postponeCount,
    DateTime? Function()? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Reminder(
      id: id ?? this.id,
      petId: petId != null ? petId() : this.petId,
      title: title ?? this.title,
      type: type ?? this.type,
      dueDate: dueDate ?? this.dueDate,
      alertOffsets: alertOffsets ?? this.alertOffsets,
      repeat: repeat ?? this.repeat,
      status: status ?? this.status,
      notes: notes != null ? notes() : this.notes,
      source: source ?? this.source,
      sourceId: sourceId != null ? sourceId() : this.sourceId,
      postponeCount: postponeCount ?? this.postponeCount,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'pet_id': petId,
        'title': title,
        'type': type.name,
        'due_date': dueDate.millisecondsSinceEpoch,
        'alert_offsets': AlertOffset.encode(alertOffsets),
        'repeat': repeat.name,
        'status': status.name,
        'notes': notes,
        'source': source.name,
        'source_id': sourceId,
        'postpone_count': postponeCount,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory Reminder.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return Reminder(
      id: map['id'] as int?,
      petId: map['pet_id'] as int?,
      title: map['title'] as String,
      type: ReminderType.parse(map['type'] as String?),
      dueDate: date('due_date')!,
      alertOffsets: AlertOffset.decode(map['alert_offsets'] as String?),
      repeat: ReminderRepeat.parse(map['repeat'] as String?),
      status: ReminderStatus.parse(map['status'] as String?),
      notes: map['notes'] as String?,
      source: ReminderSource.parse(map['source'] as String?),
      sourceId: map['source_id'] as int?,
      postponeCount: (map['postpone_count'] as int?) ?? 0,
      completedAt: date('completed_at'),
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
    );
  }

  @override
  String toString() =>
      'Reminder(#$id "$title" ${type.name} $dueDate ${status.name})';
}
