import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/health_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/health_model.dart';
import '../../models/health_record.dart';
import '../../models/health_stats.dart';
import '../health_actions.dart';
import '../health_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/line_chart_card.dart';
import '../widgets/module_header.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/stat_card.dart';
import '../health_booklet_actions.dart';
import '../../controllers/health_booklet_controller.dart';

/// Écran principal du Module 2 — Santé & vaccinations : indicateurs,
/// évolution du poids, prochaines échéances et historique des soins.
class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  static const _color = AppColors.health;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<HealthModel>();
    final controller = context.read<HealthController>();
    final stats = model.stats;
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(height: top, color: AppColors.healthDeep),
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
                              _Indicators(model: model, stats: stats),
                              const SizedBox(height: 12),
                              _WeightChart(model: model, stats: stats),
                              if (model.upcoming.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _Upcoming(model: model),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _typeFilter(model, controller)),
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
          heroTag: 'new-health',
          backgroundColor: _color,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter un dossier',
              style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => HealthActions.openForm(context),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, HealthModel model,
      HealthController controller, HealthStats stats) {
    return ModuleHeader(
      title: 'Santé',
      subtitle: '${stats.recordCount} soin(s) · ${Units.money(stats.spending)}'
          ' · ${stats.period.label}',
      color: _color,
      deepColor: AppColors.healthDeep,
      pets: model.pets,
      selectedPetId: model.petFilter,
      onPetSelected: controller.setPetFilter,
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          tooltip: "Plus d'actions",
          onSelected: (v) => v == 1
              ? HealthBookletActions.shareFromHealth(context,
                  selectedPetId: model.petFilter, records: model.all)
              : HealthActions.seedDemo(context),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 1,
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: const Text('Carnet de santé PDF'),
                subtitle: Text(
                    (Provider.of<HealthBookletController?>(context, listen: false)?.aiAvailable ??
                            false)
                        ? 'Avec synthèse Gemini'
                        : 'Vaccins, soins et poids'),
              ),
            ),
            const PopupMenuItem(
              value: 0,
              child: ListTile(
                leading: Icon(Icons.auto_fix_high_rounded),
                title: Text('Charger des exemples'),
              ),
            ),
          ],
        ),
      ],
      bottom: HeaderChoice<HealthPeriod>(
        values: HealthPeriod.values,
        selected: model.period,
        labelOf: (p) => p.label,
        onChanged: controller.setPeriod,
        accent: AppColors.healthDeep,
      ),
    );
  }

  Widget _typeFilter(HealthModel model, HealthController controller) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Tous'),
              selected: model.typeFilter == null,
              onSelected: (_) => controller.setTypeFilter(null),
            ),
          ),
          for (final t in HealthType.values)
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

  List<Widget> _history(BuildContext context, HealthModel model) {
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
            icon: Icons.medical_services_rounded,
            color: _color,
            title: 'Aucun soin sur la période',
            message: 'Vaccins, traitements, consultations : ajoutez-les pour '
                'suivre les dépenses et le poids.',
            action: model.isEmpty
                ? OutlinedButton.icon(
                    onPressed: () => HealthActions.seedDemo(context),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Charger des exemples'),
                  )
                : null,
          ),
        ),
      ];
    }

    final months = <DateTime, List<HealthRecord>>{};
    for (final r in records) {
      (months[DateTime(r.date.year, r.date.month)] ??= []).add(r);
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.list(
          children: [
            for (final MapEntry(key: month, value: list) in months.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Row(
                  children: [
                    Text(Fmt.month(month),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      Units.money(list.fold(0.0, (s, r) => s + r.cost)),
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
                  child: HealthRecordCard(record: r),
                ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Indicators extends StatelessWidget {
  const _Indicators({required this.model, required this.stats});

  final HealthModel model;
  final HealthStats stats;

  @override
  Widget build(BuildContext context) {
    final pet = model.petOf(model.weightPetId);
    final change = stats.weightChangeKg;
    final average = stats.averageWeight;
    final noPet = pet == null ? 'choisissez un animal' : null;
    return StatGrid(children: [
      StatCard(
        icon: Icons.medical_services_rounded,
        label: 'Consultations',
        value: '${stats.consultations}',
        caption: '${stats.recordCount} soin(s) au total · ${stats.period.label}',
        color: AppColors.activity,
      ),
      StatCard(
        icon: Icons.payments_rounded,
        label: 'Dépenses médicales',
        value: Units.money(stats.spending),
        caption: stats.period == HealthPeriod.all
            ? 'depuis le début'
            : 'sur ${stats.period.label}',
        color: const Color(0xFFB45309),
      ),
      StatCard(
        icon: Icons.monitor_weight_outlined,
        label: 'Poids moyen',
        value: average == null ? '—' : Units.kg(average),
        caption: noPet ??
            '${pet!.name} · ${stats.weights.length} pesée(s)',
        color: const Color(0xFF0D9488),
      ),
      StatCard(
        icon: Icons.insights_rounded,
        label: 'Évolution du poids',
        value: change == null
            ? '—'
            : '${change > 0 ? '+' : ''}${Units.kg(change)}',
        caption: noPet ??
            (change == null
                ? 'il faut au moins 2 pesées'
                : '${Units.kg(stats.weights.first.kg)} → ${Units.kg(stats.lastWeight!)}'),
        trend: stats.weightChangeRatio,
        upIsGood: null,
        color: AppColors.health,
      ),
    ]);
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.model, required this.stats});

  final HealthModel model;
  final HealthStats stats;

  @override
  Widget build(BuildContext context) {
    final pet = model.petOf(model.weightPetId);
    if (pet == null || stats.weights.length < 2) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.show_chart_rounded, color: AppColors.health),
          title: const Text('Évolution du poids'),
          subtitle: Text(pet == null
              ? 'Choisissez un animal en haut de l\'écran pour voir sa courbe.'
              : 'Indiquez le poids lors d\'au moins 2 soins pour voir la courbe.'),
        ),
      );
    }
    return LineChartCard(
      title: 'Évolution du poids de ${pet.name} (kg)',
      subtitle: stats.period.label,
      color: AppColors.health,
      valueLabel: (v) => Units.number(v),
      points: [
        for (final w in stats.weights) LinePoint(Fmt.dayMonth(w.date), w.kg),
      ],
    );
  }
}

class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.model});

  final HealthModel model;

  @override
  Widget build(BuildContext context) {
    final now = model.now;
    final today = DateTime(now.year, now.month, now.day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text('Prochaines échéances',
                  style: TextStyle(
                      color: AppColors.health,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            for (final r in model.upcoming.take(3))
              ListTile(
                dense: true,
                leading: Icon(r.type.icon, color: r.type.color),
                title: Text(r.reminderTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${model.petOf(r.petId)?.name ?? 'Animal'} · ${Fmt.medium(r.nextDue!)}'),
                trailing: Text(
                  _inDays(r.nextDue!.difference(today).inDays),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _inDays(int days) => switch (days) {
        0 => 'Aujourd\'hui',
        1 => 'Demain',
        _ => 'Dans $days j',
      };
}

/// Une ligne de l'historique : tap pour modifier, menu pour supprimer.
class HealthRecordCard extends StatelessWidget {
  const HealthRecordCard({super.key, required this.record});

  final HealthRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final pet = context.read<HealthModel>().petOf(r.petId);
    final scheme = Theme.of(context).colorScheme;
    final details = [
      Fmt.medium(r.date),
      ?r.vet,
      if (r.weightKg != null) Units.kg(r.weightKg!),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => HealthActions.openForm(context, record: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: r.type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(r.type.icon, color: r.type.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.medication == null
                          ? r.type.label
                          : '${r.type.label} · ${r.medication}',
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
                          child: Text(details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 13)),
                        ),
                      ],
                    ),
                    if (r.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(r.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    if (r.nextDue != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.event_repeat_rounded,
                                size: 15, color: AppColors.reminder),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Prochaine échéance : ${Fmt.medium(r.nextDue!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.reminder),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(Units.money(r.cost),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              PopupMenuButton<bool>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (edit) => edit
                    ? HealthActions.openForm(context, record: r)
                    : HealthActions.delete(context, r),
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
