import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminder.dart';
import '../../controllers/reminder_form_controller.dart';
import '../../models/reminder_form_model.dart';
import '../../models/reminder_planning.dart';
import '../reminder_style.dart';
import '../widgets/pet_avatar.dart';

/// Formulaire de création / modification. Affiche le [ReminderFormModel] et
/// transmet chaque saisie au [ReminderFormController] ; la View ne garde
/// que les champs texte.
class ReminderFormScreen extends StatefulWidget {
  const ReminderFormScreen({super.key});

  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;

  ReminderFormController get _controller =>
      context.read<ReminderFormController>();

  @override
  void initState() {
    super.initState();
    final form = context.read<ReminderFormModel>();
    _title = TextEditingController(text: form.title);
    _notes = TextEditingController(text: form.notes);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(ReminderFormModel form) async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await _controller.save();
    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final alerts = form.pendingAlertCount;
    messenger.showSnackBar(SnackBar(
      content: Text(form.isEdit
          ? 'Rappel mis à jour — $alerts notification(s) reprogrammée(s)'
          : 'Rappel créé — $alerts notification(s) programmée(s)'),
    ));
  }

  Future<void> _pickDate(ReminderFormModel form) async {
    final now = form.now;
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: form.day.isBefore(first) ? first : form.day,
      firstDate: form.day.isBefore(first) ? form.day : first,
      lastDate: DateTime(now.year + 10),
      helpText: 'Date de l\'échéance',
    );
    if (picked != null) _controller.setDay(picked);
  }

  Future<void> _pickTime(ReminderFormModel form) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: form.hour, minute: form.minute),
      helpText: 'Heure de l\'échéance',
    );
    if (picked != null) _controller.setTime(picked.hour, picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<ReminderFormModel>();
    final initial = form.initial;
    // Le titre peut être changé par le Controller (choix du type).
    if (_title.text != form.title) _title.text = form.title;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEdit ? 'Modifier le rappel' : 'Nouveau rappel'),
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
            if (initial != null && initial.isAutomatic)
              _Banner(
                icon: Icons.auto_awesome_rounded,
                text: 'Rappel généré automatiquement '
                    '(${initial.source.label}). Il sera mis à jour si '
                    'l\'échéance source change.',
              ),
            if (form.error != null)
              _Banner(
                icon: Icons.error_outline_rounded,
                text: form.error!,
                color: AppColors.danger,
              ),
            const _SectionLabel('Type de rappel'),
            _TypeGrid(selected: form.type, onSelected: _controller.selectType),
            const _SectionLabel('Titre'),
            TextFormField(
              controller: _title,
              maxLength: ReminderFormModel.maxTitleLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ex. Rappel vaccin rage',
                prefixIcon: Icon(form.type.icon, color: form.type.color),
              ),
              onChanged: _controller.setTitle,
              validator: ReminderFormModel.validateTitle,
            ),
            const _SectionLabel('Animal'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tous / général'),
                  avatar: const Icon(Icons.groups_2_outlined, size: 18),
                  selected: form.petId == null,
                  onSelected: (_) => _controller.setPet(null),
                ),
                for (final p in form.pets)
                  ChoiceChip(
                    avatar: PetAvatar(pet: p, size: 22),
                    label: Text(p.name),
                    selected: form.petId == p.id,
                    onSelected: (_) => _controller.setPet(p.id),
                  ),
              ],
            ),
            const _SectionLabel('Échéance'),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _PickerTile(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: Fmt.medium(form.day),
                    onTap: () => _pickDate(form),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _PickerTile(
                    icon: Icons.schedule_rounded,
                    label: 'Heure',
                    value: TimeOfDay(hour: form.hour, minute: form.minute)
                        .format(context),
                    onTap: () => _pickTime(form),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _QuickDates(options: form.quickDates, onPick: _controller.setDay),
            if (form.intervalConflict case final conflict?)
              _IntervalWarning(
                conflict: conflict,
                onUse: () => _controller.setDay(conflict.earliest),
              ),
            const _SectionLabel('Délai d\'alerte'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in AlertOffset.values)
                  FilterChip(
                    label: Text(o.label),
                    selected: form.offsets.contains(o),
                    selectedColor: AppColors.reminder.withValues(alpha: 0.18),
                    checkmarkColor: AppColors.reminder,
                    onSelected: (v) => _controller.toggleOffset(o, v),
                  ),
              ],
            ),
            const _SectionLabel('Répétition'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ReminderRepeat.values)
                  ChoiceChip(
                    avatar: Icon(r.icon, size: 18),
                    label: Text(r.label),
                    selected: form.repeat == r,
                    selectedColor: AppColors.reminder.withValues(alpha: 0.18),
                    showCheckmark: false,
                    onSelected: (_) => _controller.setRepeat(r),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(form.repeat.description,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const _SectionLabel('Notes'),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              maxLength: ReminderFormModel.maxNotesLength,
              onChanged: _controller.setNotes,
              validator: ReminderFormModel.validateNotes,
              decoration: const InputDecoration(
                hintText: 'Clinique, posologie, informations utiles…',
              ),
            ),
            const SizedBox(height: 20),
            _NotificationPreview(form: form),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.reminder,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: form.saving ? null : () => _save(form),
            icon: form.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.notifications_active_rounded),
            label: Text(form.isEdit ? 'Enregistrer' : 'Créer le rappel',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.selected, required this.onSelected});

  final ReminderType selected;
  final ValueChanged<ReminderType> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: [
        for (final t in ReminderType.values)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: t == selected
                  ? t.color.withValues(alpha: 0.14)
                  : Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: t == selected ? t.color : scheme.outlineVariant,
                width: t == selected ? 1.8 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelected(t),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, color: t.color, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          t == selected ? FontWeight.w800 : FontWeight.w600,
                      color: t == selected ? t.color : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).inputDecorationTheme.fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: AppColors.reminder, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickDates extends StatelessWidget {
  const _QuickDates({required this.options, required this.onPick});

  final List<(String, DateTime)> options;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, date) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(label),
                avatar: const Icon(Icons.bolt_rounded,
                    size: 16, color: AppColors.reminder),
                visualDensity: VisualDensity.compact,
                onPressed: () => onPick(date),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.form});

  final ReminderFormModel form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = form.now;
    final all = form.alertSchedule;
    final pending = form.pendingAlertCount;
    final next = form.nextOccurrence;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.reminder.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.reminder.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: AppColors.reminder),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Notifications prévues',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.reminder)),
              ),
              Text('$pending/${all.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.reminder)),
            ],
          ),
          const SizedBox(height: 10),
          if (all.isEmpty)
            const Text('Aucun délai d\'alerte choisi : pas de notification.')
          else
            for (final a in all)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(a.offset.shortLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      child: Text(
                        Fmt.dateTime(a.at),
                        style: TextStyle(
                          color: a.at.isAfter(now)
                              ? null
                              : theme.colorScheme.outline,
                          decoration: a.at.isAfter(now)
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (!a.at.isAfter(now))
                      Text('déjà passée',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline)),
                  ],
                ),
              ),
          if (next != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.repeat_rounded,
                    size: 18, color: AppColors.reminder),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Une fois fait, prochain rappel le ${Fmt.medium(next)}'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.color = AppColors.reminder,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

/// Délai minimal non respecté avec un autre soin du même animal.
class _IntervalWarning extends StatelessWidget {
  const _IntervalWarning({required this.conflict, required this.onUse});

  final IntervalConflict conflict;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final other = conflict.other;
    final otherDate = other.isDone ? (other.completedAt ?? other.dueDate) : other.dueDate;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Moins de ${conflict.rule.days} jours avec « ${other.title} » '
                  '(${Fmt.medium(otherDate)}). Délai conseillé entre '
                  '${conflict.rule.first.label.toLowerCase()} et '
                  '${conflict.rule.second.label.toLowerCase()}. Première date '
                  'possible : ${Fmt.medium(conflict.earliest)}.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onUse, child: const Text('Utiliser cette date')),
          ),
        ],
      ),
    );
  }
}
