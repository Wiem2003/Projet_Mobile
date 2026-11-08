import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/feeding_plan_controller.dart';
import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';
import '../../models/feeding_insights.dart';
import '../../models/feeding_model.dart';
import '../../models/feeding_plan.dart';
import '../../models/feeding_record.dart';
import '../../models/validation.dart';
import '../feeding_style.dart';
import 'input_formatters.dart';

const _warnText = Color(0xFFB45309);

TextStyle _muted(BuildContext context, [double size = 12.5]) =>
    TextStyle(fontSize: size, color: Theme.of(context).colorScheme.onSurfaceVariant);

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppColors.feeding),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          ?trailing,
        ],
      );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : _warnText;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (danger ? AppColors.danger : AppColors.warning).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(danger ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
              size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
        ],
      ),
    );
  }
}

// =================================================================== Budget

/// Budget alimentaire du mois affiché : dépense, plafond et projection de
/// fin de mois (animal choisi, ou tous les animaux).
class FoodBudgetCard extends StatelessWidget {
  const FoodBudgetCard({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FeedingModel>();
    final plan = context.watch<FeedingPlanModel>().plan;
    final petId = model.petFilter;
    final pet = model.petOf(petId);
    final stats = model.stats;
    final status = FeedingInsights.budget(
        spent: stats.spending,
        month: model.month,
        now: model.now,
        cap: plan.budget.capFor(petId));
    final cap = status.cap;
    final current = model.isCurrentMonth;
    final color = status.exceeded
        ? AppColors.danger
        : status.willExceed
            ? AppColors.warning
            : AppColors.feeding;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: pet == null ? 'Budget alimentaire' : 'Budget de ${pet.name}',
              trailing: IconButton(
                tooltip: cap == null ? 'Définir un plafond' : 'Modifier le plafond',
                icon: Icon(cap == null ? Icons.add_rounded : Icons.edit_outlined),
                onPressed: () => _editCap(context, petId, pet?.name, cap),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap == null
                        ? '${Units.money(status.spent)} dépensés · pas de plafond'
                        : '${Units.money(status.spent)} sur ${Units.money(cap)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (cap != null) ...[
                    const SizedBox(height: 6),
                    _Bar(value: status.share, color: color),
                  ],
                  const SizedBox(height: 6),
                  if (current && status.spent > 0)
                    Text('Vous finirez le mois à environ ${Units.money(status.projected)}',
                        style: _muted(context, 13))
                  else if (!current)
                    Text('Mois terminé', style: _muted(context, 13))
                  else
                    Text('Aucune dépense ce mois-ci pour l\'instant.', style: _muted(context, 13)),
                  if (status.exceeded)
                    _Notice(
                        'Plafond dépassé de ${Units.money(status.spent - cap!)}.',
                        danger: true)
                  else if (current && status.willExceed)
                    _Notice('À ce rythme, le plafond sera dépassé d\'environ '
                        '${Units.money(status.projected - cap!)} en fin de mois.'),
                  if (pet == null && cap == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Choisissez un animal en haut pour son propre plafond.',
                          style: _muted(context, 12)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _editCap(BuildContext context, int? petId, String? petName, double? cap) async {
    final controller = context.read<FeedingPlanController>();
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(
        title: petName == null ? 'Plafond mensuel (tous les animaux)' : 'Plafond mensuel de $petName',
        initial: cap,
      ),
    );
    if (result == null) return;
    await controller.setBudget(petId, result < 0 ? null : result);
    if (context.mounted) {
      _snack(context, result < 0 ? 'Plafond retiré' : 'Plafond de ${Units.money(result)} par mois enregistré');
    }
  }
}

/// Montant ; renvoie −1 si le champ est vidé (plafond retiré).
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.initial});

  final String title;
  final double? initial;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _text =
      TextEditingController(text: widget.initial == null ? '' : formatDecimal(widget.initial!));
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _key,
          child: TextFormField(
            controller: _text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalInputFormatter(decimals: 2, maxDigits: 6)],
            decoration: const InputDecoration(
                labelText: 'Montant', hintText: 'Vide = pas de plafond', suffixText: 'DT'),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return null;
              final x = parseDecimal(v!);
              if (x == null || x <= 0) return 'Montant invalide';
              if (x > FoodBudget.maxAmount) return '100 000 DT maximum';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
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

