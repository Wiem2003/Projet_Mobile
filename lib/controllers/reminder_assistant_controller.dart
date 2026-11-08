import '../models/assistant/assistant_parser.dart';
import '../models/assistant/chat_message.dart';
import '../models/assistant/conversation_model.dart';
import '../models/reminder.dart';
import '../models/reminder_calculator.dart';
import '../models/reminder_exception.dart';
import '../models/reminders_model.dart';
import 'assistant_controller.dart';
import 'reminders_controller.dart';

/// Question en attente d'une réponse (« Pour quand ? », « Lequel ? »,
/// « Je confirme ? »). Renvoie null si le message ne la concerne pas :
/// il est alors traité comme une nouvelle demande.
typedef _Pending = Future<ChatMessage?> Function(String text);

/// Controller de l'assistant Rappels : un chatbot hors ligne.
///
/// Comprend le message (AssistantParser), lit les données dans le
/// [RemindersModel], agit via le [RemindersController] (mêmes règles métier
/// T02 / doublons / T07, même base SQLite, mêmes notifications) et ajoute
/// la réponse au [ConversationModel] observé par l'écran.
class ReminderAssistantController implements AssistantController {
  ReminderAssistantController(
    this._reminders, {
    this.replyDelay = const Duration(milliseconds: 450),
  }) {
    model.restart(_welcome());
  }

  final RemindersController _reminders;
  @override
  final model = ConversationModel();

  @override
  String get title => 'Assistant Rappels';

  @override
  String get modeLabel => 'Hors ligne · vos données restent ici';

  /// Petite pause avant la réponse (indicateur « en train d'écrire »).
  final Duration replyDelay;
  bool _disposed = false;
  _Pending? _pending;

  /// Rappel de la question en cours, reposée si la réponse est incomprise.
  ({String hint, List<Reminder> reminders})? _pendingAsk;
  Future<void> Function()? _undo;

  static const defaultSuggestions = [
    'Quoi de prévu aujourd\'hui ?',
    'Qu\'est-ce qui est en retard ?',
    'Fais le point',
    'Aide',
  ];

  RemindersModel get _data => _reminders.model;
  DateTime get _now => _data.now;
  AssistantParser get _parser =>
      AssistantParser(now: _now, pets: _data.pets);

  // --------------------------------------------------------------- Actions

  @override
  Future<void> send(String text) async {
    final input = text.trim();
    if (input.isEmpty || model.typing) return;
    model
      ..add(ChatMessage(author: ChatAuthor.user, text: input, at: _now))
      ..setTyping(true);

    final answer = await reply(input);
    if (replyDelay > Duration.zero) await Future<void>.delayed(replyDelay);
    if (_disposed) return;
    model
      ..setTyping(false)
      ..add(answer);
  }

  /// Réponse à un message, sans l'ajouter à la conversation (utilisé aussi
  /// par l'assistant Gemini quand il est indisponible).
  Future<ChatMessage> reply(String text) async {
    try {
      return await _respond(text.trim());
    } on ReminderException catch (e) {
      return _bot('⚠️ ${e.message}',
          isError: true, suggestions: defaultSuggestions);
    } on Exception catch (e) {
      return _bot('⚠️ Une erreur est survenue : $e',
          isError: true, suggestions: defaultSuggestions);
    }
  }

  /// Efface la conversation.
  @override
  void reset() {
    _pending = null;
    _undo = null;
    model.restart(_welcome());
  }

  /// Pose une question dont la réponse est attendue au prochain message.
  void _ask(_Pending pending, String hint, [List<Reminder> reminders = const []]) {
    _pending = pending;
    _pendingAsk = (hint: hint, reminders: reminders);
  }

