/// Nature de l'échéance.
enum ReminderType {
  vaccination('Vaccin', 'Vaccination'),
  deworming('Vermifuge', 'Vermifuge'),
  vetAppointment('Rendez-vous', 'Rendez-vous vétérinaire'),
  treatment('Traitement', 'Traitement'),
  checkup('Contrôle', 'Contrôle médical'),
  purchase('Achat', 'Acheter de la nourriture'),
  other('Autre', 'Rappel');

  const ReminderType(this.label, this.defaultTitle);

  final String label;
  final String defaultTitle;

  static ReminderType parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => other);
}

enum ReminderRepeat {
  none('Aucune', 'Une seule fois'),
  weekly('Hebdo', 'Chaque semaine'),
  monthly('Mensuelle', 'Chaque mois'),
  yearly('Annuelle', 'Chaque année'),

  /// Antipuces, antitiques : mensuel en saison des parasites (mars à
  /// octobre), tous les 3 mois le reste de l'année.
  seasonal('Saison', 'Chaque mois de mars à octobre, tous les 3 mois sinon');

  const ReminderRepeat(this.label, this.description);

  final String label;
  final String description;

  static ReminderRepeat parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => none);
}

/// Statut stocké. « En retard » n'est pas stocké : il est calculé
/// (rappel non fait dont la date est passée).
enum ReminderStatus {
  upcoming('À venir'),
  done('Fait'),
  postponed('Reporté');

  const ReminderStatus(this.label);

  final String label;

  static ReminderStatus parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => upcoming);
}

/// Origine du rappel : saisie manuelle ou générée par un autre module.
enum ReminderSource {
  manual('Saisie manuelle'),
  health('Dossier de santé'),
  feeding('Alimentation');

  const ReminderSource(this.label);

  final String label;

  static ReminderSource parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => manual);
}

/// Délai entre la notification et l'échéance (J-10, J-1, jour J...).
enum AlertOffset {
  atTime(Duration.zero, 'À l\'heure', 'Jour J'),
  oneHour(Duration(hours: 1), '1 h avant', 'H-1'),
  oneDay(Duration(days: 1), '1 jour avant', 'J-1'),
  threeDays(Duration(days: 3), '3 jours avant', 'J-3'),
  oneWeek(Duration(days: 7), '1 semaine avant', 'J-7'),
  tenDays(Duration(days: 10), '10 jours avant', 'J-10'),
  oneMonth(Duration(days: 30), '1 mois avant', 'J-30');

  const AlertOffset(this.duration, this.label, this.shortLabel);

  final Duration duration;
  final String label;
  final String shortLabel;

  static const defaults = [AlertOffset.oneDay, AlertOffset.atTime];

  /// Stockage SQLite : noms séparés par des virgules (ex. "atTime,oneDay").
  static String encode(Iterable<AlertOffset> offsets) {
    final sorted = offsets.toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((e) => e.name).join(',');
  }

  static List<AlertOffset> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final names = raw.split(',').toSet();
    return values.where((e) => names.contains(e.name)).toList();
  }
}
