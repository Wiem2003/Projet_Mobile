import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/reminder_calculator.dart';
import '../models/reminder.dart';

export 'formatters.dart';

extension ReminderTypeStyle on ReminderType {
  IconData get icon => switch (this) {
        ReminderType.vaccination => Icons.vaccines_rounded,
        ReminderType.deworming => Icons.pest_control_rounded,
        ReminderType.vetAppointment => Icons.event_available_rounded,
        ReminderType.treatment => Icons.medication_rounded,
        ReminderType.checkup => Icons.monitor_heart_rounded,
        ReminderType.purchase => Icons.shopping_basket_rounded,
        ReminderType.other => Icons.notifications_active_rounded,
      };

  Color get color => switch (this) {
        ReminderType.vaccination => const Color(0xFFDC2626),
        ReminderType.deworming => const Color(0xFFEA580C),
        ReminderType.vetAppointment => const Color(0xFF2563EB),
        ReminderType.treatment => const Color(0xFFDB2777),
        ReminderType.checkup => const Color(0xFF0D9488),
        ReminderType.purchase => const Color(0xFF65A30D),
        ReminderType.other => AppColors.reminder,
      };
}

extension ReminderRepeatStyle on ReminderRepeat {
  IconData get icon => switch (this) {
        ReminderRepeat.none => Icons.looks_one_outlined,
        ReminderRepeat.weekly => Icons.view_week_outlined,
        ReminderRepeat.monthly => Icons.calendar_view_month_outlined,
        ReminderRepeat.yearly => Icons.event_repeat_outlined,
        ReminderRepeat.seasonal => Icons.eco_outlined,
      };
}

/// Couleur d'urgence du compte à rebours.
Color urgencyColor(Reminder r, DateTime now) {
  if (r.isDone) return AppColors.success;
  switch (ReminderCalculator.bucketOf(r, now)) {
    case ReminderBucket.overdue:
      return AppColors.danger;
    case ReminderBucket.today:
    case ReminderBucket.tomorrow:
      return AppColors.warning;
    default:
      return AppColors.reminder;
  }
}
