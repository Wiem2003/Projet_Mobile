import 'package:flutter/foundation.dart';

import 'cross_alerts.dart';
import 'dashboard_prefs.dart';
import 'monthly_report.dart';

/// État du tableau de bord : alertes masquées et rapport mensuel déjà vu.
///
/// Les chiffres (indice, alertes, coûts, rapport) sont calculés à la
/// demande à partir des Models des cinq modules.
class DashboardModel extends ChangeNotifier {
  DashboardModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DashboardPrefs _prefs = const DashboardPrefs();
  bool _sharing = false;

  DateTime get now => _clock();
  DashboardPrefs get prefs => _prefs;
  bool get sharing => _sharing;

  /// Le rapport du mois écoulé n'a pas encore été ouvert (affiché à partir
  /// du 1er du mois).
  bool get reportReady =>
      _prefs.lastReportSeen != DashboardPrefs.monthKey(MonthlyReport.previousMonth(now));

  /// Retire les alertes masquées par l'utilisateur.
  List<CrossAlert> visible(List<CrossAlert> alerts) => [
        for (final a in alerts)
          if (!(_prefs.dismissedUntil[a.id]?.isAfter(now) ?? false)) a,
      ];

  void setPrefs(DashboardPrefs p) {
    _prefs = p;
    notifyListeners();
  }

  void setSharing(bool v) {
    _sharing = v;
    notifyListeners();
  }
}
