import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/reminders_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/reminder.dart';
import '../../models/reminder_budget.dart';
import '../../models/reminder_planning.dart';
import '../../models/reminders_model.dart';
import '../../models/validation.dart';
import '../reminder_style.dart';
import '../widgets/input_formatters.dart';

/// Planification et budget : journées surchargées, budget prévisionnel des
/// soins et délais minimaux entre deux soins.
class ReminderPlanningScreen extends StatefulWidget {
  const ReminderPlanningScreen({super.key});

  static const _color = AppColors.reminder;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const ReminderPlanningScreen()));

  @override
  State<ReminderPlanningScreen> createState() => _ReminderPlanningScreenState();
}

class _ReminderPlanningScreenState extends State<ReminderPlanningScreen> {
  /// Déplacements décochés par l'utilisateur (id du rappel).
  final _skipped = <int?>{};

  @override
  void initState() {
    super.initState();
    // Relit les coûts des dossiers de santé (module Santé).
    context.read<RemindersController>().load();
  }

  RemindersController get _controller => context.read<RemindersController>();

  Future<void> _apply(List<ReminderMove> moves, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [for (final m in moves) if (!_skipped.contains(m.reminder.id)) m];
    if (chosen.isEmpty) return;
    final n = await _controller.applyMoves(chosen);
    _skipped.clear();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$n rappel${n > 1 ? 's' : ''} $done')));
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RemindersModel>();
    String? petName(Reminder r) => model.petOf(r)?.name;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planification & budget'),
        backgroundColor: ReminderPlanningScreen._color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ------------------------------------------- Journées chargées
          const _Title('Journées chargées', Icons.view_day_rounded),
          ..._overload(model, petName),
          // ------------------------------------------------------ Budget
          _Title('Budget prévisionnel', Icons.savings_rounded,
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(model.planning.monthlyBudget == null
                    ? 'Fixer un budget'
                    : 'Budget : ${Units.money(model.planning.monthlyBudget!)}'),
                onPressed: () => _editBudget(model.planning),
              )),
          for (final f in model.forecasts) _monthCard(f, model, petName),
          // ------------------------------------------ Délais minimaux
          _Title('Délais minimaux entre soins', Icons.timelapse_rounded,
              trailing: TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter'),
                onPressed: () => _editInterval(model.planning),
              )),
          Card(
            child: Column(
              children: [
                if (model.planning.intervals.isEmpty)
                  const ListTile(title: Text('Aucun délai minimal')),
                for (final rule in model.planning.intervals)
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: Text('${rule.first.label} ↔ ${rule.second.label}'),
                    subtitle: Text('${rule.days} jour${rule.days > 1 ? 's' : ''} minimum, même animal'),
                    onTap: () => _editInterval(model.planning, rule: rule),
                    trailing: IconButton(
                      tooltip: 'Supprimer le délai',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () =>
                          _controller.savePlanning(model.planning.withoutInterval(rule)),
                    ),
                  ),
              ],
            ),
          ),
          const _Note('Réglez ces délais selon l\'avis de votre vétérinaire. Un '
              'rappel trop proche d\'un autre soin affiche un avertissement '
              'avec la première date possible.'),
        ],
      ),
    );
  }

  List<Widget> _overload(RemindersModel model, String? Function(Reminder) petName) {
    final days = model.overloadedDays;
    if (days.isEmpty) {
      return const [
        _InfoCard(
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          text: 'Aucune journée de plus de ${ReminderPlanner.maxPerDay} rappels.',
        ),
      ];
    }
    final moves = model.lightenMoves;
    return [
      for (final (day, items) in days)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${Fmt.long(day)} — ${items.length} rappels',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                const SizedBox(height: 4),
                for (final r in items)
                  Text('• ${Fmt.time(r.dueDate)}  ${r.title}'
                      '${petName(r) == null ? '' : ' · ${petName(r)}'}'),
              ],
            ),
          ),
        ),
      if (moves.isEmpty)
        const _Note('Aucun rappel peu grave (achat, « Autre ») à déplacer : les '
            'soins restent à leur date.')
      else
        _MovesCard(
          title: 'Alléger : déplacer les rappels peu graves',
          moves: moves,
          skipped: _skipped,
          petName: petName,
          onToggle: (id, keep) => setState(() => keep ? _skipped.remove(id) : _skipped.add(id)),
          actionLabel: 'Déplacer',
          onApply: () => _apply(moves, 'déplacé(s)'),
        ),
    ];
  }

  Widget _monthCard(MonthForecast f, RemindersModel model, String? Function(Reminder) petName) {
    final budget = f.budget;
    final ratio = budget == null || budget == 0 ? null : f.total / budget;
    final color = f.overBudget ? AppColors.danger : AppColors.reminder;
    final moves = ReminderBudget.shiftProposal(f, model.now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Prévu en ${Fmt.month(f.month).toLowerCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text(Units.money(f.total),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
              ],
            ),
            if (ratio != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0, 1).toDouble(),
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
            const SizedBox(height: 6),
            if (f.lines.isEmpty)
              const Text('Aucun soin prévu.')
            else
              for (final l in f.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(l.reminder.type.icon, size: 16, color: l.reminder.type.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${Fmt.dayMonth(l.date)} · ${l.reminder.title}'
                          '${petName(l.reminder) == null ? '' : ' · ${petName(l.reminder)}'}'
                          '${l.projected ? ' (répétition)' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(l.estimate == null ? 'coût inconnu' : Units.money(l.amount),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: l.estimate == null
                                  ? Theme.of(context).colorScheme.onSurfaceVariant
                                  : null)),
                    ],
                  ),
                ),
            if (f.unknown > 0)
              _Note('${f.unknown} soin(s) sans coût connu : aucun dossier de santé '
                  'du même type.'),
            if (f.overBudget) ...[
              const SizedBox(height: 8),
              _InfoCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
                text: 'Budget dépassé de ${Units.money(f.excess)} '
                    '(${Units.money(f.total)} pour ${Units.money(budget!)}).',
              ),
              if (moves.isEmpty)
                const _Note('Tous les soins de ce mois sont urgents (vaccins, '
                    'traitements, vermifuges, rendez-vous) : ils ne sont pas décalés.')
              else
                _MovesCard(
                  title: 'Décaler au mois suivant les soins non urgents',
                  moves: moves,
                  skipped: _skipped,
                  petName: petName,
                  onToggle: (id, keep) =>
                      setState(() => keep ? _skipped.remove(id) : _skipped.add(id)),
                  actionLabel: 'Décaler',
                  onApply: () => _apply(moves, 'décalé(s) au mois suivant'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editBudget(PlanningSettings settings) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _BudgetDialog(initial: settings.monthlyBudget),
    );
    if (result == null) return;
    // -1 : champ vidé, plus de plafond.
    await _controller.savePlanning(
        settings.copyWith(monthlyBudget: () => result < 0 ? null : result));
  }

  Future<void> _editInterval(PlanningSettings settings, {IntervalRule? rule}) async {
    final saved = await showDialog<IntervalRule>(
      context: context,
      builder: (_) => _IntervalDialog(initial: rule),
    );
    if (saved == null) return;
    var next = settings;
    if (rule != null) next = next.withoutInterval(rule);
    await _controller.savePlanning(next.withInterval(saved));
  }
}

