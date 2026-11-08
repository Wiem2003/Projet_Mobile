import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/feeding_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/feeding_model.dart';
import '../../models/feeding_record.dart';
import '../../models/feeding_stats.dart';
import '../feeding_actions.dart';
import '../feeding_style.dart';
import '../widgets/bar_chart_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/feeding_plan_cards.dart';
import '../widgets/module_header.dart';
import '../widgets/nutrition_section.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/stat_card.dart';

/// Écran principal du Module 3 — Alimentation : indicateurs du mois,
/// évolution des dépenses et historique des repas.
class FeedingScreen extends StatelessWidget {
  const FeedingScreen({super.key});

  static const _color = AppColors.feeding;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FeedingModel>();
    final controller = context.read<FeedingController>();
    final stats = model.stats;
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(height: top, color: AppColors.feedingDeep),
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
                              const FoodBudgetCard(),
                              const SizedBox(height: 12),
                              BarChartCard(
                                title: 'Dépenses mensuelles (${Units.currency})',
                                subtitle: '6 derniers mois',
                                color: _color,
                                valueLabel: (v) =>
                                    Units.number(v, decimals: v >= 100 ? 0 : 1),
                                bars: [
                                  for (final m in stats.spendingByMonth)
                                    BarDatum(
                                      Fmt.monthShort(m.month),
                                      m.value,
                                      highlight: m.month == stats.month,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const FoodStockCard(),
                              const SizedBox(height: 12),
                              const NutritionSection(),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
                          child: Text(
                            'Historique — ${Fmt.month(model.month)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      ..._history(context, model),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new-feeding',
          backgroundColor: _color,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter un repas',
              style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => FeedingActions.openForm(context),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, FeedingModel model,
      FeedingController controller, FeedingStats stats) {
    return ModuleHeader(
      title: 'Alimentation',
      subtitle: stats.recordCount == 0
          ? 'Aucun repas en ${Fmt.month(model.month).toLowerCase()}'
          : '${stats.recordCount} enregistrement(s) · ${stats.meals} repas',
      color: _color,
      deepColor: AppColors.feedingDeep,
      pets: model.pets,
      selectedPetId: model.petFilter,
      onPetSelected: controller.setPetFilter,
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (_) => FeedingActions.seedDemo(context),
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
      bottom: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mois précédent',
              color: Colors.white,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: controller.previousMonth,
            ),
            Expanded(
              child: Text(
                Fmt.month(model.month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ),
            IconButton(
              tooltip: 'Mois suivant',
              color: Colors.white,
              disabledColor: Colors.white38,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: model.isCurrentMonth ? null : controller.nextMonth,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _history(BuildContext context, FeedingModel model) {
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
    final records = model.history;
    if (records.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.restaurant_rounded,
            color: _color,
            title: 'Aucun repas ce mois-ci',
            message: 'Ajoutez les repas de vos animaux pour suivre les '
                'quantités et les dépenses.',
            action: model.isEmpty
                ? OutlinedButton.icon(
                    onPressed: () => FeedingActions.seedDemo(context),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Charger des exemples'),
                  )
                : null,
          ),
        ),
      ];
    }

    // Regroupement par jour.
    final days = <DateTime, List<FeedingRecord>>{};
    for (final r in records) {
      (days[r.date] ??= []).add(r);
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
                      Units.money(list.fold(0.0, (s, r) => s + r.price)),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FeedingRecordCard(record: r),
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

  final FeedingStats stats;

  @override
  Widget build(BuildContext context) {
    final change = stats.spendingChange;
    return StatGrid(children: [
      StatCard(
        icon: Icons.scale_rounded,
        label: 'Quantité consommée',
        value: Units.grams(stats.quantityG),
        caption: 'sur le mois',
        color: AppColors.feeding,
      ),
      StatCard(
        icon: Icons.payments_rounded,
        label: 'Dépense alimentaire',
        value: Units.money(stats.spending),
        caption: '${Units.money(stats.dailyAverageSpending)} / jour',
        color: const Color(0xFFB45309),
      ),
      StatCard(
        icon: Icons.today_rounded,
        label: 'Moyenne quotidienne',
        value: '${Units.grams(stats.dailyAverageG)} / j',
        caption: 'sur ${stats.days} jour(s)',
        color: const Color(0xFF0D9488),
      ),
      StatCard(
        icon: Icons.insights_rounded,
        label: 'Évolution des dépenses',
        value: change == null ? '—' : Units.percent(change),
        caption: switch ((change, stats.comparedDays)) {
          (null, null) => 'pas de dépense le mois précédent',
          (null, final d?) => 'pas de dépense du 1er au $d du mois précédent',
          (_, null) => 'vs ${Units.money(stats.previousSamePeriod)} le mois précédent',
          (_, final d?) => 'vs ${Units.money(stats.previousSamePeriod)} du 1er au $d '
              '${Fmt.monthShort(DateTime(stats.month.year, stats.month.month - 1)).toLowerCase()}',
        },
        trend: change,
        upIsGood: false,
        color: const Color(0xFF7C3AED),
      ),
    ]);
  }
}

/// Une ligne de l'historique : tap pour modifier, menu pour supprimer.
class FeedingRecordCard extends StatelessWidget {
  const FeedingRecordCard({super.key, required this.record});

  final FeedingRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final pet = context.read<FeedingModel>().petOf(r.petId);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => FeedingActions.openForm(context, record: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: r.foodType.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(r.foodType.icon, color: r.foodType.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.brand == null
                          ? r.foodType.label
                          : '${r.foodType.label} · ${r.brand}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (pet != null) ...[
                          PetAvatar(pet: pet, size: 18),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            '${pet?.name ?? 'Animal'} · ${Units.grams(r.quantityG)} · '
                            '${r.meals} repas',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(Units.money(r.price),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              PopupMenuButton<bool>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (edit) => edit
                    ? FeedingActions.openForm(context, record: r)
                    : FeedingActions.delete(context, r),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: true,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Modifier'),
                    ),
                  ),
                  PopupMenuItem(
                    value: false,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger),
                      title: Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
