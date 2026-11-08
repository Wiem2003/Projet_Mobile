import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../meal_schedule.dart';
import '../reminder.dart';
import '../reminder_calculator.dart';
import '../reminder_rules.dart';
import 'achievement_notifier.dart';
import 'reminder_notifier.dart';

/// Notifications locales via flutter_local_notifications.
///
/// Chaque rappel produit une notification par délai d'alerte futur ; leur
/// identifiant est dérivé de l'id du rappel ([notificationIdFor]).
class LocalNotificationService
    implements ReminderNotifier, MealNotifier, AchievementNotifier {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'smart_pet_reminders';
  static const _channelName = 'Rappels Smart Pet';
  static const _categoryId = 'smart_pet_reminder';
  static const _actionDone = 'done';
  static const _actionPostpone = 'postpone';
  static const _testNotificationId = 0;

  /// Nouveau record (remplace le précédent).
  static const _achievementId = 1;

  /// Repas : identifiants réservés, au-delà de ceux des rappels
  /// (`id × 16 + créneau`).
  static const mealIdBase = 1900000000;
  static bool isMealId(int id) => id >= mealIdBase;
  static int mealIdFor(int petId, int index) => mealIdBase + petId * MealSchedule.maxPerPet + index;

  final FlutterLocalNotificationsPlugin _plugin;
  final _events = StreamController<ReminderNotificationEvent>.broadcast();
  bool _ready = false;

  /// Notification qui a lancé l'application (app fermée), à traiter une fois.
  ReminderNotificationEvent? launchEvent;

  Stream<ReminderNotificationEvent> get events => _events.stream;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supported || _ready) return;

    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(_categoryId, actions: [
          DarwinNotificationAction.plain(_actionDone, 'Marquer fait',
              options: {DarwinNotificationActionOption.foreground}),
          DarwinNotificationAction.plain(_actionPostpone, 'Reporter',
              options: {DarwinNotificationActionOption.foreground}),
        ]),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        final event = _toEvent(response);
        if (event != null) _events.add(event);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) launchEvent = _toEvent(response);
    }
    _ready = true;
  }

  /// À appeler suite à une action de l'utilisateur (Android 13+ / iOS).
  @override
  Future<bool> requestPermissions() async {
    if (!_supported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<void> syncAll(List<Reminder> reminders,
      {Map<int, String> petNames = const {}}) async {
    if (!_ready) return;
    final now = DateTime.now();
    final wanted = <int>{};

    for (final r in reminders) {
      if (r.id == null) continue;
      for (final alert in ReminderCalculator.pendingAlerts(r, now)) {
        final id = notificationIdFor(r.id!, alert.offset);
        wanted.add(id);
        // Même id => la notification existante est remplacée.
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(alert.at, tz.local),
          notificationDetails: _details(),
          // Inexact : suffisant pour des rappels à la journée et ne demande
          // pas la permission SCHEDULE_EXACT_ALARM.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: _title(r, petNames[r.petId]),
          body: _body(r, alert.at),
          payload: '${r.id}',
        );
      }
      // Relances J+1 et J+3 si le rappel n'est toujours pas fait.
      for (final relance in ReminderRules.pendingRelances(r, now)) {
        final id = r.id! * 16 + relance.slot;
        wanted.add(id);
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(relance.at, tz.local),
          notificationDetails: _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: [
            '⚠️ ${relance.level.label} : ${r.title}',
            ?petNames[r.petId],
          ].join(' · '),
          body: 'Toujours pas fait : ${_body(r, relance.at)}',
          payload: '${r.id}',
        );
      }
    }

    // Rappels supprimés, faits, reportés ou alertes retirées.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.id != _testNotificationId &&
          pending.id != _achievementId &&
          !isMealId(pending.id) &&
          !wanted.contains(pending.id)) {
        await _plugin.cancel(id: pending.id);
      }
    }
  }

  /// Repas : une notification chaque jour à l'heure choisie.
  @override
  Future<void> syncMeals(List<MealAlarm> alarms) async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    final wanted = <int>{};
    final perPet = <int, int>{};
    for (final a in alarms) {
      final index = perPet[a.petId] = (perPet[a.petId] ?? -1) + 1;
      if (index >= MealSchedule.maxPerPet) continue;
      final id = mealIdFor(a.petId, index);
      wanted.add(id);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, a.time.hour, a.time.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: at,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        title: '🍽️ Repas de ${a.petName}, ${a.time.label}',
        body: "C'est l'heure du repas de ${a.petName}.",
        payload: 'meal:${a.petId}',
      );
    }
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (isMealId(pending.id) && !wanted.contains(pending.id)) {
        await _plugin.cancel(id: pending.id);
      }
    }
  }

  @override
  Future<void> showAchievement({required String title, required String body}) async {
    if (!_ready) return;
    await _plugin.show(
      id: _achievementId,
      title: title,
      body: body,
      notificationDetails: _details(),
    );
  }

  /// Notification immédiate pour vérifier la configuration.
  @override
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: _testNotificationId,
      title: 'Smart Pet 🐾',
      body: 'Les notifications de rappel fonctionnent !',
      notificationDetails: _details(),
    );
  }

  Future<int> pendingCount() async {
    if (!_ready) return 0;
    return (await _plugin.pendingNotificationRequests()).length;
  }

  String _title(Reminder r, String? petName) =>
      petName == null ? '🔔 ${r.title}' : '🔔 ${r.title} · $petName';

  String _body(Reminder r, DateTime alertAt) {
    final when = DateFormat('EEEE d MMMM \'à\' HH:mm', 'fr_FR').format(r.dueDate);
    final rel = ReminderCalculator.relativeSentence(r.dueDate, alertAt);
    final head = rel == 'aujourd\'hui' ? 'C\'est aujourd\'hui' : 'Échéance $rel';
    return '$head — $when';
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Vaccins, vermifuges, rendez-vous et achats à ne pas oublier',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF7C3AED),
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(_actionDone, 'Marquer fait',
                showsUserInterface: true),
            AndroidNotificationAction(_actionPostpone, 'Reporter',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _categoryId),
      );

  ReminderNotificationEvent? _toEvent(NotificationResponse response) {
    final id = int.tryParse(response.payload ?? '');
    if (id == null) return null;
    final action = switch (response.actionId) {
      _actionDone => NotificationAction.done,
      _actionPostpone => NotificationAction.postpone,
      _ => NotificationAction.open,
    };
    return ReminderNotificationEvent(id, action);
  }

  void dispose() => _events.close();
}