  Future<ChatMessage> _respond(String text) async {
    final pending = _pending;
    final ask = _pendingAsk;
    _pending = null;
    _pendingAsk = null;
    final command = _parser.parse(text);
    if (pending != null) {
      final reply = await pending(text);
      if (reply != null) return reply;
      // Réponse incomprise (ou « oui » à « Lequel ? ») : on garde la
      // question au lieu de l'oublier.
      if (ask != null &&
          (command is UnknownCommand || AssistantParser.isYes(text))) {
        _ask(pending, ask.hint, ask.reminders);
        return _bot('Je n\'ai pas compris votre réponse 🤔 ${ask.hint}',
            reminders: ask.reminders);
      }
    }
    // « Annuler » ne vaut que juste après une action.
    if (command is! UndoCommand) _undo = null;
    return switch (command) {
      HelpCommand() => _help(),
      GreetingCommand() => _greeting(),
      ThanksCommand() =>
        _bot('Avec plaisir ! 🐾', suggestions: defaultSuggestions),
      SummaryCommand() => _summary(),
      UndoCommand() => await _undoLast(),
      ListCommand() => _listReply(command),
      CreateCommand() => _create(command),
      DoneCommand() =>
        await _target(command.query, 'marquer comme fait', _markDone),
      PostponeCommand() => await _target(
          command.query, 'reporter', (r) => _postpone(r, command)),
      DeleteCommand() =>
        await _target(command.query, 'supprimer', _askDelete),
      UnknownCommand() => _unknown(),
      OutOfScopeCommand() => _otherModule(command.topic),
    };
  }

  // ------------------------------------------------------------ Consulter

  ChatMessage _listReply(ListCommand c) {
    final now = _now;
    final base = _data.all.where((r) =>
        (c.petId == null || r.petId == c.petId) &&
        (c.type == null || r.type == c.type));
    final open = base.where((r) => !r.isDone);
    final upcoming = open.where((r) => !r.isOverdue(now)).toList()
      ..sort(_byDue);
    final target = _describe(c);

    switch (c.scope) {
      case ListScope.overdue:
        final items = open.where((r) => r.isOverdue(now)).toList()
          ..sort(_byDue);
        if (items.isEmpty) {
          return _bot('Rien en retard$target 👏 Toutes les échéances passées '
              'ont été traitées.', suggestions: defaultSuggestions);
        }
        return _items(
          '${AssistantFormat.count(items.length, 'rappel')} en retard$target. '
          'Dites « c\'est fait » ou « reporte … à demain » pour les traiter.',
          items,
          suggestions: const ['C\'est fait', 'Fais le point'],
        );
      case ListScope.day:
        final day = c.day!;
        final items = open
            .where((r) => ReminderCalculator.daysUntil(r.dueDate, day) == 0)
            .toList()
          ..sort(_byDue);
        final label = _capitalize(AssistantFormat.day(day, now));
        if (items.isEmpty) {
          return _bot('$label$target : rien de prévu ✨',
              suggestions: defaultSuggestions);
        }
        return _items(
            '$label$target : ${AssistantFormat.count(items.length, 'rappel')}.',
            items);
      case ListScope.week:
      case ListScope.month:
        final days = c.scope == ListScope.week ? 7 : 31;
        final items = upcoming
            .where((r) => ReminderCalculator.daysUntil(r.dueDate, now) <= days)
            .toList();
        final period = c.scope == ListScope.week
            ? 'les 7 prochains jours'
            : 'les 30 prochains jours';
        if (items.isEmpty) {
          return _bot('Rien de prévu dans $period$target ✨',
              suggestions: defaultSuggestions);
        }
        return _items(
            'Dans $period$target : '
            '${AssistantFormat.count(items.length, 'rappel')}.',
            items);
      case ListScope.next:
        if (upcoming.isEmpty) {
          return _bot('Aucun rappel à venir$target.',
              suggestions: defaultSuggestions);
        }
        final r = upcoming.first;
        return _bot(
          'Prochain rappel$target : « ${r.title} »${_petSuffix(r)}, '
          '${AssistantFormat.when(r.dueDate, now)} '
          '(${ReminderCalculator.relativeSentence(r.dueDate, now)}).',
          reminders: [r],
          suggestions: defaultSuggestions,
        );
      case ListScope.upcoming:
        if (upcoming.isEmpty) {
          return _bot('Aucun rappel à venir$target. Voulez-vous en créer un ?',
              suggestions: [_createExample(), 'Aide']);
        }
        return _items(
            '${AssistantFormat.count(upcoming.length, 'rappel')} '
            'à venir$target. Les plus proches :',
            upcoming);
      case ListScope.done:
        final items = base.where((r) => r.isDone).toList()
          ..sort((a, b) => (b.completedAt ?? b.dueDate)
              .compareTo(a.completedAt ?? a.dueDate));
        if (items.isEmpty) {
          return _bot('Aucun rappel terminé$target pour le moment.',
              suggestions: defaultSuggestions);
        }
        return _items(
            '${AssistantFormat.count(items.length, 'rappel terminé', 'rappels terminés')}'
            '$target. Les plus récents :',
            items);
    }
  }