// ==================================================================== Stock

/// Sacs ouverts : reste, date où ils seront vides et rappel « Racheter ».
class FoodStockCard extends StatelessWidget {
  const FoodStockCard({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FeedingModel>();
    final plan = context.watch<FeedingPlanModel>().plan;
    final bags = plan.bagsOf(model.petFilter);
    final now = model.now;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(icon: Icons.inventory_2_outlined, title: 'Stock de nourriture'),
            if (bags.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Enregistrez le sac que vous ouvrez : l\'app calcule ce qu\'il reste et '
                    'vous rappelle de racheter 3 jours avant qu\'il soit vide.',
                    style: _muted(context, 13)),
              ),
            for (final bag in bags)
              _BagTile(
                status: FeedingInsights.stock(bag, model.all, now),
                pets: [for (final id in bag.petIds) ?model.petOf(id)],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ouvrir un sac'),
                onPressed: model.pets.isEmpty ? null : () => _openForm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openForm(BuildContext context, [FoodBag? bag]) async {
    final saved = await showDialog<FoodBag>(context: context, builder: (_) => _BagDialog(bag: bag));
    if (saved != null && context.mounted) {
      _snack(context, bag == null ? 'Sac enregistré' : 'Sac modifié');
    }
  }
}

enum _BagAction { edit, finish }

class _BagTile extends StatelessWidget {
  const _BagTile({required this.status, required this.pets});

  final StockStatus status;
  final List<PetSummary> pets;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final bag = s.bag;
    final color = s.empty
        ? AppColors.danger
        : s.low
            ? AppColors.warning
            : AppColors.feeding;
    final emptyOn = s.emptyOn;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bag.foodType.icon, color: bag.foodType.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${bag.label} · ${pets.map((p) => p.name).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<_BagAction>(
                tooltip: 'Actions du sac',
                padding: EdgeInsets.zero,
                onSelected: (a) => _run(context, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _BagAction.edit, child: Text('Modifier')),
                  PopupMenuItem(value: _BagAction.finish, child: Text('Sac terminé')),
                ],
              ),
            ],
          ),
          _Bar(value: s.remainingShare, color: color),
          const SizedBox(height: 4),
          Text(
            'Reste ${Units.grams(s.remainingG)} sur ${Units.grams(bag.weightG)}'
            '${s.dailyG == null ? '' : ' · ${Units.grams(s.dailyG!)} / jour'}'
            '${emptyOn == null || s.empty ? '' : ' · vide vers le ${Fmt.short(emptyOn)}'}',
            style: _muted(context),
          ),
          if (s.low)
            _Notice(FeedingInsights.stockSentence(s, [for (final p in pets) p.name]),
                danger: s.empty),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, _BagAction a) async {
    if (a == _BagAction.edit) return FoodStockCard._openForm(context, status.bag);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sac terminé ?'),
        content: const Text('Le sac est retiré du stock, avec son rappel « Racheter ». '
            'Enregistrez ensuite le nouveau sac.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<FeedingPlanController>().removeBag(status.bag);
    if (context.mounted) _snack(context, 'Sac retiré du stock');
  }
}

class _BagDialog extends StatefulWidget {
  const _BagDialog({this.bag});

  final FoodBag? bag;

  @override
  State<_BagDialog> createState() => _BagDialogState();
}

