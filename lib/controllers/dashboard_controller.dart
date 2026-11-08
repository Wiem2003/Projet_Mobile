import '../models/dashboard/cross_alerts.dart';
import '../models/dashboard/dashboard_model.dart';
import '../models/dashboard/dashboard_prefs.dart';
import '../models/dashboard/monthly_report.dart';
import '../models/dashboard/pet_metrics.dart';
import '../models/dashboard/report_pdf.dart';
import '../models/dashboard/report_sharer.dart';

/// Controller du tableau de bord : masquer une alerte 30 jours, marquer le
/// rapport mensuel comme vu, partager le rapport (texte ou PDF).
class DashboardController {
  DashboardController({
    required this.model,
    required DashboardPrefsStore prefsStore,
    ReportSharer reportSharer = const SystemReportSharer(),
  })  : _store = prefsStore,
        _sharer = reportSharer;

  final DashboardModel model;
  final DashboardPrefsStore _store;
  final ReportSharer _sharer;

  Future<void> load() async {
    try {
      model.setPrefs((await _store.load()).cleaned(model.now));
    } on Exception {
      model.setPrefs(const DashboardPrefs());
    }
  }

  Future<void> _save(DashboardPrefs p) async {
    model.setPrefs(p);
    await _store.save(p);
  }

  /// « Ne plus afficher pendant 30 jours ».
  Future<void> dismiss(CrossAlert alert) => _save(model.prefs.copyWith(dismissedUntil: {
        ...model.prefs.dismissedUntil,
        alert.id: model.now.add(CrossAlerts.snooze),
      }));

  /// Remet toutes les alertes masquées.
  Future<void> restoreAlerts() => _save(model.prefs.copyWith(dismissedUntil: const {}));

  /// Le rapport du mois écoulé a été ouvert : la carte « prêt » disparaît.
  Future<void> markReportSeen() => _save(model.prefs
      .copyWith(lastReportSeen: DashboardPrefs.monthKey(MonthlyReport.previousMonth(model.now))));

  Future<void> shareText(MonthlyReport report) =>
      _share(() => _sharer.shareText(subject: report.title, text: report.toText()));

  Future<void> sharePdf(MonthlyReport report) => _share(() async {
        final bytes = await ReportPdf.build(report);
        final m = report.month;
        await _sharer.sharePdf(
          fileName: 'smart_pet_${m.year}_${m.month.toString().padLeft(2, '0')}.pdf',
          subject: report.title,
          bytes: bytes,
        );
      });

  Future<void> _share(Future<void> Function() action) async {
    model.setSharing(true);
    try {
      await action();
    } finally {
      model.setSharing(false);
    }
  }

  /// Libellé du mois pour les écrans (« octobre 2026 »).
  static String monthLabel(DateTime month) => PetMetrics.monthLabel(month);
}
