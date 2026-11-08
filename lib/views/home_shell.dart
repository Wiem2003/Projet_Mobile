import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../models/activities_model.dart';
import '../models/auth/auth_model.dart';
import '../models/feeding_model.dart';
import '../models/health_model.dart';
import '../models/pets_model.dart';
import '../models/reminders_model.dart';
import '../controllers/reminders_controller.dart';
import 'health_style.dart';
import 'dashboard_data.dart';
import 'pet_actions.dart';
import 'screens/account_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/activities_screen.dart';
import 'screens/feeding_screen.dart';
import 'screens/health_screen.dart';
import 'screens/reminders_screen.dart';
import 'widgets/dashboard_cards.dart';
import 'widgets/pet_photo.dart';
import 'widgets/stat_card.dart';
import 'widgets/upcoming_reminders_card.dart';

/// Navigation principale (barre du bas, cf. plan de navigation).
/// Le module Animaux s'ouvre depuis l'accueil (« Mes animaux »).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const healthTab = 1;
  static const feedingTab = 2;
  static const activityTab = 3;
  static const remindersTab = 4;
  int _index = 0;
  late final RemindersController _reminders;

  @override
  void initState() {
    super.initState();
    _reminders = context.read<RemindersController>();
    _reminders.intent.addListener(_openReminders);
  }

  @override
  void dispose() {
    _reminders.intent.removeListener(_openReminders);
    super.dispose();
  }

  void _openReminders() {
    if (_reminders.intent.value != null && _index != remindersTab) {
      setState(() => _index = remindersTab);
    }
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _DashboardPreview(
            onSeeReminders: () => _go(remindersTab),
            onSeeHealth: () => _go(healthTab),
            onSeeFeeding: () => _go(feedingTab),
            onSeeActivity: () => _go(activityTab),
          ),
          const HealthScreen(),
          const FeedingScreen(),
          const ActivitiesScreen(),
          const RemindersScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Accueil'),
          const NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: 'Santé'),
          const NavigationDestination(
              icon: Icon(Icons.restaurant_outlined),
              selectedIcon: Icon(Icons.restaurant_rounded),
              label: 'Repas'),
          const NavigationDestination(
              icon: Icon(Icons.directions_run_outlined),
              selectedIcon: Icon(Icons.directions_run_rounded),
              label: 'Activité'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: context.select<RemindersModel, bool>(
                  (c) => c.stats.overdue > 0),
              label: Text(
                  '${context.select<RemindersModel, int>((c) => c.stats.overdue)}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: 'Rappels',
          ),
        ],
      ),
    );
  }
}

class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview({
    required this.onSeeReminders,
    required this.onSeeHealth,
    required this.onSeeFeeding,
    required this.onSeeActivity,
  });

  final VoidCallback onSeeReminders;
  final VoidCallback onSeeHealth;
  final VoidCallback onSeeFeeding;
  final VoidCallback onSeeActivity;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.paddingOf(context).top + 20, 20, 24),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: const _Greeting(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const _AdminCard(),
              const ReportReadyCard(),
              const AlertsCard(),
              const _MyPets(),
              const SizedBox(height: 12),
              UpcomingRemindersCard(onSeeAll: onSeeReminders),
              const SizedBox(height: 12),
              const SmartPetIndexCard(),
              StatGrid(children: [
                _DashboardTile(
                  onTap: onSeeFeeding,
                  child: Builder(builder: (context) {
                    final stats = context.watch<FeedingModel>().stats;
                    return StatCard(
                      icon: Icons.restaurant_rounded,
                      label: 'Dépenses du mois',
                      value: Units.money(stats.spending),
                      caption: '${Units.grams(stats.quantityG)} consommés',
                      trend: stats.spendingChange,
                      upIsGood: false,
                      color: AppColors.feeding,
                    );
                  }),
                ),
                _DashboardTile(
                  onTap: onSeeActivity,
                  child: Builder(builder: (context) {
                    final stats = context.watch<ActivitiesModel>().stats;
                    return StatCard(
                      icon: Icons.directions_run_rounded,
                      label: 'Distance 7 jours',
                      value: Units.km(stats.weeklyDistanceKm),
                      caption: '${stats.thisWeek.count} activité(s) cette semaine',
                      trend: stats.distanceChange,
                      color: AppColors.activity,
                    );
                  }),
                ),
              ]),
              const SizedBox(height: 10),
              StatGrid(children: [
                _DashboardTile(
                  onTap: onSeeHealth,
                  child: Builder(builder: (context) {
                    final stats = context.watch<HealthModel>().stats;
                    return StatCard(
                      icon: Icons.medical_services_rounded,
                      label: 'Dépenses médicales',
                      value: Units.money(stats.spending),
                      caption: '${stats.consultations} consultation(s) · '
                          '${stats.period.label}',
                      color: AppColors.health,
                    );
                  }),
                ),
                _DashboardTile(
                  onTap: onSeeHealth,
                  child: Builder(builder: (context) {
                    final health = context.watch<HealthModel>();
                    final next = health.upcoming.firstOrNull;
                    return StatCard(
                      icon: Icons.event_repeat_rounded,
                      label: 'Prochain soin',
                      value: next == null ? '—' : Fmt.short(next.nextDue!),
                      caption: next == null
                          ? 'aucune échéance'
                          : '${next.type.label} · '
                              '${health.petOf(next.petId)?.name ?? ''}',
                      color: AppColors.reminder,
                    );
                  }),
                ),
              ]),
              const SizedBox(height: 12),
              const PetCostCard(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rend une carte de l'accueil cliquable (ouvre l'onglet du module).
class _DashboardTile extends StatelessWidget {
  const _DashboardTile({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// « Mes animaux » : accès au module 1 depuis l'accueil.
class _MyPets extends StatelessWidget {
  const _MyPets();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PetsModel>();
    final data = DashboardData.watch(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pets_rounded, color: AppColors.pet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Mes animaux',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  onPressed: () => PetActions.openList(context),
                  child: const Text('Voir tout'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in model.all)
                    _PetBubble(
                      label: p.name,
                      onTap: () => PetActions.openDetail(context, p),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          PetPhoto.of(p, size: 60),
                          Positioned(
                            right: -6,
                            top: -4,
                            child: IndexBadge(index: data.indexOf(p)),
                          ),
                        ],
                      ),
                    ),
                  _PetBubble(
                    label: 'Ajouter',
                    onTap: () => PetActions.openForm(context),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.pet, width: 1.5),
                      ),
                      child: const Icon(Icons.add_rounded, color: AppColors.pet),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetBubble extends StatelessWidget {
  const _PetBubble({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              child,
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// En-tête de l'accueil : salutation et accès au compte.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthModel>().user;
    final first = user?.name.trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Smart Pet',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  first == null || first.isEmpty
                      ? 'Bonjour ! Voici le résumé de vos animaux'
                      : 'Bonjour $first ! Voici le résumé de vos animaux',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        if (user != null)
          Tooltip(
            message: 'Mon compte',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => AccountScreen.open(context),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: UserAvatar(user: user),
              ),
            ),
          ),
      ],
    );
  }
}

/// Raccourci vers l'administration (rôle admin uniquement).
class _AdminCard extends StatelessWidget {
  const _AdminCard();

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthModel>().isAdmin) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.admin_panel_settings_rounded,
              color: AppColors.reminder),
          title: const Text('Administration',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Comptes, rôles et statistiques'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => AdminScreen.open(context),
        ),
      ),
    );
  }
}
