import 'reminder.dart';
import 'reminder_calculator.dart';

/// Niveau d'escalade d'un rappel en retard.
///
/// J+1 : première relance ; J+3 : deuxième relance ; au-delà : critique.
enum EscalationLevel {
  none(''),
  overdue('En retard'),
  firstReminder('Relance 1'),
  secondReminder('Relance 2'),
  critical('Critique');

  const EscalationLevel(this.label);

  final String label;
}

/// Limites de report d'un type de rappel (`null` = sans limite).
class PostponePolicy {
  const PostponePolicy({this.maxCount, this.maxDays});

  /// Nombre de reports autorisés.
  final int? maxCount;

  /// Durée maximale d'un report, comptée depuis l'échéance (ou depuis
  /// aujourd'hui si l'échéance est passée).
  final int? maxDays;

  bool get isLimited => maxCount != null || maxDays != null;
}

/// Règles métier « priorité et escalade » du module Rappels.
/// Fonctions pures, `now` toujours injecté pour rester testable.
abstract final class ReminderRules {
  /// Jours après l'échéance où une relance est envoyée.
  static const firstReminderDay = 1;
  static const secondReminderDay = 3;

  /// Créneaux de notification des relances (cf. `notificationIdFor`).
  static const firstReminderSlot = 14;
  static const secondReminderSlot = 15;

  /// Gravité d'un oubli, de 1 (achat) à 5 (vaccin).
  static int severity(ReminderType t) => switch (t) {
        ReminderType.vaccination => 5,
        ReminderType.treatment => 4,
        ReminderType.vetAppointment => 4,
        ReminderType.deworming => 3,
        ReminderType.checkup => 3,
        ReminderType.other => 2,
        ReminderType.purchase => 1,
      };

  /// Jours calendaires de retard (0 si le rappel n'est pas en retard ou si
  /// l'échéance est passée aujourd'hui même).
  static int daysLate(Reminder r, DateTime now) {
    if (!r.isOverdue(now)) return 0;
    final days = -ReminderCalculator.daysUntil(r.dueDate, now);
    return days < 0 ? 0 : days;
  }

  /// Score d'urgence = gravité × jours de retard (au moins 1 jour dès que
  /// l'échéance est dépassée). 0 pour un rappel à venir ou fait.
  static int urgencyScore(Reminder r, DateTime now) {
    if (!r.isOverdue(now)) return 0;
    final days = daysLate(r, now);
    return severity(r.type) * (days < 1 ? 1 : days);
  }

  /// Tri de la liste « En retard » : le plus urgent d'abord ; à score égal,
  /// la plus ancienne échéance.
  static int compareByUrgency(Reminder a, Reminder b, DateTime now) {
    final byScore = urgencyScore(b, now).compareTo(urgencyScore(a, now));
    return byScore != 0 ? byScore : a.dueDate.compareTo(b.dueDate);
  }

  static EscalationLevel escalation(Reminder r, DateTime now) {
    if (!r.isOverdue(now)) return EscalationLevel.none;
    final days = daysLate(r, now);
    if (days > secondReminderDay) return EscalationLevel.critical;
    if (days >= secondReminderDay) return EscalationLevel.secondReminder;
    if (days >= firstReminderDay) return EscalationLevel.firstReminder;
    return EscalationLevel.overdue;
  }

  static bool isCritical(Reminder r, DateTime now) =>
      escalation(r, now) == EscalationLevel.critical;

  /// Relances programmées après l'échéance (J+1 et J+3, même heure), pour un
  /// rappel non fait.
  static List<({EscalationLevel level, DateTime at, int slot})> relances(
      Reminder r) {
    if (r.isDone) return const [];
    DateTime plus(int days) => DateTime(r.dueDate.year, r.dueDate.month,
        r.dueDate.day + days, r.dueDate.hour, r.dueDate.minute);
    return [
      (
        level: EscalationLevel.firstReminder,
        at: plus(firstReminderDay),
        slot: firstReminderSlot,
      ),
      (
        level: EscalationLevel.secondReminder,
        at: plus(secondReminderDay),
        slot: secondReminderSlot,
      ),
    ];
  }

  static List<({EscalationLevel level, DateTime at, int slot})> pendingRelances(
          Reminder r, DateTime now) =>
      relances(r).where((x) => x.at.isAfter(now)).toList();

  // ------------------------------------------------------------- Reports

  /// Soins médicaux : nombre et durée des reports limités. Achats et rappels
  /// « Autre » : sans limite.
  static PostponePolicy postponePolicy(ReminderType t) => switch (t) {
        ReminderType.vaccination => const PostponePolicy(maxCount: 3, maxDays: 30),
        ReminderType.deworming => const PostponePolicy(maxCount: 3, maxDays: 30),
        ReminderType.vetAppointment =>
          const PostponePolicy(maxCount: 3, maxDays: 30),
        ReminderType.checkup => const PostponePolicy(maxCount: 3, maxDays: 60),
        // Un traitement en cours ne peut pas attendre longtemps.
        ReminderType.treatment => const PostponePolicy(maxCount: 2, maxDays: 7),
        ReminderType.purchase || ReminderType.other => const PostponePolicy(),
      };

  /// Reports encore possibles (`null` = sans limite).
  static int? remainingPostpones(Reminder r) {
    final max = postponePolicy(r.type).maxCount;
    if (max == null) return null;
    final left = max - r.postponeCount;
    return left < 0 ? 0 : left;
  }

  /// La limite est atteinte : il faut prendre rendez-vous.
  static bool needsAppointment(Reminder r) => remainingPostpones(r) == 0;

  /// Date la plus lointaine autorisée pour un report (`null` = sans limite).
  static DateTime? latestPostponeDate(Reminder r, DateTime now) {
    final days = postponePolicy(r.type).maxDays;
    if (days == null) return null;
    final base = ReminderCalculator.postponeBase(r.dueDate, now);
    return DateTime(base.year, base.month, base.day + days, base.hour, base.minute);
  }

  /// « ce vaccin », « ce traitement »...
  static String _this(ReminderType t) => 'ce ${t.label.toLowerCase()}';

  /// Message si le report est refusé, sinon `null`.
  static String? postponeError(Reminder r, DateTime newDate, DateTime now) {
    final policy = postponePolicy(r.type);
    final max = policy.maxCount;
    if (max != null && r.postponeCount >= max) {
      return 'Limite atteinte : ${_this(r.type)} a déjà été reporté $max fois. '
          'Prenez rendez-vous chez le vétérinaire.';
    }
    final latest = latestPostponeDate(r, now);
    if (latest != null && newDate.isAfter(latest)) {
      String two(int n) => n.toString().padLeft(2, '0');
      return 'Un report ne peut pas dépasser ${policy.maxDays} jours pour '
          '${_this(r.type)} (au plus tard le ${two(latest.day)}/'
          '${two(latest.month)}/${latest.year}).';
    }
    return null;
  }

  /// Brouillon du rendez-vous proposé quand la limite de reports est
  /// atteinte (demain à 10 h).
  static Reminder appointmentFor(Reminder r, DateTime now) {
    final title = 'Rendez-vous vétérinaire : ${r.title}';
    return Reminder(
        petId: r.petId,
        // Titre limité à 80 caractères.
        title: title.length <= 80 ? title : '${title.substring(0, 79)}…',
        type: ReminderType.vetAppointment,
        dueDate: DateTime(now.year, now.month, now.day + 1, 10),
        alertOffsets: const [AlertOffset.oneDay, AlertOffset.oneHour],
        notes: '« ${r.title} » reporté ${r.postponeCount} fois.',
      );
  }
}
