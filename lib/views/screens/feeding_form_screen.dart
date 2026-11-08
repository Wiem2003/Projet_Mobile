import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/feeding_form_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/feeding_form_model.dart';
import '../../models/feeding_record.dart';
import '../feeding_style.dart';
import '../widgets/form_parts.dart';
import '../widgets/input_formatters.dart';
import '../widgets/pet_avatar.dart';

/// Formulaire « Ajouter / Modifier un repas ». Affiche le [FeedingFormModel]
/// et transmet chaque saisie au [FeedingFormController].
class FeedingFormScreen extends StatefulWidget {
  const FeedingFormScreen({super.key});

  @override
  State<FeedingFormScreen> createState() => _FeedingFormScreenState();
}

class _FeedingFormScreenState extends State<FeedingFormScreen> {
  static const _color = AppColors.feeding;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _brand;
  late final TextEditingController _kcal;

  FeedingFormController get _controller =>
      context.read<FeedingFormController>();

  @override
  void initState() {
    super.initState();
    final form = context.read<FeedingFormModel>();
    _quantity = TextEditingController(text: form.quantity);
    _price = TextEditingController(text: form.price);
    _brand = TextEditingController(text: form.brand);
    _kcal = TextEditingController(text: form.kcal);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _brand.dispose();
    _kcal.dispose();
    super.dispose();
  }

  /// Les champs peuvent être remplis par le Controller (« Reprendre »).
  void _sync(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  Future<void> _save(FeedingFormModel form) async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await _controller.save();
    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(form.isEdit
          ? 'Repas mis à jour'
          : 'Repas ajouté — ${Units.grams(saved.quantityG)}, '
              '${Units.money(saved.price)}'),
    ));
  }

  Future<void> _pickDate(FeedingFormModel form) async {
    final now = form.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: form.day,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Date du repas',
    );
    if (picked != null) _controller.setDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<FeedingFormModel>();
    _sync(_quantity, form.quantity);
    _sync(_price, form.price);
    _sync(_brand, form.brand);
    _sync(_kcal, form.kcal);
    final last = _controller.lastRecord;
    final perKg = form.pricePerKg;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEdit ? 'Modifier le repas' : 'Ajouter un repas'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        // Les erreurs s'affichent dès que l'utilisateur a touché un champ.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            if (form.pets.isEmpty)
              const FormBanner(
                icon: Icons.pets_rounded,
                text: 'Ajoutez d\'abord un animal (Accueil → Mes animaux).',
                color: AppColors.warning,
              ),
            if (form.error != null)
              FormBanner(
                icon: Icons.error_outline_rounded,
                text: form.error!,
                color: AppColors.danger,
              ),
            if (last != null)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: Icon(Icons.history_rounded, color: _color),
                  title: const Text('Reprendre le dernier repas'),
                  subtitle: Text('${last.foodType.label} · '
                      '${Units.grams(last.quantityG)} · '
                      '${Units.money(last.price)}'
                      '${last.brand == null ? '' : ' · ${last.brand}'}'),
                  trailing: TextButton(
                    onPressed: _controller.copyLast,
                    child: const Text('Reprendre'),
                  ),
                ),
              ),
            const FormSectionLabel('Animal'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in form.pets)
                  ChoiceChip(
                    avatar: PetAvatar(pet: p, size: 22),
                    label: Text(p.name),
                    selected: form.petId == p.id,
                    onSelected: (_) => _controller.setPet(p.id),
                  ),
              ],
            ),
            const FormSectionLabel('Date'),
            PickerTile(
              icon: Icons.calendar_today_rounded,
              label: 'Jour du repas',
              value: Fmt.long(form.day),
              color: _color,
              onTap: () => _pickDate(form),
              error: form.dateError,
            ),
            const FormSectionLabel('Type de nourriture'),
            ChoiceGrid<FoodType>(
              values: FoodType.values,
              selected: form.foodType,
              labelOf: (t) => t.label,
              iconOf: (t) => t.icon,
              colorOf: (t) => t.color,
              onSelected: _controller.setFoodType,
            ),
            const FormSectionLabel('Quantité'),
            TextFormField(
              controller: _quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'Ex. 350',
                suffixText: 'g',
                prefixIcon: Icon(Icons.scale_rounded),
              ),
              inputFormatters: [DecimalInputFormatter(decimals: 1)],
              onChanged: _controller.setQuantity,
              validator: form.quantityError,
            ),
            QuickValues(
              options: const [
                ('50 g', '50'),
                ('100 g', '100'),
                ('250 g', '250'),
                ('500 g', '500'),
              ],
              onPick: _controller.setQuantity,
            ),
            const FormSectionLabel('Nombre de repas'),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Moins de repas',
                  onPressed: form.meals > 1
                      ? () => _controller.setMeals(form.meals - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    '${form.meals} repas',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Plus de repas',
                  onPressed: form.meals < FeedingRecord.maxMeals
                      ? () => _controller.setMeals(form.meals + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (form.mealsWarning case final warning?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(warning,
                            style: const TextStyle(fontSize: 13, color: Color(0xFFB45309)))),
                  ],
                ),
              ),
            const FormSectionLabel('Prix'),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'Prix de cette quantité',
                suffixText: Units.currency,
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              inputFormatters: [DecimalInputFormatter(decimals: 3)],
              onChanged: _controller.setPrice,
              validator: FeedingFormModel.validatePrice,
            ),
            const FormSectionLabel('Marque'),
            TextFormField(
              controller: _brand,
              maxLength: FeedingRecord.maxBrandLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. Royal Canin',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              onChanged: _controller.setBrand,
              validator: FeedingFormModel.validateBrand,
            ),
            const FormSectionLabel('Calories (emballage)'),
            TextFormField(
              controller: _kcal,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Facultatif — valeur typique : '
                    '${form.foodType.typicalKcalPer100g.round()}',
                suffixText: 'kcal / 100 g',
                prefixIcon: const Icon(Icons.local_fire_department_outlined),
              ),
              inputFormatters: [DecimalInputFormatter(decimals: 0, maxDigits: 3)],
              onChanged: _controller.setKcal,
              validator: FeedingFormModel.validateKcal,
            ),
            if (form.mealKcal case final kcal?)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  '≈ ${kcal.round()} kcal'
                  '${form.kcalValue == null ? ' (valeur typique des ${form.foodType.label.toLowerCase()})' : ''}',
                  style: TextStyle(
                      fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            if (perKg != null) ...[
              const SizedBox(height: 8),
              ComputedPanel(
                icon: Icons.calculate_outlined,
                title: 'Prix au kilo (calculé)',
                value: '${Units.money(perKg)} / kg',
                detail: '${Units.grams(form.quantityValue!)} en '
                    '${form.meals} repas',
                color: _color,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(
        color: _color,
        saving: form.saving,
        label: form.isEdit ? 'Enregistrer' : 'Ajouter le repas',
        icon: Icons.check_rounded,
        onPressed: () => _save(form),
      ),
    );
  }
}
