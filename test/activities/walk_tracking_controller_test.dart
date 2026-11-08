import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/walk_tracking_controller.dart';
import 'package:smart_pet/models/gps/geo_point.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/gps/walk_session_model.dart';

import '../reminders/test_helpers.dart';

void main() {
  final start = DateTime(2026, 11, 3, 9);
  late FakeClock clock;
  late FakeLocationSource source;
  late WalkTrackingController walk;

  setUp(() {
    clock = FakeClock(start);
    source = FakeLocationSource();
    walk = WalkTrackingController(source: source, clock: clock.call, tick: null);
  });
  tearDown(() {
    walk.dispose();
    source.fixes.close();
  });

  /// Point sur le méridien de Tunis ; 0,001° de latitude ≈ 111 m.
  void gps(double lat, {required int sec, double accuracy = 5}) =>
      source.fixes.add(LocationFix(
        GeoPoint(lat, 10.18, start.add(Duration(seconds: sec))),
        accuracyM: accuracy,
      ));

  void wait(Duration d) => clock.now = clock.now.add(d);

  test('autorisation refusée : message et accès aux réglages', () async {
    source.issue = LocationIssue.denied;
    await walk.start();
    expect(walk.model.status, WalkStatus.idle);
    expect(walk.model.issue, LocationIssue.denied);
    expect(walk.model.error, contains('position'));
    await walk.openSettings();
    expect(source.settingsOpened, 1);
  });

  test('distance, filtrage des mesures, pause et fin', () async {
    await walk.start();
    expect(walk.model.status, WalkStatus.tracking);
    expect(walk.model.startedAt, start);

    gps(36.800, sec: 0);
    wait(const Duration(minutes: 5));
    gps(36.803, sec: 300);
    expect(walk.model.distanceKm, closeTo(0.3336, 0.001));
    expect(walk.model.elapsed, const Duration(minutes: 5));

    gps(36.900, sec: 305); // Saut de 11 km en 5 s : ignoré.
    gps(36.804, sec: 310, accuracy: 80); // Trop imprécis : ignoré.
    expect(walk.model.points, hasLength(2));
    expect(walk.model.accuracyM, 80);

    walk.pause();
    wait(const Duration(minutes: 10));
    gps(36.810, sec: 900); // En pause : ignoré.
    expect(walk.model.points, hasLength(2));
    expect(walk.model.elapsed, const Duration(minutes: 5));

    walk.resume();
    gps(36.810, sec: 910); // Nouveau segment : pas de distance depuis la pause.
    expect(walk.model.distanceKm, closeTo(0.3336, 0.001));
    wait(const Duration(minutes: 5));
    gps(36.811, sec: 1210);
    expect(walk.model.distanceKm, closeTo(0.4448, 0.001));
    expect(walk.model.speedKmh, closeTo(2.67, 0.01));

    final result = walk.finish();
    expect(walk.model.status, WalkStatus.finished);
    expect(result.start, start);
    expect(result.durationMin, 10, reason: 'la pause ne compte pas');
    expect(result.distanceKm, 0.44);
    expect(result.route, hasLength(4));

    gps(36.9, sec: 1300); // Après la fin : ignoré.
    expect(walk.model.points, hasLength(4));
  });

  test('promenade très courte : au moins 1 minute', () async {
    await walk.start();
    wait(const Duration(seconds: 20));
    expect(walk.finish().durationMin, 1);
  });
}
