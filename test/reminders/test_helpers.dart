import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/notifications/reminder_notifier.dart';
import 'package:smart_pet/models/pet_photo_store.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const rexId = 1;
const miaId = 2;

/// Photos simulées : chaque prise renvoie un nouveau chemin.
class FakePhotoStore implements PetPhotoStore {
  int taken = 0;
  bool cancel = false;
  final deleted = <String>[];

  @override
  Future<String?> pick({required bool camera}) async =>
      cancel ? null : '/data/pet_photos/photo_${++taken}.jpg';

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

/// Base SQLite en mémoire (sqflite_ffi) : à fermer en fin de test.
AppDatabase memoryDatabase() {
  sqfliteFfiInit();
  return AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
}

/// Base SQLite en mémoire sur le même isolate : utilisable dans les tests
/// d'écran (horloge simulée) sans `tester.runAsync`.
AppDatabase syncMemoryDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
      factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
}

/// GPS simulé : les positions sont envoyées par le test via [fixes].
class FakeLocationSource implements LocationSource {
  LocationIssue? issue;
  final fixes = StreamController<LocationFix>.broadcast(sync: true);
  int settingsOpened = 0;

  @override
  Future<void> ensureReady() async {
    if (issue != null) throw LocationException(issue!);
  }

  @override
  Stream<LocationFix> watch() => fixes.stream;

  @override
  Future<void> openSettings(LocationIssue issue) async => settingsOpened++;
}

/// Enregistre les synchronisations au lieu de programmer des notifications.
class FakeNotifier implements ReminderNotifier {
  List<Reminder> lastSync = const [];
  Map<int, String> lastPetNames = const {};
  int syncCount = 0;

  @override
  Future<void> syncAll(List<Reminder> reminders,
      {Map<int, String> petNames = const {}}) async {
    lastSync = reminders;
    lastPetNames = petNames;
    syncCount++;
  }

  int permissionRequests = 0;
  int testsShown = 0;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> showTest() async => testsShown++;
}

/// Horloge contrôlable.
class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Code du captcha dans les tests (`CaptchaGenerator.fixed`).
const testCaptcha = 'AB3CD';

/// Coche « Je ne suis pas un robot » et recopie le code de test.
Future<void> solveCaptcha(WidgetTester tester, [String code = testCaptcha]) async {
  await tester.ensureVisible(find.text('Je ne suis pas un robot'));
  await tester.tap(find.text('Je ne suis pas un robot'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Recopiez le code'), code);
  await tester.pumpAndSettle();
}