  /// Message avec au plus 5 cartes de rappels.
  ChatMessage _items(String text, List<Reminder> items,
      {List<String> suggestions = defaultSuggestions}) {
    const max = 5;
    final more = items.length - max;
    return _bot(
      more > 0 ? '$text\n(+ $more autres dans l\'onglet Rappels)' : text,
      reminders: items.take(max).toList(),
      suggestions: suggestions,
    );
  }

  ChatMessage _summary() {
    final now = _now;
    final all = _data.all;
    if (all.isEmpty) {
      return _bot('Vous n\'avez encore aucun rappel. Dites par exemple :\n'
          '« ${_createExample()} »', suggestions: [_createExample(), 'Aide']);
    }
    final s = ReminderStats.compute(all, now);
    final next = all.where((r) => !r.isDone && !r.isOverdue(now)).toList()
      ..sort(_byDue);
    final lines = [
      'Voici le point 📋',
      '• ${AssistantFormat.count(s.overdue, 'rappel')} en retard',
      '• ${s.today} aujourd\'hui',
      '• ${s.next7Days} dans les 7 prochains jours',
      '• ${s.doneThisMonth} ${s.doneThisMonth > 1 ? 'faits' : 'fait'} ce mois-ci',
      if (next.isNotEmpty)
        'Prochain : « ${next.first.title} »${_petSuffix(next.first)}, '
            '${AssistantFormat.when(next.first.dueDate, now)}.',
    ];
    return _bot(lines.join('\n'),
        reminders: next.take(1).toList(),
        suggestions: [
          if (s.overdue > 0) 'Qu\'est-ce qui est en retard ?',
          'Quoi de prévu cette semaine ?',
          'Aide',
        ]);
  }

  // ---------------------------------------------------------------- Créer

  ChatMessage _create(CreateCommand c) {
    final when = c.when;
    if (when == null) {
      _ask(_awaitDate((w) async => _confirmCreate(c, w)), _dateHint);
      return _bot('Pour quand dois-je programmer « ${c.title} » ?',
          suggestions: const ['Demain à 9h', 'Samedi à 10h', 'Dans une semaine']);
    }
    return _confirmCreate(c, when);
  }

  ChatMessage _confirmCreate(CreateCommand c, AssistantWhen when) {
    final due = when.resolve();
    if (!due.isAfter(_now)) {
      _ask(_awaitDate((w) async => _confirmCreate(c, w)), _dateHint);
      return _bot(
          'Cette date est déjà passée (${AssistantFormat.when(due, _now)}). '
          'Pour quand plutôt ?',
          isError: true,
          suggestions: const ['Demain à 9h', 'Dans 3 jours', 'Dans une semaine']);
    }
    final draft = Reminder(
      petId: c.petId,
      title: c.title,
      type: c.type,
      dueDate: due,
      repeat: c.repeat ??
          (c.type == ReminderType.vaccination
              ? ReminderRepeat.yearly
              : ReminderRepeat.none),
    );
    _ask(_confirm(() => _doCreate(draft)),
        'Répondez « oui » pour créer le rappel, ou « non » pour annuler.');
    final pet = _petName(draft.petId);
    return _bot(
      [
        'Je crée ce rappel ?',
        '📌 ${draft.title} (${draft.type.label})',
        if (pet != null) '🐾 $pet',
        '📅 ${_capitalize(AssistantFormat.when(due, _now))}',
        if (draft.repeat != ReminderRepeat.none) '🔁 ${draft.repeat.description}',
        '🔔 ${draft.alertOffsets.map((o) => o.shortLabel).join(' + ')}',
      ].join('\n'),
      suggestions: const ['Oui', 'Non'],
    );
  }

