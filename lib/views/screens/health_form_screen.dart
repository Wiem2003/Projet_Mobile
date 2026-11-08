import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/health_form_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/health_form_model.dart';
import '../../models/health_record.dart';
import '../health_style.dart';
import '../widgets/form_parts.dart';
import '../widgets/input_formatters.dart';
import '../widgets/pet_avatar.dart';

/// Formulaire « Ajouter / Modifier un dossier de santé ». Affiche le
/// [HealthFormModel] et transmet chaque saisie au [HealthFormController].
class HealthFormScreen extends StatefulWidget {
  const HealthFormScreen({super.key});

  @override
  State<HealthFormScreen> createState() => _HealthFormScreenState();
}

class _HealthFormScreenState extends State<HealthFormScreen> {
  static const _color = AppColors.health;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vet;
  late final TextEditingController _description;
  late final TextEditingController _weight;
  late final TextEditingController _medication;
  late final TextEditingController _cost;

  HealthFormController get _controller => context.read<HealthFormController>();

  @override
  void initState() {
    super.initState();
    final form = context.read<HealthFormModel>();
    _vet = TextEditingController(text: form.vet);
    _description = TextEditingController(text: form.description);
    _weight = TextEditingController(text: form.weight);
    _medication = TextEditingController(text: form.medication);
    _cost = TextEditingController(text: form.cost);
  }

  @override
  void dispose() {
    for (final c in [_vet, _description, _weight, _medication, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(HealthFormModel form) async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await _controller.save();
    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text([
        form.isEdit ? 'Dossier mis à jour' : 'Dossier ajouté (${saved.type.label})',
        if (saved.nextDue != null)
          'rappel le ${Fmt.medium(saved.nextDue!)} ajouté aux Rappels',
      ].join(' — ')),
    ));
  }

  Future<void> _pickDay(HealthFormModel form) async {
    final now = form.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: form.day,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Date du soin',
    );
    if (picked != null) _controller.setDay(picked);
  }

  Future<void> _pickNextDue(HealthFormModel form) async {
    final first = form.day.add(const Duration(days: 1));
    final initial = form.nextDue ?? DateTime(form.day.year + 1, form.day.month, form.day.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: DateTime(form.day.year + 10),
      helpText: 'Prochaine échéance',
    );
    if (picked != null) _controller.setNextDue(picked);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<HealthFormModel>();
    final next = form.nextDue;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEdit ? 'Modifier le dossier' : 'Nouveau dossier de santé'),
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
            const FormSectionLabel('Type'),
            ChoiceGrid<HealthType>(
              values: HealthType.values,
              selected: form.type,
              labelOf: (t) => t.label,
              iconOf: (t) => t.icon,
              colorOf: (t) => t.color,
              onSelected: _controller.setType,
              columns: 3,
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
              label: 'Jour du soin',
              value: Fmt.long(form.day),
              color: _color,
              onTap: () => _pickDay(form),
              error: form.dateError,
            ),
            const FormSectionLabel('Vétérinaire'),
            TextFormField(
              controller: _vet,
              maxLength: HealthRecord.maxVetLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. Dr Ben Salah',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              onChanged: _controller.setVet,
              validator: HealthFormModel.validateVet,
            ),
            const FormSectionLabel('Description'),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              maxLength: HealthRecord.maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Motif, diagnostic, remarques…',
              ),
              onChanged: _controller.setDescription,
              validator: HealthFormModel.validateDescription,
            ),
            const FormSectionLabel('Médicament'),
            TextFormField(
              controller: _medication,
              maxLength: HealthRecord.maxMedicationLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: switch (form.type) {
                  HealthType.vaccination => 'Nom du vaccin (obligatoire)',
                  HealthType.treatment => 'Médicament et posologie (obligatoire)',
                  _ => 'Facultatif — médicament, posologie',
                },
                prefixIcon: const Icon(Icons.medication_outlined),
              ),
              onChanged: _controller.setMedication,
              validator: form.medicationError,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormSectionLabel('Poids'),
                      TextFormField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          hintText: 'Facultatif',
                          suffixText: 'kg',
                        ),
                        inputFormatters: [
                          DecimalInputFormatter(decimals: 3, maxDigits: 4),
                        ],
                        onChanged: _controller.setWeight,
                        validator: form.weightError,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormSectionLabel('Coût'),
                      TextFormField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0',
                          suffixText: Units.currency,
                        ),
                        inputFormatters: [
                          DecimalInputFormatter(decimals: 3, maxDigits: 6),
                        ],
                        onChanged: _controller.setCost,
                        validator: HealthFormModel.validateCost,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            FormSectionLabel(
              'Prochaine échéance',
              trailing: next == null
                  ? null
                  : TextButton(
                      onPressed: () => _controller.setNextDue(null),
                      child: const Text('Aucune'),
                    ),
            ),
            PickerTile(
              icon: Icons.event_repeat_rounded,
              label: 'Rappel de vaccin, contrôle, traitement…',
              value: next == null ? 'Aucune échéance' : Fmt.long(next),
              color: _color,
              onTap: () => _pickNextDue(form),
              error: form.nextDueError,
            ),
            QuickValues(
              options: [
                for (final (label, date) in form.quickNextDue)
                  (label, date.toIso8601String()),
              ],
              onPick: (iso) => _controller.setNextDue(DateTime.parse(iso)),
            ),
            if (next != null) ...[
              const SizedBox(height: 12),
              ComputedPanel(
                icon: Icons.notifications_active_outlined,
                title: 'Rappel créé automatiquement',
                value: '${Fmt.medium(next)} à ${HealthRecord.reminderHour} h',
                detail: 'Notifications 10 jours avant, la veille et le jour J '
                    '(onglet Rappels)',
                color: AppColors.reminder,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(
        color: _color,
        saving: form.saving,
        label: form.isEdit ? 'Enregistrer' : 'Ajouter le dossier',
        icon: Icons.check_rounded,
        onPressed: () => _save(form),
      ),
    );
  }
}
