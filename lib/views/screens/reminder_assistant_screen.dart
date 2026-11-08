import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../controllers/assistant_controller.dart';
import '../../controllers/assistant_tools.dart';
import '../../controllers/gemini_assistant_controller.dart';
import '../../controllers/reminder_assistant_controller.dart';
import '../../controllers/reminders_controller.dart';
import '../../models/activities_model.dart';
import '../../models/assistant/chat_message.dart';
import '../../models/assistant/conversation_model.dart';
import '../../models/assistant/gemini_client.dart';
import '../../models/feeding_model.dart';
import '../../models/health_model.dart';
import '../../models/pets_model.dart';
import '../../models/reminder.dart';
import '../../models/reminder_calculator.dart';
import '../../models/reminders_model.dart';
import '../reminder_style.dart';
import '../sheets/reminder_detail_sheet.dart';
import '../widgets/pet_avatar.dart';

/// Assistant : discussion en français. Avec une clé Gemini, l'assistant
/// Smart Pet répond sur les cinq modules ; sinon l'assistant Rappels
/// fonctionne hors ligne.
class ReminderAssistantScreen extends StatefulWidget {
  const ReminderAssistantScreen({super.key});

  /// Ouvre l'assistant avec son Controller et sa conversation.
  static Future<void> open(BuildContext context) {
    final controller = _create(context);
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Provider<AssistantController>(
        create: (_) => controller,
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<ConversationModel>.value(
            value: context.read<AssistantController>().model,
            child: const ReminderAssistantScreen(),
          ),
        ),
      ),
    ));
  }

  /// Gemini si une clé est configurée (`Provider<LlmClient?>`), sinon
  /// l'assistant hors ligne.
  static AssistantController _create(BuildContext context) {
    final reminders = context.read<RemindersController>();
    final offline = ReminderAssistantController(reminders);
    final llm = _maybeRead<LlmClient?>(context);
    if (llm == null) return offline;
    return GeminiAssistantController(
      llm: llm,
      offline: offline,
      tools: AssistantTools(
        reminders: reminders,
        pets: context.read<PetsModel>(),
        health: context.read<HealthModel>(),
        feeding: context.read<FeedingModel>(),
        activities: context.read<ActivitiesModel>(),
      ),
    );
  }

  static T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  State<ReminderAssistantScreen> createState() =>
      _ReminderAssistantScreenState();
}

class _ReminderAssistantScreenState extends State<ReminderAssistantScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AssistantController get _controller => context.read<AssistantController>();

  void _send(String text) {
    if (text.trim().isEmpty || context.read<ConversationModel>().typing) {
      return;
    }
    _input.clear();
    _controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ConversationModel>();
    // Les cartes affichent l'état à jour des rappels.
    final data = context.watch<RemindersModel>();
    final messages = chat.messages;
    final offset = chat.typing ? 1 : 0;

    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: Colors.white,
        backgroundColor: AppColors.reminderDeep,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.reminderDeep, AppColors.reminder],
            ),
          ),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_controller.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(
                    chat.typing ? 'écrit…' : _controller.modeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Nouvelle conversation',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: chat.typing ? null : _controller.reset,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: messages.length + offset,
              itemBuilder: (context, i) {
                if (chat.typing && i == 0) return const _TypingBubble();
                final m = messages[messages.length - 1 - (i - offset)];
                return _MessageBubble(
                  key: ValueKey(m),
                  message: m,
                  current: (r) => data.byId(r.id) ?? r,
                );
              },
            ),
          ),
          if (chat.suggestions.isNotEmpty)
            _SuggestionBar(
              suggestions: chat.suggestions,
              onTap: _send,
            ),
          _Composer(
            controller: _input,
            enabled: !chat.typing,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.current,
  });

  final ChatMessage message;
  final Reminder Function(Reminder) current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromUser;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    final background = mine
        ? AppColors.reminder
        : message.isError
            ? AppColors.danger.withValues(alpha: 0.1)
            : scheme.surfaceContainerHighest;
    final foreground = mine
        ? Colors.white
        : message.isError
            ? AppColors.danger
            : scheme.onSurface;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Text(message.text,
          style: TextStyle(color: foreground, fontSize: 15, height: 1.35)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.reminder,
                  child: Icon(Icons.smart_toy_rounded,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: bubble),
            ],
          ),
          for (final r in message.reminders)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 6),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _ReminderTile(reminder: current(r)),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 3, left: mine ? 0 : 36, right: 4),
            child: Text(Fmt.time(message.at),
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}

/// Carte compacte d'un rappel cité par l'assistant : ouvre la fiche détail.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final list = context.read<RemindersModel>();
    final scheme = Theme.of(context).colorScheme;
    final r = reminder;
    final pet = list.petOf(r);
    final now = list.now;
    final color = urgencyColor(r, now);

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showReminderDetailSheet(context, r),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: r.type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(r.type.icon, color: r.type.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration:
                            r.isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (pet != null) ...[
                          PetAvatar(pet: pet, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            [if (pet != null) pet.name, Fmt.dateTime(r.dueDate)]
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.isDone
                      ? 'Fait'
                      : ReminderCalculator.countdownLabel(r.dueDate, now),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          label: Text(suggestions[i]),
          labelStyle: const TextStyle(
              color: AppColors.reminder, fontWeight: FontWeight.w600),
          side: BorderSide(color: AppColors.reminder.withValues(alpha: 0.4)),
          backgroundColor: AppColors.reminder.withValues(alpha: 0.06),
          shape: const StadiumBorder(),
          onPressed: () => onTap(suggestions[i]),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                // Message limité : évite les envois démesurés à Gemini.
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: 'Écrivez votre message…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.reminder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Envoyer',
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.reminder,
                  foregroundColor: Colors.white),
              onPressed: enabled ? () => onSend(controller.text) : null,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trois points animés pendant que l'assistant « écrit ».
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 5, bottom: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: 0.3 +
                          0.7 *
                              (1 - ((_controller.value * 3 - i) % 3).clamp(0, 1)),
                      child: const CircleAvatar(
                          radius: 4, backgroundColor: AppColors.reminder),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
