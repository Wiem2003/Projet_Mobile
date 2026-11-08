import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/activities_model.dart';
import '../models/activity.dart';
import '../models/dashboard/cross_alerts.dart';
import '../models/dashboard/dashboard_model.dart';
import '../models/dashboard/monthly_report.dart';
import '../models/dashboard/pet_costs.dart';
import '../models/dashboard/smart_pet_index.dart';
import '../models/feeding_model.dart';
import '../models/feeding_record.dart';
import '../models/health_model.dart';
import '../models/health_record.dart';
import '../models/pet.dart';
import '../models/pets_model.dart';
import '../models/reminder.dart';
import '../models/reminders_model.dart';

/// Données des cinq modules lues par le tableau de bord. [watch] abonne le
/// widget aux Models : l'accueil se met à jour à chaque saisie.
class DashboardData {
  const DashboardData({
    required this.pets,
    required this.health,
    required this.feeding,
    required this.activities,
    required this.reminders,
    required this.now,
  });

  factory DashboardData.watch(BuildContext context) => DashboardData(
        pets: context.watch<PetsModel>().all,
        health: context.watch<HealthModel>().all,
        feeding: context.watch<FeedingModel>().all,
        activities: context.watch<ActivitiesModel>().all,
        reminders: context.watch<RemindersModel>().all,
        now: context.read<PetsModel>().now,
      );

  final List<Pet> pets;
  final List<HealthRecord> health;
  final List<FeedingRecord> feeding;
  final List<Activity> activities;
  final List<Reminder> reminders;
  final DateTime now;

  PetIndex indexOf(Pet p) => SmartPetIndex.compute(p,
      reminders: reminders, activities: activities, health: health, feeding: feeding, now: now);

  List<PetIndex> get indexes => [for (final p in pets) indexOf(p)];

  /// Alertes croisées, sans celles masquées par l'utilisateur.
  List<CrossAlert> alerts(DashboardModel dashboard) => CrossAlerts.compute(
        pets: pets,
        health: health,
        feeding: feeding,
        activities: activities,
        now: now,
        dismissedUntil: dashboard.prefs.dismissedUntil,
      );

  CostReport get costs => CostReport.compute(
      pets: pets, health: health, feeding: feeding, reminders: reminders, now: now);

  MonthlyReport report(DateTime month) => MonthlyReport.compute(
        month: month,
        pets: pets,
        health: health,
        feeding: feeding,
        activities: activities,
        reminders: reminders,
        now: now,
      );
}