  Future<ChatMessage> _doCreate(Reminder draft) async {
    final saved = await _reminders.save(draft);
    _undo = () => _reminders.delete(saved);
    final alerts = ReminderCalculator.pendingAlerts(saved, _now).length;
    return _bot(
      'C\'est noté ✅ « ${saved.title} » '
      '${AssistantFormat.when(saved.dueDate, _now)}.\n'
      '${AssistantFormat.count(alerts, 'notification programmée', 'notifications programmées')}.',
      reminders: [saved],
      suggestions: const ['Annuler', 'Quoi de prévu cette semaine ?'],
    );
  }

  // ----------------------------------------- Terminer, reporter, supprimer

  /// Retrouve le rappel visé, ou demande lequel si plusieurs correspondent.
  Future<ChatMessage> _target(ReminderQuery q, String verb,
      Future<ChatMessage> Function(Reminder) action) async {
    final open = _data.all.where((r) => !r.isDone).toList();
    final found = q.match(open, _now);
    if (found.isEmpty) {
      return _bot(
          open.isEmpty
              ? 'Vous n\'avez aucun rappel en cours.'
              : 'Je n\'ai trouvé aucun rappel en cours correspondant. '
                  'Précisez le titre, par exemple « le vermifuge de Rex ».',
          suggestions: const ['Mes rappels à venir', 'Aide']);
    }
    if (found.length == 1) return action(found.single);
    final options = found.take(4).toList();
    _ask(
        _choose(options, action),
        'Répondez « le premier », « le 2 »… ou précisez (ex. « celui de '
        '${_examplePet()} »). Dites « annuler » pour abandonner.',
        options);
    return _bot('Plusieurs rappels correspondent. Lequel voulez-vous $verb ?',
        reminders: options,
        suggestions: [
          for (var i = 0; i < options.length; i++) _choiceLabel(i, options[i]),
          'Non',
        ]);
  }

  Future<ChatMessage> _markDone(Reminder r) async {
    final result = await _reminders.markDone(r);
    _undo = () => _reminders.undoDone(result);
    final next = result.next;
    return _bot(
      next == null
          ? '« ${r.title} » est marqué comme fait ✅'
          : '« ${r.title} » est marqué comme fait ✅\n'
              'Prochain rappel ${AssistantFormat.when(next.dueDate, _now)} 🔁',
      reminders: [?next],
      suggestions: const ['Annuler', 'Fais le point'],
    );
  }

  Future<ChatMessage> _postpone(Reminder r, PostponeCommand c) async {
    DateTime at(AssistantWhen w) => w.resolve(
        defaultHour: r.dueDate.hour, defaultMinute: r.dueDate.minute);
    final delta = c.delta;
    if (delta != null) {
      return _doPostpone(
          r,
          delta.inDays > 0
              ? ReminderCalculator.postponeBy(r.dueDate, _now, delta)
              : ReminderCalculator.postponeBase(r.dueDate, _now).add(delta));
    }
    if (c.when != null) return _doPostpone(r, at(c.when!));
    _ask(_awaitDate((w) => _doPostpone(r, at(w))), _dateHint);
    return _bot('À quand voulez-vous reporter « ${r.title} » ?',
        reminders: [r],
        suggestions: const ['Demain', 'Dans 3 jours', 'Dans une semaine']);
  }

  Future<ChatMessage> _doPostpone(Reminder r, DateTime date) async {
    final saved = await _reminders.postpone(r, date);
    return _bot(
      'C\'est reporté 💤 « ${saved.title} » '
      '${AssistantFormat.when(saved.dueDate, _now)}.\n'
      'Les notifications ont été reprogrammées.',
      reminders: [saved],
      suggestions: defaultSuggestions,
    );
  }

