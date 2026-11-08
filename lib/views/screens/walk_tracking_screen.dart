import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/walk_tracking_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/gps/walk_session_model.dart';
import '../activity_actions.dart';
import '../activity_style.dart';
import '../widgets/route_trace.dart';

/// Bonus GPS : enregistre le trajet d'une promenade. La distance, la durée
/// et le tracé sont ensuite repris par le formulaire d'activité.
class WalkTrackingScreen extends StatelessWidget {
  const WalkTrackingScreen({super.key});

  static const _color = AppColors.activity;

  Future<void> _finish(BuildContext context) async {
    final controller = context.read<WalkTrackingController>();
    final walk = controller.finish();
    await ActivityActions.saveWalk(context, walk);
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner la promenade ?'),
        content: const Text('Le trajet en cours ne sera pas enregistré.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuer')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WalkSessionModel>();
    final controller = context.read<WalkTrackingController>();
    final speed = session.speedKmh;

    return PopScope(
      canPop: !session.isActive,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave(context)) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Promenade GPS')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            RouteTrace(
              points: session.points,
              color: _color,
              height: 300,
              emptyText: session.status == WalkStatus.idle
                  ? 'Appuyez sur « Démarrer » pour enregistrer le trajet'
                  : 'En attente du signal GPS…',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _LiveValue('Durée', Units.stopwatch(session.elapsed)),
                _LiveValue('Distance', Units.km(session.distanceKm)),
                _LiveValue('Vitesse', speed == null ? '—' : Units.speed(speed)),
              ],
            ),
            const SizedBox(height: 12),
            _StatusLine(session: session),
            if (session.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.error!,
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600)),
                    if (session.issue != null)
                      TextButton.icon(
                        onPressed: controller.openSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Ouvrir les réglages'),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ..._buttons(context, session, controller),
            const SizedBox(height: 16),
            Text(
              'Gardez l\'application ouverte pendant la promenade. Le trajet '
              'est enregistré sur le téléphone, sans connexion Internet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, WalkSessionModel session,
      WalkTrackingController controller) {
    final big = FilledButton.styleFrom(
      backgroundColor: _color,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    switch (session.status) {
      case WalkStatus.idle:
        return [
          FilledButton.icon(
            style: big,
            onPressed: controller.start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Démarrer',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ];
      case WalkStatus.starting:
        return const [Center(child: CircularProgressIndicator(color: _color))];
      case WalkStatus.tracking:
      case WalkStatus.paused:
        final paused = session.status == WalkStatus.paused;
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: paused ? controller.resume : controller.pause,
                  icon: Icon(paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
                  label: Text(paused ? 'Reprendre' : 'Pause'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: big,
                  onPressed: () => _finish(context),
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('Terminer',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ];
      case WalkStatus.finished:
        return const [];
    }
  }
}

class _LiveValue extends StatelessWidget {
  const _LiveValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.session});

  final WalkSessionModel session;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = switch (session.status) {
      WalkStatus.idle => (Icons.gps_not_fixed_rounded, 'Prêt', Colors.grey),
      WalkStatus.starting =>
        (Icons.gps_not_fixed_rounded, 'Recherche du GPS…', AppColors.warning),
      WalkStatus.tracking => (
          Icons.gps_fixed_rounded,
          session.accuracyM == null
              ? 'Enregistrement en cours'
              : 'Enregistrement · précision ±${session.accuracyM!.round()} m',
          AppColors.success
        ),
      WalkStatus.paused => (Icons.pause_circle_outline, 'En pause', AppColors.warning),
      WalkStatus.finished => (Icons.check_circle_outline, 'Terminé', AppColors.success),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
