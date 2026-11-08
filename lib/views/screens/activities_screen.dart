import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/activities_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activities_model.dart';
import '../../models/activity.dart';
import '../../models/activity_stats.dart';
import '../activity_actions.dart';
import '../activity_style.dart';
import '../sheets/activity_detail_sheet.dart';
import '../widgets/activity_insights_section.dart';
import '../widgets/bar_chart_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/module_header.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/stat_card.dart';

/// Écran principal du Module 4 — Activités : indicateurs, distance
/// hebdomadaire, historique et accès à la promenade GPS.
class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  static const _color = AppColors.activity;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ActivitiesModel>();
    final controller = context.read<ActivitiesController>();
    final stats = model.stats;
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(height: top, color: AppColors.activityDeep),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: RefreshIndicator(
                  color: _color,
                  onRefresh: controller.load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                          child: _header(context, model, controller, stats)),
                      if (model.error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(model.error!,
                                style: const TextStyle(color: AppColors.danger)),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              _Indicators(stats: stats),
                              const SizedBox(height: 12),
                              BarChartCard(
                                title: 'Distance hebdomadaire (km)',
                                subtitle: '7 jours glissants',
                                color: _color,
                                valueLabel: (v) => Units.number(v),
                                bars: [
                                  for (final (i, w) in stats.weeks.indexed)
                                    BarDatum(
                                      i == stats.weeks.length - 1
                                          ? 'Cette sem.'
                                          : Fmt.dayMonth(w.start),
                                      w.distanceKm,
                                      highlight: i == stats.weeks.length - 1,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const ActivityInsightsSection(),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _typeFilter(model, controller)),
                      ..._history(context, model),
                      const SliverToBoxAdapter(child: SizedBox(height: 140)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'gps-walk',
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor: _color,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Promenade GPS',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => ActivityActions.startWalk(context),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'new-activity',
              backgroundColor: _color,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle activité',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => ActivityActions.openForm(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ActivitiesModel model,
      ActivitiesController controller, ActivityStats stats) {
    return ModuleHeader(
      title: 'Activités',
      subtitle: '${stats.count} activité(s) · ${Units.minutes(stats.totalMinutes)}'
          ' · ${Units.kcal(stats.totalCalories)}',
      color: _color,
      deepColor: AppColors.activityDeep,
      pets: model.pets,
      selectedPetId: model.petFilter,
      onPetSelected: controller.setPetFilter,
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (_) => ActivityActions.seedDemo(context),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 0,
              child: ListTile(
                leading: Icon(Icons.auto_fix_high_rounded),
                title: Text('Charger des exemples'),
              ),
            ),
          ],
        ),
      ],
      bottom: HeaderChoice<ActivityPeriod>(
        values: ActivityPeriod.values,
        selected: model.period,
        labelOf: (p) => p.label,
        onChanged: controller.setPeriod,
        accent: AppColors.activityDeep,
      ),
    );
  }

  Widget _typeFilter(ActivitiesModel model, ActivitiesController controller) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Toutes'),
              selected: model.typeFilter == null,
              onSelected: (_) => controller.setTypeFilter(null),
            ),
          ),
          for (final t in ActivityType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(t.icon, size: 18, color: t.color),
                label: Text(t.label),
                selected: model.typeFilter == t,
                selectedColor: t.color.withValues(alpha: 0.16),
                onSelected: (_) =>
                    controller.setTypeFilter(model.typeFilter == t ? null : t),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _history(BuildContext context, ActivitiesModel model) {
    if (model.loading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: _color)),
          ),
        ),
      ];
    }
    final activities = model.visible;
    if (activities.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.directions_run_rounded,
            color: _color,
            title: 'Aucune activité sur la période',
            message: 'Ajoutez une activité ou enregistrez une promenade '
                'avec le GPS.',
            action: model.isEmpty
                ? OutlinedButton.icon(
                    onPressed: () => ActivityActions.seedDemo(context),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Charger des exemples'),
                  )
                : null,
          ),
        ),
      ];
    }

    final days = <DateTime, List<Activity>>{};
    for (final a in activities) {
      (days[DateTime(a.date.year, a.date.month, a.date.day)] ??= []).add(a);
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.list(
          children: [
            for (final MapEntry(key: day, value: list) in days.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Row(
                  children: [
                    Text(Fmt.medium(day),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      Units.minutes(list.fold(0, (s, a) => s + a.durationMin)),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ActivityCard(activity: a),
                ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Indicators extends StatelessWidget {
  const _Indicators({required this.stats});

  final ActivityStats stats;

  @override
  Widget build(BuildContext context) {
    final minutesChange = stats.minutesChange;
    final lastWeek = stats.lastWeek;
    return StatGrid(children: [
      StatCard(
        icon: Icons.straighten_rounded,
        label: 'Distance hebdomadaire',
        value: Units.km(stats.weeklyDistanceKm),
        caption: '7 derniers jours',
        trend: stats.distanceChange,
        color: AppColors.activity,
      ),
      StatCard(
        icon: Icons.timer_outlined,
        label: 'Durée moyenne',
        value: Units.minutes(stats.averageDurationMin),
        caption: 'par activité · ${stats.period.label}',
        color: const Color(0xFF0D9488),
      ),
      StatCard(
        icon: Icons.format_list_numbered_rounded,
        label: 'Nombre d\'activités',
        value: '${stats.count}',
        caption: stats.period == ActivityPeriod.all
            ? 'depuis le début'
            : 'sur ${stats.period.label}',
        color: const Color(0xFFF59E0B),
      ),
      StatCard(
        icon: Icons.insights_rounded,
        label: 'Évolution de l\'activité',
        value: minutesChange == null ? '—' : Units.percent(minutesChange),
        caption: 'Cette semaine ${Units.minutes(stats.thisWeek.minutes)}'
            ' · préc. ${Units.minutes(lastWeek?.minutes ?? 0)}',
        trend: minutesChange,
        color: const Color(0xFF7C3AED),
      ),
    ]);
  }
}

/// Une activité de l'historique : tap pour ouvrir le détail.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final pet = context.read<ActivitiesModel>().petOf(a.petId);
    final scheme = Theme.of(context).colorScheme;
    final details = [
      Units.minutes(a.durationMin),
      if (a.distanceKm > 0) Units.km(a.distanceKm),
      Units.kcal(a.calories),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showActivityDetailSheet(context, a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: a.type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(a.type.icon, color: a.type.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(a.type.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (a.hasRoute) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.activity.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('GPS',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.activity)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (pet != null) PetAvatar(pet: pet, size: 24),
                  const SizedBox(height: 4),
                  Text(Fmt.time(a.date),
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
