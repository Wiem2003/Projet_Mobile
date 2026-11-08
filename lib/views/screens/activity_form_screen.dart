import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/activity_form_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activity.dart';
import '../../models/activity_form_model.dart';
import '../activity_style.dart';
import '../widgets/form_parts.dart';
import '../widgets/input_formatters.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/route_trace.dart';

/// Formulaire « Nouvelle activité / Modifier ». Affiche
/// l'[ActivityFormModel] (dont l'aperçu des calories) et transmet chaque
/// saisie à l'[ActivityFormController].
class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key});

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  static const _color = AppColors.activity;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _duration;
  late final TextEditingController _distance;
  late final TextEditingController _weight;
  late final TextEditingController _description;

  ActivityFormController get _controller =>
      context.read<ActivityFormController>();

  @override
  void initState() {
    super.initState();
    final form = context.read<ActivityFormModel>();
    _duration = TextEditingController(text: form.duration);
    _distance = TextEditingController(text: form.distance);
    _weight = TextEditingController(text: form.weight);
    _description = TextEditingController(text: form.description);
  }

  @override
  void dispose() {
    _duration.dispose();
    _distance.dispose();
    _weight.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Le poids peut être changé par le Controller (choix de l'animal).
  void _sync(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  Future<void> _save(ActivityFormModel form) async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await _controller.save();
    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(form.isEdit
          ? 'Activité mise à jour'
          : '${saved.type.label} enregistrée — ${Units.kcal(saved.calories)}'),
    ));
  }

  Future<void> _pickDate(ActivityFormModel form) async {
    final now = form.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: form.day,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Date de l\'activité',
    );
    if (picked != null) _controller.setDay(picked);
  }

  Future<void> _pickTime(ActivityFormModel form) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: form.hour, minute: form.minute),
      helpText: 'Heure de début',
    );
    if (picked != null) _controller.setTime(picked.hour, picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<ActivityFormModel>();
    _sync(_duration, form.duration);
    _sync(_distance, form.distance);
    _sync(_weight, form.weight);
    final pet = form.pet;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEdit
            ? 'Modifier l\'activité'
            : form.fromGps
                ? 'Enregistrer la promenade'
                : 'Nouvelle activité'),
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
            if (form.fromGps) ...[
              const FormSectionLabel('Trajet GPS'),
              RouteTrace(points: form.route, color: _color, height: 180),
            ],
            const FormSectionLabel('Type d\'activité'),
            ChoiceGrid<ActivityType>(
              values: ActivityType.values,
              selected: form.type,
              labelOf: (t) => t.label,
              iconOf: (t) => t.icon,
              colorOf: (t) => t.color,
              onSelected: _controller.setType,
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
            const FormSectionLabel('Date et heure'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: PickerTile(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: Fmt.medium(form.day),
                    color: _color,
                    onTap: () => _pickDate(form),
                    error: form.dateError,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PickerTile(
                    icon: Icons.schedule_rounded,
                    label: 'Début',
                    value: TimeOfDay(hour: form.hour, minute: form.minute)
                        .format(context),
                    color: _color,
                    onTap: () => _pickTime(form),
                  ),
                ),
              ],
            ),
            const FormSectionLabel('Durée'),
            TextFormField(
              controller: _duration,
              keyboardType: TextInputType.number,
              inputFormatters: integerInput(),
              decoration: const InputDecoration(
                hintText: 'Ex. 45',
                suffixText: 'min',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              onChanged: _controller.setDuration,
              validator: ActivityFormModel.validateDuration,
            ),
            QuickValues(
              options: const [
                ('15 min', '15'),
                ('30 min', '30'),
                ('45 min', '45'),
                ('1 h', '60'),
              ],
              onPick: _controller.setDuration,
            ),
            if (form.type.usesDistance) ...[
              const FormSectionLabel('Distance'),
              TextFormField(
                controller: _distance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'Facultatif — ex. 3,5',
                  suffixText: 'km',
                  prefixIcon: const Icon(Icons.straighten_rounded),
                  helperText: form.fromGps ? 'Mesurée par le GPS' : null,
                ),
                inputFormatters: [DecimalInputFormatter(maxDigits: 3)],
                onChanged: _controller.setDistance,
                validator: (v) =>
                    ActivityFormModel.validateDistance(v) ?? form.speedError,
              ),
            ],
            const FormSectionLabel('Poids de l\'animal'),
            TextFormField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Ex. 12',
                suffixText: 'kg',
                prefixIcon: const Icon(Icons.monitor_weight_outlined),
                helperText: pet?.weightKg == null
                    ? 'Sert au calcul des calories'
                    : 'Poids connu de ${pet!.name} : ${Units.kg(pet.weightKg!)}',
              ),
              inputFormatters: [DecimalInputFormatter(decimals: 3, maxDigits: 4)],
              onChanged: _controller.setWeight,
              validator: form.weightError,
            ),
            const SizedBox(height: 12),
            ComputedPanel(
              icon: Icons.local_fire_department_rounded,
              title: 'Calories estimées (calcul automatique)',
              value: Units.kcal(form.estimatedCalories),
              detail: 'MET ${form.type.met} (${form.type.label.toLowerCase()}) '
                  '× poids (kg) × durée (h)',
              color: const Color(0xFFEA580C),
            ),
            const FormSectionLabel('Description'),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              maxLength: Activity.maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _controller.setDescription,
              validator: ActivityFormModel.validateDescription,
              decoration: const InputDecoration(
                hintText: 'Lieu, comportement, remarques…',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(
        color: _color,
        saving: form.saving,
        label: form.isEdit ? 'Enregistrer' : 'Ajouter l\'activité',
        icon: Icons.check_rounded,
        onPressed: () => _save(form),
      ),
    );
  }
}