class _BagDialogState extends State<_BagDialog> {
  final _key = GlobalKey<FormState>();
  late final FeedingModel _feeding = context.read<FeedingModel>();
  late final Set<int> _pets;
  late FoodType _type;
  late DateTime _opened;
  late final TextEditingController _brand, _weight, _price;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bag;
    final selected = _feeding.petFilter;
    final last = _feeding.lastFor(selected ?? _feeding.pets.firstOrNull?.id);
    _pets = {...?b?.petIds, if (b == null) ?(selected ?? _feeding.pets.firstOrNull?.id)};
    _type = b?.foodType ?? FoodType.kibble;
    final now = _feeding.now;
    _opened = b?.openedOn ?? DateTime(now.year, now.month, now.day);
    _brand = TextEditingController(
        text: b?.brand ?? (last?.foodType == FoodType.kibble ? last?.brand ?? '' : ''));
    _weight = TextEditingController(text: b == null ? '' : formatDecimal(b.weightG / 1000, decimals: 3));
    _price = TextEditingController(text: b == null ? '' : formatDecimal(b.price));
  }

  @override
  void dispose() {
    for (final c in [_brand, _weight, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = _feeding.now;
    final d = await showDatePicker(
      context: context,
      initialDate: _opened,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Date d\'ouverture',
    );
    if (d != null) setState(() => _opened = d);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_pets.isEmpty) return setState(() => _error = 'Choisissez au moins un animal.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await context.read<FeedingPlanController>().saveBag(FoodBag(
            id: widget.bag?.id ?? 0,
            petIds: _pets.toList(),
            foodType: _type,
            brand: _brand.text,
            weightG: parseDecimal(_weight.text)! * 1000,
            price: parseDecimal(_price.text) ?? 0,
            openedOn: _opened,
          ));
      if (mounted) Navigator.pop(context, saved);
    } on RecordException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.bag == null ? 'Ouvrir un sac' : 'Modifier le sac'),
      scrollable: true,
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mangé par', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _feeding.pets)
                  FilterChip(
                    label: Text(p.name),
                    selected: _pets.contains(p.id),
                    onSelected: (v) => setState(() => v ? _pets.add(p.id) : _pets.remove(p.id)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<FoodType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Aliment'),
              items: [
                for (final t in FoodType.values) DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _type = t!),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _brand,
              inputFormatters: [LengthLimitingTextInputFormatter(FeedingRecord.maxBrandLength)],
              decoration: const InputDecoration(
                  labelText: 'Marque (facultatif)',
                  helperText: 'Si elle est indiquée, seuls les repas de cette marque comptent'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalInputFormatter(decimals: 3, maxDigits: 2)],
              decoration: const InputDecoration(labelText: 'Poids du sac', suffixText: 'kg'),
              validator: (v) {
                final x = parseDecimal(v ?? '');
                if (x == null || x <= 0) return 'Indiquez le poids du sac';
                if (x * 1000 > FoodBag.maxWeightG) return '50 kg maximum';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalInputFormatter(decimals: 2, maxDigits: 5)],
              decoration: InputDecoration(labelText: 'Prix (facultatif)', suffixText: Units.currency),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Ouvert le'),
              subtitle: Text(Fmt.long(_opened)),
              onTap: _pickDate,
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

// =========================================================== Perte de poids

/// Programme de perte de poids de l'animal choisi (dans la section
/// Nutrition).
class DietPanel extends StatelessWidget {
  const DietPanel({super.key, required this.pet, required this.progress});

  final PetSummary pet;

  /// `null` : pas de programme en cours.
  final DietProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) {
      return Row(
        children: [
          Expanded(
            child: Text('Programme de perte de poids', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Démarrer'),
            onPressed: pet.weightKg == null ? null : () => _start(context),
          ),
        ],
      );
    }
    final plan = p.plan;
    final pace = p.pace;
    final warning = FeedingInsights.dietWarning(pet.name, p);
    final paceColor = switch (pace) {
      DietPace.reached || DietPace.ahead || DietPace.onTrack => AppColors.success,
      DietPace.behind => _warnText,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Perte de poids : ${Units.kg(plan.startKg)} → ${Units.kg(plan.targetKg)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Arrêter le programme',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => _stop(context),
            ),
          ],
        ),
        _Bar(value: p.progress, color: AppColors.feeding),
        const SizedBox(height: 4),
        Text(
          'Actuel : ${Units.kg(p.current.kg)} (pesé le ${Fmt.short(p.current.date)}) · '
          'prévu : ${Units.kg(p.plannedNow)}',
          style: _muted(context),
        ),
        Text(
          'Rythme : ${_pct(plan.weeklyRate)} par semaine · arrivée estimée le ${Fmt.short(plan.arrival)}'
          '${p.weeklyLoss == null ? '' : ' · mesuré : ${_pct(p.weeklyLoss!)} / sem.'}',
          style: _muted(context),
        ),
        const SizedBox(height: 2),
        Text(pace.label, style: TextStyle(fontWeight: FontWeight.w700, color: paceColor, fontSize: 13)),
        if (warning != null) _Notice(warning, danger: p.isCat),
        if (pace == DietPace.reached)
          Text('Bravo ! Vous pouvez arrêter le programme : la ration revient au poids actuel.',
              style: _muted(context)),
        const SizedBox(height: 8),
        SizedBox(height: 130, child: DietChart(progress: p)),
        if (p.weights.length < 2)
          Text('Ajoutez le poids lors d\'un soin (module Santé) pour suivre la courbe.',
              style: _muted(context, 12)),
      ],
    );
  }

  static String _pct(double r) => '${formatDecimal(r * 100, decimals: 1)} %';

  Future<void> _start(BuildContext context) async {
    final plan = await showDialog<DietPlan>(
        context: context, builder: (_) => _DietDialog(pet: pet, now: context.read<FeedingModel>().now));
    if (plan != null && context.mounted) {
      _snack(context, 'Programme démarré : objectif ${Units.kg(plan.targetKg)} vers le ${Fmt.short(plan.arrival)}');
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter le programme ?'),
        content: Text('La ration de ${pet.name} sera de nouveau calculée sur son poids actuel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arrêter')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<FeedingPlanController>().stopDiet(pet.id);
    if (context.mounted) _snack(context, 'Programme arrêté');
  }
}

