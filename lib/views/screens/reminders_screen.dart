import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../controllers/reminders_controller.dart';
import '../../models/reminder.dart';
import '../../models/notifications/reminder_notifier.dart';
import '../../models/reminder_exception.dart';
import '../../models/reminder_repository.dart';
import '../../models/reminders_model.dart';
import '../reminder_actions.dart';
import '../reminder_style.dart';
import '../sheets/reminder_detail_sheet.dart';
import '../widgets/day_strip.dart';
import '../widgets/empty_state.dart';
import '../widgets/reminder_card.dart';
import '../widgets/reminders_header.dart';
import '../widgets/segment_tabs.dart';
import '../widgets/type_filter_bar.dart';
import 'reminder_assistant_screen.dart';
import 'reminder_compliance_screen.dart';
import 'reminder_planning_screen.dart';

/// Écran principal du Module 5 — Rappels & alertes.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

enum _MenuAction { demo, planning, compliance, simulate, testNotification, permissions }

class _RemindersScreenState extends State<RemindersScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  late final RemindersController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<RemindersController>();
    _controller.intent.addListener(_onIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onIntent());
  }

  @override
  void dispose() {
    _controller.intent.removeListener(_onIntent);
    _search.dispose();
    super.dispose();
  }

  /// Ouverture depuis une notification (tap, « Reporter » ou « Fait »).
  void _onIntent() {
    final intent = _controller.intent.value;
    if (intent == null || !mounted) return;
    _controller.intent.value = null;
    switch (intent.action) {
      case NotificationAction.open:
        showReminderDetailSheet(context, intent.reminder);
      case NotificationAction.postpone:
        ReminderActions.postpone(context, intent.reminder);
      case NotificationAction.done:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('« ${intent.reminder.title} » marqué comme fait ✓'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RemindersModel>();
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            // Barre d'état violette fixe : le contenu défile dessous.
            Container(height: top, color: AppColors.reminderDeep),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: RefreshIndicator(
                  color: AppColors.reminder,
                  onRefresh: _controller.load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _header(model)),
                      if (_searching)
                        SliverToBoxAdapter(child: _searchField(model)),
                      SliverToBoxAdapter(child: _calendar(model)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TypeFilterBar(
                            selected: model.typeFilter,
                            onChanged: _controller.setTypeFilter,
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabsHeaderDelegate(
                          child: SegmentTabs(
                            current: model.tab,
                            counts: {
                              for (final t in ReminderTab.values)
                                t: model.countFor(t),
                            },
                            onChanged: _controller.setTab,
                          ),
                        ),
                      ),
                      if (model.hasActiveFilters)
                        SliverToBoxAdapter(child: _activeFilters(model)),
                      ..._content(model),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
            FloatingActionButton.small(
              heroTag: 'assistant',
              tooltip: 'Assistant',
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor: AppColors.reminder,
              onPressed: () => ReminderAssistantScreen.open(context),
              child: const Icon(Icons.smart_toy_outlined),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'new-reminder',
              backgroundColor: AppColors.reminder,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text('Nouveau rappel',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => ReminderActions.openForm(context),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Sections

  Widget _header(RemindersModel model) {
    return RemindersHeader(
      stats: model.stats,
      pets: model.pets,
      selectedPetId: model.petFilter,
      onPetSelected: _controller.setPetFilter,
      onOverdueTap: () => _controller.setTab(ReminderTab.overdue),
      actions: [
        IconButton(
          tooltip: 'Rechercher',
          icon: Icon(_searching ? Icons.search_off_rounded : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) {
              _search.clear();
              _controller.setQuery('');
            }
          }),
        ),
        PopupMenuButton<_MenuAction>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: _onMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _MenuAction.demo,
              child: ListTile(
                leading: Icon(Icons.auto_fix_high_rounded),
                title: Text('Charger des exemples'),
              ),
            ),
            PopupMenuItem(
              value: _MenuAction.planning,
              child: ListTile(
                leading: Icon(Icons.savings_outlined),
                title: Text('Planification & budget'),
              ),
            ),
            PopupMenuItem(
              value: _MenuAction.compliance,
              child: ListTile(
                leading: Icon(Icons.insights_rounded),
                title: Text("Statistiques d'observance"),
              ),
            ),
            PopupMenuItem(
              value: _MenuAction.simulate,
              child: ListTile(
                leading: Icon(Icons.medical_services_outlined),
                title: Text('Simuler une échéance Santé'),
              ),
            ),
            PopupMenuItem(
              value: _MenuAction.testNotification,
              child: ListTile(
                leading: Icon(Icons.notifications_outlined),
                title: Text('Tester une notification'),
              ),
            ),
            PopupMenuItem(
              value: _MenuAction.permissions,
              child: ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Autoriser les notifications'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _searchField(RemindersModel model) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: TextField(
        controller: _search,
        inputFormatters: [LengthLimitingTextInputFormatter(60)],
        autofocus: true,
        onChanged: _controller.setQuery,
        decoration: InputDecoration(
          hintText: 'Rechercher un rappel, un animal, une note…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _controller.setQuery('');
                  },
                ),
        ),
      ),
    );
  }

  Widget _calendar(RemindersModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              Text('Calendrier',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(Fmt.long(model.now).split(' ').take(3).join(' '),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        DayStrip(
          today: model.now,
          selected: model.dayFilter,
          typesOnDay: model.typesOnDay,
          onSelected: _controller.setDayFilter,
        ),
      ],
    );
  }

  Widget _activeFilters(RemindersModel model) {
    final parts = [
      if (model.dayFilter != null) Fmt.medium(model.dayFilter!),
      if (model.typeFilter != null) model.typeFilter!.label,
      if (model.query.isNotEmpty) '« ${model.query} »',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined,
              size: 18, color: AppColors.reminder),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Filtré : ${parts.join(' · ')}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              _search.clear();
              _controller.clearFilters();
            },
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(RemindersModel model) {
    if (model.loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.reminder),
          ),
        ),
      ];
    }
    if (model.error != null && model.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Erreur',
            message: model.error!,
            action: FilledButton(
                onPressed: _controller.load, child: const Text('Réessayer')),
          ),
        ),
      ];
    }
    return [
      // Données déjà chargées mais rechargement en échec.
      if (model.error != null)
        SliverToBoxAdapter(
          child: _InfoStrip(
            text: '${model.error!} Affichage des dernières données chargées.',
          ),
        ),
      ..._tabContent(model),
    ];
  }

  List<Widget> _tabContent(RemindersModel model) {
    switch (model.tab) {
      case ReminderTab.upcoming:
        final sections = model.upcomingSections;
        if (sections.isEmpty) {
          return [_empty(model, ReminderTab.upcoming)];
        }
        final alert = _planningAlert(model);
        return [
          if (alert != null)
            SliverToBoxAdapter(
              child: _PlanningAlert(
                text: alert,
                onTap: () => ReminderPlanningScreen.open(context),
              ),
            ),
          for (final (bucket, items) in sections) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(label: bucket.label, count: items.length),
            ),
            _list(model, items),
          ],
        ];
      case ReminderTab.overdue:
        final items = model.overdue;
        if (items.isEmpty) return [_empty(model, ReminderTab.overdue)];
        final critical = model.criticalCount;
        return [
          SliverToBoxAdapter(
            child: _InfoStrip(
              text: 'Ces échéances sont dépassées : marquez-les comme faites '
                  '(glisser à droite) ou reportez-les (glisser à gauche). '
                  'Triées par urgence (gravité du soin × jours de retard)'
                  '${critical == 0 ? '.' : ' — $critical critique${critical > 1 ? 's' : ''} '
                      '(plus de 3 jours de retard).'}',
            ),
          ),
          _list(model, items),
        ];
      case ReminderTab.done:
        final items = model.done;
        if (items.isEmpty) return [_empty(model, ReminderTab.done)];
        final rate = model.compliance.overall.rate;
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.insights_rounded,
                      color: AppColors.reminder),
                  title: Text(rate == null
                      ? 'Observance'
                      : '${(rate * 100).round()} % des soins faits à temps'),
                  subtitle: const Text('Par animal, par type et par mois'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => ReminderComplianceScreen.open(context),
                ),
              ),
            ),
          ),
          _list(model, items),
        ];
    }
  }

  Widget _list(RemindersModel model, List<Reminder> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = items[i];
          return _FadeIn(
            key: ValueKey('fade-${r.id}'),
            child: ReminderCard(
              reminder: r,
              now: model.now,
              pet: model.petOf(r),
              onTap: () => showReminderDetailSheet(context, r),
              onDone: () => ReminderActions.markDone(context, r),
              onPostpone: () => ReminderActions.postpone(context, r),
              onDelete: () => ReminderActions.delete(context, r),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(RemindersModel model, ReminderTab tab) {
    if (model.hasActiveFilters) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'Aucun résultat',
          message: 'Aucun rappel ne correspond aux filtres actuels.',
          action: OutlinedButton(
            onPressed: () {
              _search.clear();
              _controller.clearFilters();
            },
            child: const Text('Effacer les filtres'),
          ),
        ),
      );
    }
    final (icon, title, message) = switch (tab) {
      ReminderTab.upcoming => (
          Icons.notifications_none_rounded,
          'Aucun rappel à venir',
          'Créez un rappel pour ne plus oublier un vaccin, un vermifuge '
              'ou un rendez-vous vétérinaire.',
        ),
      ReminderTab.overdue => (
          Icons.task_alt_rounded,
          'Rien en retard 👏',
          'Toutes les échéances passées ont été traitées.',
        ),
      ReminderTab.done => (
          Icons.history_rounded,
          'Aucun rappel terminé',
          'Les rappels marqués comme faits apparaîtront ici.',
        ),
    };
    return SliverToBoxAdapter(
      child: EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: tab == ReminderTab.upcoming
            ? FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.reminder),
                onPressed: () => ReminderActions.openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Créer un rappel'),
              )
            : null,
      ),
    );
  }

  /// Journée surchargée ou budget dépassé : alerte en tête de « À venir ».
  String? _planningAlert(RemindersModel model) {
    final parts = <String>[
      if (model.overloadedDays.firstOrNull case (final day, final items))
        'Journée chargée le ${Fmt.short(day)} (${items.length} rappels)',
      if (model.overBudgetMonth case final f?)
        'Budget de ${Fmt.month(f.month).toLowerCase()} dépassé de ${Units.money(f.excess)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ------------------------------------------------------------ Menu

  Future<void> _onMenu(_MenuAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _MenuAction.demo:
        try {
          final n = await _controller.seedDemo();
          messenger.showSnackBar(SnackBar(
            content: Text(n == 0
                ? 'Les exemples sont déjà chargés'
                : '$n rappels d\'exemple ajoutés'),
          ));
        } on ReminderException catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
      case _MenuAction.planning:
        await ReminderPlanningScreen.open(context);
      case _MenuAction.compliance:
        await ReminderComplianceScreen.open(context);
      case _MenuAction.simulate:
        await _simulateHealth();
      case _MenuAction.testNotification:
        await _controller.sendTestNotification();
        messenger.showSnackBar(const SnackBar(
          content: Text('Notification de test envoyée '
              '(uniquement sur Android / iOS)'),
        ));
      case _MenuAction.permissions:
        final granted = await _controller.requestNotificationPermission();
        messenger.showSnackBar(SnackBar(
          content: Text(granted
              ? 'Notifications autorisées ✓'
              : 'Notifications non autorisées'),
        ));
    }
  }

  /// Démontre l'intégration avec le Module 2 : un HealthRecord saisit une
  /// « prochaine échéance » ; le rappel est créé ou mis à jour sans doublon.
  Future<void> _simulateHealth() async {
    final messenger = ScaffoldMessenger.of(context);
    final now = _controller.model.now;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Dossier santé de démo — prochaine échéance',
      initialDate: DateTime(now.year, now.month, now.day + 14),
      firstDate: DateTime(now.year, now.month, now.day + 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    try {
      final outcome = await _controller.simulateHealthDeadline(
          DateTime(picked.year, picked.month, picked.day, 9));
      final text = switch (outcome) {
        SyncOutcome.created => 'Rappel créé depuis le dossier de santé',
        SyncOutcome.updated =>
          'Échéance modifiée : rappel mis à jour et notifications reprogrammées',
        SyncOutcome.unchanged => 'Déjà synchronisé : aucun doublon créé ✓',
        SyncOutcome.removed => 'Rappel supprimé',
      };
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } on ReminderException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabsHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 68;

  @override
  double get maxExtent => 68;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: maxExtent,
      alignment: Alignment.center,
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_TabsHeaderDelegate old) => true;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Apparition douce des cartes.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Bandeau d'alerte de planification (ouvre Planification & budget).
class _PlanningAlert extends StatelessWidget {
  const _PlanningAlert({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Material(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: Color(0xFFB45309)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );
}
