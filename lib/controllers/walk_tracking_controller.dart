import 'dart:async';

import '../models/gps/geo_point.dart';
import '../models/gps/location_source.dart';
import '../models/gps/walk_session_model.dart';

/// Controller de la promenade GPS : démarre / met en pause / termine le
/// suivi, filtre les mesures imprécises et met à jour le [WalkSessionModel].
class WalkTrackingController {
  WalkTrackingController({
    required LocationSource source,
    DateTime Function()? clock,
    Duration? tick = const Duration(seconds: 1),
  })  : _location = source,
        _clock = clock ?? DateTime.now,
        _tickEvery = tick;

  /// Mesures moins précises ignorées (mètres).
  static const maxAccuracyM = 35.0;

  /// Au-delà, le point est un saut GPS et non un déplacement réel.
  static const maxSpeedKmh = 45.0;

  final LocationSource _location;
  final DateTime Function() _clock;
  final Duration? _tickEvery;
  final model = WalkSessionModel();

  StreamSubscription<LocationFix>? _sub;
  Timer? _ticker;
  Duration _banked = Duration.zero;
  DateTime? _resumedAt;

  /// Après une pause, le premier point ne compte pas dans la distance.
  bool _newSegment = false;

  Duration get _elapsedNow =>
      _banked + (_resumedAt == null ? Duration.zero : _clock().difference(_resumedAt!));

  Future<void> start() async {
    if (model.status != WalkStatus.idle) return;
    model
      ..status = WalkStatus.starting
      ..error = null
      ..issue = null
      ..changed();
    try {
      await _location.ensureReady();
    } on LocationException catch (e) {
      model
        ..status = WalkStatus.idle
        ..issue = e.issue
        ..error = e.message
        ..changed();
      return;
    }
    final now = _clock();
    model
      ..startedAt = now
      ..status = WalkStatus.tracking;
    _resumedAt = now;
    _sub = _location.watch().listen(_onFix, onError: (Object e) {
      model
        ..error = 'Signal GPS perdu : $e'
        ..changed();
    });
    final every = _tickEvery;
    if (every != null) _ticker = Timer.periodic(every, (_) => _refresh());
    _refresh();
  }

  void _onFix(LocationFix fix) {
    if (model.status != WalkStatus.tracking) return;
    model
      ..accuracyM = fix.accuracyM
      ..error = null;
    if (fix.accuracyM > maxAccuracyM) return _refresh();
    final p = fix.point;
    final points = model.points;
    if (points.isNotEmpty && !_newSegment) {
      final last = points.last;
      final km = Geo.distanceKm(last, p);
      final ms = p.at != null && last.at != null
          ? p.at!.difference(last.at!).inMilliseconds
          : 0;
      if (ms > 0 && km / (ms / 3600000) > maxSpeedKmh) return _refresh();
      model.distanceKm += km;
    }
    _newSegment = false;
    points.add(p);
    _refresh();
  }

  void _refresh() {
    model
      ..elapsed = _elapsedNow
      ..changed();
  }

  void pause() {
    if (model.status != WalkStatus.tracking) return;
    _banked = _elapsedNow;
    _resumedAt = null;
    model.status = WalkStatus.paused;
    _refresh();
  }

  void resume() {
    if (model.status != WalkStatus.paused) return;
    _resumedAt = _clock();
    _newSegment = true;
    model.status = WalkStatus.tracking;
    _refresh();
  }

  /// Arrête le suivi et renvoie la promenade à enregistrer.
  WalkResult finish() {
    final elapsed = _elapsedNow;
    _stop();
    model
      ..elapsed = elapsed
      ..status = WalkStatus.finished
      ..changed();
    final minutes = (elapsed.inSeconds / 60).round();
    return (
      start: model.startedAt ?? _clock(),
      durationMin: minutes < 1 ? 1 : minutes,
      distanceKm: double.parse(model.distanceKm.toStringAsFixed(2)),
      route: List.unmodifiable(model.points),
    );
  }

  Future<void> openSettings() async {
    final issue = model.issue;
    if (issue != null) await _location.openSettings(issue);
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _resumedAt = null;
  }

  void dispose() {
    _stop();
    model.dispose();
  }
}