  Future<ChatMessage> _askDelete(Reminder r) async {
    _ask(_confirm(() async {
      await _reminders.delete(r);
      return _bot('Rappel « ${r.title} » supprimé 🗑️',
          suggestions: defaultSuggestions);
    }), 'Répondez « oui » pour supprimer, ou « non » pour garder le rappel.');
    return _bot(
      'Supprimer définitivement « ${r.title} »${_petSuffix(r)}, prévu '
      '${AssistantFormat.when(r.dueDate, _now)} ?'
      '${r.isAutomatic ? '\nIl a été créé automatiquement depuis : ${r.source.label}.' : ''}',
      reminders: [r],
      suggestions: const ['Oui, supprimer', 'Non'],
    );
  }

  Future<ChatMessage> _undoLast() async {
    final undo = _undo;
    _undo = null;
    if (undo == null) {
      return _bot('Il n\'y a rien à annuler.', suggestions: defaultSuggestions);
    }
    await undo();
    return _bot('C\'est annulé ↩️', suggestions: defaultSuggestions);
  }

  // ----------------------------------------------------- Questions en cours

  _Pending _confirm(Future<ChatMessage> Function() onYes) => (text) async {
        if (AssistantParser.isYes(text)) return onYes();
        if (AssistantParser.isNo(text)) return _cancelled();
        return null;
      };

  _Pending _awaitDate(Future<ChatMessage> Function(AssistantWhen) onDate) =>
      (text) async {
        if (AssistantParser.isNo(text)) return _cancelled();
        if (text.contains('?')) return null; // Nouvelle question.
        final when = _parser.parseWhen(text);
        return when == null ? null : onDate(when);
      };

  _Pending _choose(List<Reminder> options,
          Future<ChatMessage> Function(Reminder) onPick) =>
      (text) async {
        if (AssistantParser.isNo(text)) return _cancelled();
        final t = normalizeFr(text);
        // « 2 », « le 2 », « numéro 2 », « le 2e ».
        final number =
            RegExp(r'^\s*(?:le |la |numero |n°\s*)?(\d+)(?:e|eme|er)?\b')
                .firstMatch(t);
        var index = number == null ? -1 : int.parse(number[1]!) - 1;
        if (index < 0) {
          index = switch (RegExp(r'\b(premier|1er|deuxieme|second|troisieme|'
                  r'quatrieme|dernier)\b')
              .firstMatch(t)
              ?.group(1)) {
            'premier' || '1er' => 0,
            'deuxieme' || 'second' => 1,
            'troisieme' => 2,
            'quatrieme' => 3,
            'dernier' => options.length - 1,
            _ => -1,
          };
        }
        if (index >= 0 && index < options.length) return onPick(options[index]);
        final q = _parser.parseQuery(text);
        final picked = q.isEmpty ? const <Reminder>[] : q.match(options, _now);
        return picked.length == 1 ? onPick(picked.single) : null;
      };

  static const _dateHint = 'Indiquez une date, par exemple « demain à 9h », '
      '« samedi » ou « le 20/11 », ou dites « annuler ».';

  /// Questions des autres modules : orienter vers le bon onglet.
  ChatMessage _otherModule(OtherTopic topic) {
    final (tab, what) = switch (topic) {
      OtherTopic.healthSpending =>
        ('Santé', 'les dépenses médicales par période'),
      OtherTopic.foodSpending =>
        ('Repas', 'la dépense alimentaire du mois et son évolution'),
      OtherTopic.spending => ('Santé et Repas',
          'les dépenses médicales (Santé) et alimentaires (Repas)'),
      OtherTopic.weight =>
        ('Santé', 'le poids moyen et la courbe d\'évolution du poids'),
      OtherTopic.petInfo =>
        ('Accueil → Mes animaux', 'la fiche complète de chaque animal'),
      OtherTopic.food => ('Repas', 'les quantités et la moyenne quotidienne'),
      OtherTopic.activity =>
        ('Activité', 'la distance hebdomadaire, la durée et les calories'),
    };
    return _bot(
      'Je m\'occupe uniquement des rappels 🔔. Pour cette question, ouvrez '
      'l\'onglet $tab : vous y trouverez $what.',
      suggestions: defaultSuggestions,
    );
  }