/// Saisie du budget mensuel. Renvoie le montant, -1 pour « pas de plafond ».
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({this.initial});

  final double? initial;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _text = TextEditingController(
      text: widget.initial == null ? '' : formatDecimal(widget.initial!));
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Budget mensuel des soins'),
        content: Form(
          key: _key,
          child: TextFormField(
            controller: _text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalInputFormatter(decimals: 2, maxDigits: 6)],
            decoration: const InputDecoration(
                labelText: 'Montant (DT)',
                hintText: 'Vide = pas de plafond',
                suffixText: 'DT'),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return null;
              final x = parseDecimal(v!);
              if (x == null || x <= 0) return 'Montant invalide';
              if (x > PlanningSettings.maxBudget) return '100 000 DT maximum';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(context, parseDecimal(_text.text) ?? -1);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      );
}

class _IntervalDialog extends StatefulWidget {
  const _IntervalDialog({this.initial});

  final IntervalRule? initial;

  @override
  State<_IntervalDialog> createState() => _IntervalDialogState();
}

class _IntervalDialogState extends State<_IntervalDialog> {
  late ReminderType _a = widget.initial?.first ?? ReminderType.vaccination;
  late ReminderType _b = widget.initial?.second ?? ReminderType.deworming;
  late final _days = TextEditingController(text: '${widget.initial?.days ?? 7}');
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Widget _typePicker(String label, ReminderType value, ValueChanged<ReminderType> onChanged) =>
      DropdownButtonFormField<ReminderType>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final t in ReminderType.values)
            if (t != ReminderType.purchase)
              DropdownMenuItem(value: t, child: Text(t.label)),
        ],
        onChanged: (t) => setState(() => onChanged(t!)),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Nouveau délai minimal' : 'Modifier le délai'),
        content: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _typePicker('Premier soin', _a, (t) => _a = t),
              const SizedBox(height: 8),
              _typePicker('Second soin', _b, (t) => _b = t),
              const SizedBox(height: 8),
              TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: integerInput(maxDigits: 2),
                decoration: const InputDecoration(labelText: 'Délai minimal', suffixText: 'jours'),
                validator: (v) {
                  final d = int.tryParse(v ?? '');
                  if (d == null || d < 1 || d > IntervalRule.maxDays) {
                    return 'Entre 1 et ${IntervalRule.maxDays} jours';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(context, IntervalRule(_a, _b, int.parse(_days.text)));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      );
}

/// Liste de déplacements à cocher, puis bouton d'application.
class _MovesCard extends StatelessWidget {
  const _MovesCard({
    required this.title,
    required this.moves,
    required this.skipped,
    required this.petName,
    required this.onToggle,
    required this.actionLabel,
    required this.onApply,
  });

  final String title;
  final List<ReminderMove> moves;
  final Set<int?> skipped;
  final String? Function(Reminder) petName;
  final void Function(int? id, bool keep) onToggle;
  final String actionLabel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final chosen = moves.where((m) => !skipped.contains(m.reminder.id)).length;
    return Card(
      color: AppColors.reminder.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (final m in moves)
              CheckboxListTile(
                dense: true,
                value: !skipped.contains(m.reminder.id),
                onChanged: (v) => onToggle(m.reminder.id, v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                    '${m.reminder.title}${petName(m.reminder) == null ? '' : ' · ${petName(m.reminder)}'}'),
                subtitle: Text('${Fmt.short(m.from)} → ${Fmt.short(m.to)} · ${m.reason}'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.reminder),
                onPressed: chosen == 0 ? null : onApply,
                child: Text('$actionLabel ($chosen)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, this.icon, {this.trailing});

  final String text;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
        child: Row(
          children: [
            Icon(icon, color: AppColors.reminder, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ?trailing,
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