class _DietDialog extends StatefulWidget {
  const _DietDialog({required this.pet, required this.now});

  final PetSummary pet;
  final DateTime now;

  @override
  State<_DietDialog> createState() => _DietDialogState();
}

class _DietDialogState extends State<_DietDialog> {
  final _key = GlobalKey<FormState>();
  final _target = TextEditingController();
  double _rate = DietPlan.minRate;
  String? _error;

  double get _start => widget.pet.weightKg!;

  DietPlan? get _draft {
    final t = parseDecimal(_target.text);
    if (t == null) return null;
    return DietPlan(
        petId: widget.pet.id, startKg: _start, targetKg: t, startDate: widget.now, weeklyRate: _rate);
  }

  @override
  void initState() {
    super.initState();
    _target.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final plan = _draft!;
    try {
      await context.read<FeedingPlanController>().startDiet(plan);
      if (mounted) Navigator.pop(context, plan);
    } on RecordException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final valid = draft != null && DietPlan.validate(draft) == null;
    return AlertDialog(
      title: Text('Perte de poids de ${widget.pet.name}'),
      scrollable: true,
      content: Form(
        key: _key,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Poids actuel : ${Units.kg(_start)}'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _target,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalInputFormatter(decimals: 2, maxDigits: 4)],
              decoration: const InputDecoration(labelText: 'Poids cible', suffixText: 'kg'),
              validator: (_) {
                final d = _draft;
                return d == null ? 'Indiquez le poids cible' : DietPlan.validate(d);
              },
            ),
            const SizedBox(height: 12),
            const Text('Rythme par semaine', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0.01, label: Text('1 %')),
                ButtonSegment(value: 0.015, label: Text('1,5 %')),
                ButtonSegment(value: 0.02, label: Text('2 %')),
              ],
              selected: {_rate},
              onSelectionChanged: (s) => setState(() => _rate = s.first),
            ),
            const SizedBox(height: 10),
            if (valid)
              Text(
                'Environ ${draft.weeks} semaines : arrivée estimée le ${Fmt.long(draft.arrival)}. '
                'La ration sera calculée sur ${Units.kg(draft.targetKg)}.',
                style: _muted(context, 13),
              ),
            Text('À valider avec le vétérinaire.',
                style: _muted(context, 12).copyWith(fontStyle: FontStyle.italic)),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Démarrer')),
      ],
    );
  }
}