  ChatMessage _cancelled() =>
      _bot('D\'accord, j\'annule 👍', suggestions: defaultSuggestions);

  // ---------------------------------------------------------- Messages fixes

  ChatMessage _welcome() => _bot(
        'Bonjour 👋 Je suis votre assistant Rappels.\n'
        'Posez-moi une question ou donnez-moi une consigne en français. '
        'Je fonctionne hors ligne, directement sur vos rappels.',
        suggestions: [
          'Quoi de prévu aujourd\'hui ?',
          'Qu\'est-ce qui est en retard ?',
          _createExample(),
          'Aide',
        ],
      );

  ChatMessage _greeting() {
    final s = ReminderStats.compute(_data.all, _now);
    final status = s.overdue > 0
        ? 'Attention : ${AssistantFormat.count(s.overdue, 'rappel')} en retard.'
        : s.today > 0
            ? '${AssistantFormat.count(s.today, 'rappel')} aujourd\'hui.'
            : 'Tout est à jour ✅';
    return _bot('Bonjour 👋 $status Que puis-je faire pour vous ?',
        suggestions: defaultSuggestions);
  }

  ChatMessage _help() => _bot(
        'Je comprends des phrases simples, sans connexion Internet :\n'
        '• Consulter : « Quoi de prévu demain ? », « Qu\'est-ce qui est en '
        'retard ? », « Prochain vaccin de ${_examplePet()} ? »\n'
        '• Créer : « ${_createExample()} »\n'
        '• Terminer : « J\'ai donné le vermifuge »\n'
        '• Reporter : « Reporte l\'antipuces à lundi » ou « … de 3 jours »\n'
        '• Supprimer : « Supprime le rendez-vous »\n'
        '• Bilan : « Fais le point »\n'
        'Après une action, dites « annuler » pour revenir en arrière.',
        suggestions: [
          'Quoi de prévu cette semaine ?',
          _createExample(),
          'Fais le point',
        ],
      );

  ChatMessage _unknown() => _bot(
        'Je n\'ai pas bien compris 🤔 Essayez par exemple :\n'
        '« Quoi de prévu demain ? » ou « ${_createExample()} »',
        suggestions: defaultSuggestions,
      );

  // ---------------------------------------------------------------- Outils

  ChatMessage _bot(String text,
          {List<Reminder> reminders = const [],
          List<String> suggestions = const [],
          bool isError = false}) =>
      ChatMessage(
        author: ChatAuthor.assistant,
        text: text,
        at: _now,
        reminders: reminders,
        suggestions: suggestions,
        isError: isError,
      );

  static int _byDue(Reminder a, Reminder b) => a.dueDate.compareTo(b.dueDate);

  String? _petName(int? id) {
    for (final p in _data.pets) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  String _petSuffix(Reminder r) {
    final name = _petName(r.petId);
    return name == null ? '' : ' ($name)';
  }

  String _describe(ListCommand c) {
    final pet = _petName(c.petId);
    return [
      if (pet != null) ' pour $pet',
      if (c.type != null) ' · ${c.type!.label.toLowerCase()}',
    ].join();
  }

  String _choiceLabel(int i, Reminder r) {
    final pet = _petName(r.petId);
    return '${i + 1}. ${r.title}${pet == null ? '' : ' · $pet'} · '
        '${AssistantFormat.short(r.dueDate)}';
  }

  String _examplePet() => _data.pets.isEmpty ? 'mon chien' : _data.pets.first.name;

  String _createExample() => _data.pets.isEmpty
      ? 'Rappelle-moi d\'acheter des croquettes samedi'
      : 'Rappelle-moi le vermifuge de ${_data.pets.first.name} demain à 9h';

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void dispose() {
    _disposed = true;
    model.dispose();
  }
}
