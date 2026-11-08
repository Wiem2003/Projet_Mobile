import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/pet_form_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/pet.dart';
import '../../models/pet_form_model.dart';
import '../formatters.dart';
import '../widgets/form_parts.dart';
import '../widgets/input_formatters.dart';
import '../widgets/pet_photo.dart';

/// Formulaire « Ajouter / Modifier un animal ». Affiche le [PetFormModel]
/// et transmet chaque saisie au [PetFormController].
class PetFormScreen extends StatefulWidget {
  const PetFormScreen({super.key});

  @override
  State<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends State<PetFormScreen> {
  static const _color = AppColors.pet;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _weight;
  late final TextEditingController _colorText;
  late final TextEditingController _identification;
  late final TextEditingController _allergies;

  PetFormController get _controller => context.read<PetFormController>();

  @override
  void initState() {
    super.initState();
    final form = context.read<PetFormModel>();
    _name = TextEditingController(text: form.name);
    _breed = TextEditingController(text: form.breed);
    _weight = TextEditingController(text: form.weight);
    _colorText = TextEditingController(text: form.color);
    _identification = TextEditingController(text: form.identification);
    _allergies = TextEditingController(text: form.allergies);
  }

  @override
  void dispose() {
    for (final c in [_name, _breed, _weight, _colorText, _identification, _allergies]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(PetFormModel form) async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await _controller.save();
    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, saved);
    messenger.showSnackBar(SnackBar(
      content: Text(form.isEdit
          ? 'Fiche de ${saved.name} mise à jour'
          : 'Fiche de ${saved.name} créée'),
    ));
  }

  Future<void> _pickBirthDate(PetFormModel form) async {
    final now = form.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: form.birthDate ?? DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Date de naissance',
    );
    if (picked != null) _controller.setBirthDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<PetFormModel>();
    final age = form.ageLabel;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEdit ? 'Modifier ${form.initial!.name}' : 'Nouvel animal'),
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
            if (form.error != null)
              FormBanner(
                icon: Icons.error_outline_rounded,
                text: form.error!,
                color: AppColors.danger,
              ),
            const SizedBox(height: 12),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PetPhoto(
                    species: form.species,
                    path: form.photoPath,
                    color: _color,
                    size: 120,
                  ),
                  if (form.pickingPhoto)
                    const CircularProgressIndicator(color: _color),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: form.pickingPhoto
                      ? null
                      : () => _controller.pickPhoto(camera: true),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Appareil photo'),
                ),
                TextButton.icon(
                  onPressed: form.pickingPhoto
                      ? null
                      : () => _controller.pickPhoto(camera: false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
                if (form.photoPath != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: _controller.removePhoto,
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Retirer'),
                  ),
              ],
            ),
            const FormSectionLabel('Nom'),
            TextFormField(
              controller: _name,
              maxLength: Pet.maxNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Ex. Rex',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: _controller.setName,
              validator: PetFormModel.validateName,
            ),
            const FormSectionLabel('Espèce'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in Species.values)
                  ChoiceChip(
                    avatar: Text(s.emoji),
                    label: Text(s.label),
                    selected: form.species == s,
                    onSelected: (_) => _controller.setSpecies(s),
                  ),
              ],
            ),
            const FormSectionLabel('Race'),
            TextFormField(
              controller: _breed,
              maxLength: Pet.maxTextLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. Berger allemand',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              onChanged: _controller.setBreed,
              validator: PetFormModel.validateBreed,
            ),
            const FormSectionLabel('Sexe'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PetSex>(
                showSelectedIcon: false,
                segments: [
                  for (final s in PetSex.values)
                    ButtonSegment(
                        value: s, label: Text('${s.symbol} ${s.label}')),
                ],
                selected: {form.sex},
                onSelectionChanged: (s) => _controller.setSex(s.first),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stérilisé(e)'),
              subtitle: const Text('Utilisé pour la ration conseillée'),
              value: form.sterilized,
              onChanged: _controller.setSterilized,
            ),
            FormSectionLabel(
              'Date de naissance',
              trailing: form.birthDate == null
                  ? null
                  : TextButton(
                      onPressed: () => _controller.setBirthDate(null),
                      child: const Text('Effacer'),
                    ),
            ),
            PickerTile(
              icon: Icons.cake_outlined,
              label: age == null ? 'Facultative' : 'Âge : $age',
              value: form.birthDate == null
                  ? 'Choisir une date'
                  : Fmt.long(form.birthDate!),
              color: _color,
              onTap: () => _pickBirthDate(form),
              error: form.birthDateError,
            ),
            const FormSectionLabel('Poids'),
            TextFormField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. 12,5',
                suffixText: 'kg',
                prefixIcon: Icon(Icons.monitor_weight_outlined),
                helperText: 'Mis à jour à chaque pesée du module Santé',
              ),
              inputFormatters: [DecimalInputFormatter(decimals: 3, maxDigits: 4)],
              onChanged: _controller.setWeight,
              validator: form.weightError,
            ),
            const FormSectionLabel('Couleur'),
            TextFormField(
              controller: _colorText,
              maxLength: Pet.maxTextLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. Noir et feu',
                prefixIcon: Icon(Icons.palette_outlined),
              ),
              onChanged: _controller.setColor,
              validator: PetFormModel.validateColor,
            ),
            const FormSectionLabel('Numéro d\'identification'),
            TextFormField(
              controller: _identification,
              maxLength: Pet.maxIdentificationLength,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Facultatif — puce (15 chiffres) ou tatouage',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
              inputFormatters: [IdentificationInputFormatter()],
              onChanged: _controller.setIdentification,
              validator: PetFormModel.validateIdentification,
            ),
            const FormSectionLabel('Allergies'),
            TextFormField(
              controller: _allergies,
              maxLength: Pet.maxAllergiesLength,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Facultatif — ex. amoxicilline, poulet',
                prefixIcon: Icon(Icons.warning_amber_rounded),
              ),
              onChanged: _controller.setAllergies,
              validator: PetFormModel.validateAllergies,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(
        color: _color,
        saving: form.saving,
        label: form.isEdit ? 'Enregistrer' : 'Ajouter l\'animal',
        icon: Icons.check_rounded,
        onPressed: () => _save(form),
      ),
    );
  }
}