/// Courbe prévue (pointillés) et pesées réelles du programme.
class DietChart extends StatelessWidget {
  const DietChart({super.key, required this.progress});

  final DietProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Courbe de poids : prévue et réelle',
      child: CustomPaint(
        size: Size.infinite,
        painter: _DietPainter(
          progress,
          planned: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          actual: AppColors.feeding,
          text: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DietPainter extends CustomPainter {
  _DietPainter(this.p, {required this.planned, required this.actual, required this.text});

  final DietProgress p;
  final Color planned, actual, text;

  @override
  void paint(Canvas canvas, Size size) {
    final plan = p.plan;
    final end = [plan.arrival, p.current.date].reduce((a, b) => a.isAfter(b) ? a : b);
    final spanDays = math.max(7, end.difference(plan.startDate).inDays);
    final kgs = [plan.startKg, plan.targetKg, for (final w in p.weights) w.kg];
    final hi = kgs.reduce(math.max), lo = kgs.reduce(math.min);
    final pad = math.max(0.2, (hi - lo) * 0.1);
    final top = hi + pad, bottom = lo - pad;

    const left = 40.0, labelH = 16.0;
    final w = size.width - left - 4, h = size.height - labelH;
    Offset at(DateTime d, double kg) => Offset(
          left + w * d.difference(plan.startDate).inDays / spanDays,
          h * (top - kg) / (top - bottom),
        );

    void label(String s, Offset o, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: text)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = switch (align) {
        TextAlign.right => o.dx - tp.width,
        TextAlign.center => o.dx - tp.width / 2,
        _ => o.dx,
      };
      tp.paint(canvas, Offset(dx, o.dy - tp.height / 2));
    }

    // Objectif.
    final targetY = at(plan.startDate, plan.targetKg).dy;
    final grid = Paint()
      ..color = text.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, targetY), Offset(size.width, targetY), grid);
    label(Units.kg(plan.startKg), Offset(left - 4, at(plan.startDate, plan.startKg).dy),
        align: TextAlign.right);
    label(Units.kg(plan.targetKg), Offset(left - 4, targetY), align: TextAlign.right);

    // Courbe prévue, en pointillés.
    final dash = Paint()
      ..color = planned
      ..strokeWidth = 1.5;
    Offset? prev;
    for (var d = 0; d <= spanDays; d++) {
      final day = plan.startDate.add(Duration(days: d));
      final o = at(day, plan.plannedKgAt(day));
      if (prev != null && d.isOdd) canvas.drawLine(prev, o, dash);
      prev = o;
    }

    // Pesées réelles.
    final line = Paint()
      ..color = actual
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (final (i, wt) in p.weights.indexed) {
      final o = at(wt.date, wt.kg);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = actual;
    for (final wt in p.weights) {
      canvas.drawCircle(at(wt.date, wt.kg), 3.5, dot);
    }

    label(Fmt.short(plan.startDate), Offset(left, size.height - labelH / 2));
    label(Fmt.short(end), Offset(size.width - 4, size.height - labelH / 2), align: TextAlign.right);
  }

  @override
  bool shouldRepaint(_DietPainter old) => old.p != p || old.text != text;
}
