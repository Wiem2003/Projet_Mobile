import '../../core/pets/pet_directory.dart';
import '../reminder.dart';
import 'assistant_command.dart';

export 'assistant_command.dart';

/// Compréhension des messages en français, entièrement locale : aucune
/// connexion ni service externe (critère T09).
///
/// Exemples reconnus :
/// - « Qu'est-ce qui est prévu demain ? », « Quoi en retard pour Mia ? »
/// - « Rappelle-moi le vermifuge de Rex vendredi à 8h »
/// - « J'ai donné le vermifuge », « Reporte l'antipuces à lundi »
/// - « Supprime le rendez-vous », « Fais le point »
class AssistantParser {
  AssistantParser({required this.now, this.pets = const []});

  final DateTime now;
  final List<PetSummary> pets;

  // ------------------------------------------------------------ Oui / non

  static final _yes = RegExp(
      r"^\s*(oui|ouais|yes|ok|okay|d'accord|dac|confirme[rsz]?|valide[rsz]?|"
      r"vas[- ]y|go|parfait|c'est bon|bien sur|exactement)\b");
  static final _no = RegExp(
      r"^\s*(non|nan|no|annule[rsz]?|laisse tomber|stop|pas maintenant|surtout pas)\b");

  static bool isYes(String text) => _yes.hasMatch(normalizeFr(text));
  static bool isNo(String text) => _no.hasMatch(normalizeFr(text));

  // ------------------------------------------------------------- Intentions

  static final _undo = RegExp(
      r"^(annuler?|annule (ca|cela|la derniere action)|defais|defaire|undo)\W*$");
  static final _help = RegExp(
      r"\b(aide|help|que (peux|sais)[- ]tu|qu'est[- ]ce que tu (peux|sais)|"
      r"tu (peux|sais) faire quoi|tu sers a quoi|commandes|exemples?)\b");
  static final _thanks = RegExp(r"^\W*(merci|thanks|super merci|top)\b");
  static final _greeting =
      RegExp(r"^\W*(bonjour|salut|hello|coucou|bonsoir|hey|slt|bjr)\b");
  static final _doneList = RegExp(
      r"\b(historique|termines|terminees|deja faits?|rappels faits|"
      r"qu'est[- ]ce que j'ai (deja )?fait|ce que j'ai (deja )?fait)\b");
  static final _create = RegExp(
      r"(\brap+el+e?[- ]?(moi|nous)\b|fais[- ]moi penser|nouveau rappel|"
      r"^\s*(?:(?:peux[- ]tu|tu peux|pourrais[- ]tu)\s+)?"
      r"(cree[rz]?|ajoute[rz]?|programme[rz]?|planifie[rz]?|note[rz]?)\b)");
  static final _postpone = RegExp(
      r"\b(reporte[rz]?|decale[rz]?|repousse[rz]?|remets|remettre|deplace[rz]?)\b");
  static final _delete = RegExp(
      r"\b(supprime[rz]?|efface[rz]?|enleve[rz]?|retire[rz]?)\b|"
      r"^\s*annule[rz]?\s+(?=(le|la|les|l'|mon|ma|mes)\b)");
  static final _done = RegExp(
      r"(\bc'est fait\b|\bj'ai (deja |bien )?(fait|donne|achete|termine|effectue|pris|mis|eu)\b|"
      r"\bmarque[rz]?\b.*\b(fait|faite|termine|terminee)\b|"
      r"\b(fait|faite|termine|terminee|effectue|regle)[\s.!]*$|"
      r"^\s*(fait|termine|valide)\b)");
  static final _overdue =
      RegExp(r"\b(retard|depasse\w*|oublie\w*|manque\w*|echu\w*)\b");
  static final _week = RegExp(r"\b(semaine|7 jours|sept jours|8 jours|huit jours)\b");
  static final _month = RegExp(r"\b(ce mois|du mois|30 jours|trente jours)\b");
  static final _next = RegExp(r"\b(prochaine?s?|quand)\b");
  static final _summary = RegExp(
      r"\b(resume|recap\w*|bilan|point|statistiques?|stats|combien|situation)\b");
  // Questions des autres modules (Santé, Repas, Activités, Animaux).
  static final _money = RegExp(
      r"\b(depense\w*|depenser|cout\w*|coute\w*|prix|paye\w*|argent|budget|"
      r"factures?|euros?|dinars?|dt)\b");
  static final _healthWords = RegExp(
      r"\b(veto\w*|veterinaire\w*|sante|soins?|medica\w*|consultations?|"
      r"vaccins?|analyses?)\b");
  static final _foodWords = RegExp(
      r"\b(croquettes?|nourriture|alimentation|repas|patee|friandises?)\b");
  static final _weight =
      RegExp(r"\b(poids|pese\w*|kilos?|kg|grossi\w*|maigri\w*)\b");
  static final _petInfo = RegExp(
      r"\b(quel age|son age|ne le|nee? quand|race|puce|tatouage|"
      r"numero d'identification)\b");
  static final _foodStats =
      RegExp(r"\b(mange\w*|quantite|grammes?|combien de repas)\b");
  static final _activityStats = RegExp(
      r"\b(distance|km|kilometres?|calories?|marche\w*|couru|activites?)\b");

  static final _upcoming = RegExp(
      r"\b(a venir|prevue?s?|programmee?s?|rappels?|agenda|planning|liste|"
      r"tout|tous|toutes|echeances?|quoi de neuf)\b");

  /// Analyse un message et renvoie l'intention reconnue.
  AssistantCommand parse(String text) {
    final s = _Scan(text);
    final t = s.norm.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return const UnknownCommand();
    if (_undo.hasMatch(t)) return const UndoCommand();
    if (_help.hasMatch(t)) return const HelpCommand();
    if (_thanks.hasMatch(t)) return const ThanksCommand();
    if (_greeting.hasMatch(t) && t.split(' ').length <= 3) {
      return const GreetingCommand();
    }

    final type = typeIn(t);
    if (_doneList.hasMatch(t)) {
      return ListCommand(ListScope.done, petId: _takePet(s), type: type);
    }
    if (s.take(_create) != null) return _parseCreate(s, type)!;
    if (s.take(_postpone) != null) {
      final delta = _takeDelta(s);
      final when = delta == null ? _takeWhen(s) : null;
      return PostponeCommand(_query(s, type), when: when, delta: delta);
    }
    if (s.take(_delete) != null) return DeleteCommand(_query(s, type));
    if (s.take(_done) != null) return DoneCommand(_query(s, type));
    final terse = _terseCreate(text, type);
    if (terse != null) return terse;
    final other = _otherTopic(t);
    if (other != null) return OutOfScopeCommand(other);
    return _parseList(s, t, type);
  }

  /// « rappel vaccin Rex 15/12 10h » : création sans verbe, seulement si
  /// une date et un objet sont donnés (sinon c'est une recherche).
  CreateCommand? _terseCreate(String text, ReminderType? type) {
    final t = normalizeFr(text).trim();
    if (t.contains('?') || !RegExp(r"^(?:un |nouveau )?rappel ").hasMatch(t)) {
      return null;
    }
    return _parseCreate(_Scan(text), type, strict: true);
  }

  static OtherTopic? _otherTopic(String t) {
    if (_money.hasMatch(t)) {
      if (_foodWords.hasMatch(t)) return OtherTopic.foodSpending;
      if (_healthWords.hasMatch(t)) return OtherTopic.healthSpending;
      return OtherTopic.spending;
    }
    if (_weight.hasMatch(t)) return OtherTopic.weight;
    if (_petInfo.hasMatch(t)) return OtherTopic.petInfo;
    if (_foodStats.hasMatch(t)) return OtherTopic.food;
    if (_activityStats.hasMatch(t)) return OtherTopic.activity;
    return null;
  }

  /// Lit uniquement une date (réponse à « Pour quand ? »).
  AssistantWhen? parseWhen(String text) => _takeWhen(_Scan(text));

  /// Critères de recherche d'un rappel (réponse à « Lequel ? »).
  ReminderQuery parseQuery(String text) {
    final s = _Scan(text);
    return _query(s, typeIn(s.norm));
  }

  AssistantCommand _parseList(_Scan s, String t, ReminderType? type) {
    final pet = _takePet(s);
    ListCommand list(ListScope scope, [DateTime? day]) =>
        ListCommand(scope, day: day, petId: pet, type: type);

    if (_overdue.hasMatch(t)) return list(ListScope.overdue);
    if (_week.hasMatch(t)) return list(ListScope.week);
    if (_month.hasMatch(t)) return list(ListScope.month);
    final when = _takeWhen(s);
    if (when != null) return list(ListScope.day, when.day);
    if (_next.hasMatch(t)) return list(ListScope.next);
    if (_summary.hasMatch(t) && !t.contains('bilan de sante')) {
      return const SummaryCommand();
    }
    if (_upcoming.hasMatch(t) || pet != null || type != null) {
      return list(ListScope.upcoming);
    }
    return const UnknownCommand();
  }

  /// [strict] : renvoie null sans date ou sans objet (forme courte).
  CreateCommand? _parseCreate(_Scan s, ReminderType? type, {bool strict = false}) {
    final repeat = _takeRepeat(s);
    final when = _takeWhen(s);
    final pet = _takePet(s);
    s.take(RegExp(r"\b(?:un |une |le |nouveau )?rappel\b"));
    final (original, normalized) = s.remainder();
    final kind = type ?? ReminderType.other;
    var title = _cleanTitle(original, normalized);
    if (strict && (when == null || title.isEmpty)) return null;
    if (title.isEmpty) title = kind.defaultTitle;
    if (title.length > 80) title = title.substring(0, 80).trim();
    return CreateCommand(
      title: title,
      type: kind,
      petId: pet,
      when: when,
      repeat: repeat,
    );
  }

  ReminderQuery _query(_Scan s, ReminderType? type) {
    final pet = _takePet(s);
    _takeWhen(s); // Une date éventuelle ne fait pas partie du nom.
    final words = s.work
        .split(RegExp(r"[^a-z0-9]+"))
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .toList();
    return ReminderQuery(words: words, petId: pet, type: type);
  }

  // ------------------------------------------------------------- Éléments

  /// Type de rappel évoqué par des mots-clés (« vaccin », « croquettes »...).
  static ReminderType? typeIn(String normalized) {
    for (final (type, re) in _typeWords) {
      if (re.hasMatch(normalized)) return type;
    }
    return null;
  }

  static final _typeWords = [
    (ReminderType.vaccination,
        RegExp(r"\bvaccin\w*|\brage\b|\bchppi\b|\btyphus\b")),
    (ReminderType.deworming, RegExp(r"\bvermifug\w*")),
    (ReminderType.vetAppointment,
        RegExp(r"\brendez[- ]vous\b|\brdv\b|\bveto\w*|\bveterinaire\w*|"
            r"\bclinique\b|\bconsultation\b")),
    (ReminderType.checkup,
        RegExp(r"\bcontroles?\b|\bbilan de sante\b|\bcheck[- ]?up\b|"
            r"\bvisite annuelle\b|\bpesee\b")),
    (ReminderType.treatment,
        RegExp(r"\btraitements?\b|\bmedicaments?\b|\bantipuces?\b|"
            r"\bpipettes?\b|\bcomprimes?\b|\bantibio\w*|\bgouttes?\b|\bsoins?\b")),
    (ReminderType.purchase,
        RegExp(r"\bachat\w*|\bachete\w*|\bcroquettes?\b|\bnourriture\b|"
            r"\blitiere\b|\bpatee\b|\bstock\b|\bcourses?\b")),
  ];

  int? _takePet(_Scan s) {
    const prefix = r"(?:\b(?:pour|a|de|du|chez|avec)\s+)?";
    for (final p in pets) {
      final name = RegExp.escape(normalizeFr(p.name));
      if (s.take(RegExp('$prefix\\b$name\\b')) != null) return p.id;
    }
    // « mon chien » quand un seul animal est de cette espèce.
    for (final p in pets) {
      final species = p.species;
      if (species == null) continue;
      final same = pets.where((o) => o.species == species).length;
      if (same != 1) continue;
      final word = RegExp.escape(normalizeFr(species));
      if (s.take(RegExp('$prefix\\b(?:mon|ma|le|la)\\s+$word\\b')) != null) {
        return p.id;
      }
    }
    return null;
  }

  ReminderRepeat? _takeRepeat(_Scan s) {
    if (s.take(RegExp(r"\b(?:chaque|tous les|toutes les)\s+semaines?\b|"
            r"\bhebdo(?:madaire)?\b|"
            r"\b(?:chaque|tous les)\s+(?=(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche))")) !=
        null) {
      return ReminderRepeat.weekly;
    }
    if (s.take(RegExp(r"\b(?:chaque|tous les)\s+mois\b|\bmensuel(?:le)?\b|"
            r"\bune fois par mois\b")) !=
        null) {
      return ReminderRepeat.monthly;
    }
    if (s.take(RegExp(r"\bsaisonni(?:er|ere)\b|\ben saison\b")) != null) {
      return ReminderRepeat.seasonal;
    }
    if (s.take(RegExp(r"\b(?:chaque|tous les|toutes les)\s+(?:ans?|annees?)\b|"
            r"\bannuel(?:le)?\b|\bune fois par an\b")) !=
        null) {
      return ReminderRepeat.yearly;
    }
    return null;
  }

  /// « de 3 jours », « d'une semaine » (report relatif à l'échéance).
  Duration? _takeDelta(_Scan s) {
    final m = s.take(RegExp(r"\b(?:de\s+|d')\s*(\d+|un|une|deux|trois|quatre|"
        r"cinq|six|sept|huit|neuf|dix|quinze)\s*"
        r"(minutes?|mins?|heures?|h|jours?|j|semaines?|mois)\b"));
    if (m == null) return null;
    final n = _number(m[1]!);
    final unit = m[2]!;
    if (unit.startsWith('min')) return Duration(minutes: n);
    if (unit.startsWith('h')) return Duration(hours: n);
    if (unit.startsWith('j')) return Duration(days: n);
    if (unit.startsWith('s')) return Duration(days: 7 * n);
    return Duration(days: 30 * n);
  }

  static const _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static const _months = [
    'janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout',
    'septembre', 'octobre', 'novembre', 'decembre',
  ];

  /// Repère et retire du texte la première expression de date et d'heure.
  AssistantWhen? _takeWhen(_Scan s) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime plusDays(int n) => DateTime(today.year, today.month, today.day + n);
    DateTime? day;
    DateTime? exact;
    int? partHour; // « ce soir », « le matin »

    // Relatif : « dans 3 jours », « dans 2 heures ».
    final rel = s.take(RegExp(r"\bdans\s+(\d+|un|une|deux|trois|quatre|cinq|"
        r"six|sept|huit|neuf|dix|quinze|vingt)\s*"
        r"(minutes?|mins?|heures?|h|jours?|j|semaines?|mois|ans?|annees?)\b"));
    if (rel != null) {
      final n = _number(rel[1]!);
      final unit = rel[2]!;
      if (unit.startsWith('min') || unit.startsWith('h')) {
        final e = now.add(unit.startsWith('h')
            ? Duration(hours: n)
            : Duration(minutes: n));
        exact = DateTime(e.year, e.month, e.day, e.hour, e.minute);
      } else if (unit.startsWith('j')) {
        day = plusDays(n);
      } else if (unit.startsWith('s')) {
        day = plusDays(7 * n);
      } else if (unit == 'mois') {
        day = _addMonths(today, n);
      } else {
        day = _addMonths(today, 12 * n);
      }
    }

    if (day == null && exact == null) {
      if (s.take(RegExp(r"\bapres[- ]demain\b")) != null) {
        day = plusDays(2);
      } else if (s.take(RegExp(r"\bdemain\b")) != null) {
        day = plusDays(1);
      } else if (s.take(RegExp(r"\baujourd'?hui\b|\bce jour\b")) != null) {
        day = today;
      } else if (s.take(RegExp(r"\bce soir\b")) != null) {
        day = today;
        partHour = 19;
      } else if (s.take(RegExp(r"\bce matin\b")) != null) {
        day = today;
        partHour = 9;
      } else if (s.take(RegExp(r"\bcet apres[- ]midi\b")) != null) {
        day = today;
        partHour = 15;
      } else if (s.take(RegExp(r"\b(?:la )?semaine prochaine\b")) != null) {
        day = plusDays(7);
      } else if (s.take(RegExp(r"\b(?:le )?mois prochain\b")) != null) {
        day = _addMonths(today, 1);
      } else if (s.take(RegExp(r"\b(?:ce|le) week[- ]?end\b")) != null) {
        day = plusDays((DateTime.saturday - today.weekday + 7) % 7);
      }
    }

    if (day == null && exact == null) {
      final m = s.take(RegExp(
          r"\b(?:le\s+)?(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b"));
      if (m != null) {
        day = _date(int.parse(m[1]!), int.parse(m[2]!),
            m[3] == null ? null : int.parse(m[3]!), today);
      }
    }
    if (day == null && exact == null) {
      final m = s.take(RegExp(r"\b(?:le\s+)?(1er|\d{1,2})\s+"
          "(${_months.join('|')})"
          r"(?:\s+(\d{4}))?\b"));
      if (m != null) {
        final d = m[1] == '1er' ? 1 : int.parse(m[1]!);
        day = _date(d, _months.indexOf(m[2]!) + 1,
            m[3] == null ? null : int.parse(m[3]!), today);
      }
    }
    if (day == null && exact == null) {
      final m = s.take(RegExp(r"\b(?:(?:ce|le)\s+)?"
          "(${_weekdays.join('|')})"
          r"s?(?:\s+prochain)?\b"));
      if (m != null) {
        final target = _weekdays.indexOf(m[1]!) + 1;
        var diff = (target - today.weekday + 7) % 7;
        if (diff == 0) diff = 7;
        day = plusDays(diff);
      }
    }

    int? hour;
    int? minute;
    if (exact == null) {
      final m = s.take(RegExp(r"(?:\b(?:a|vers|pour|des)\s+)?\b(\d{1,2})\s*"
          r"(?:heures?|h|:)\s*(\d{2})?(?!\d)"));
      if (m != null) {
        final h = int.parse(m[1]!);
        final min = m[2] == null ? 0 : int.parse(m[2]!);
        if (h < 24 && min < 60) {
          hour = h;
          minute = min;
        }
      } else if (s.take(RegExp(r"(?:\b(?:a|vers)\s+)?\bmidi\b")) != null) {
        hour = 12;
        minute = 0;
      }
      if (s.take(RegExp(r"\b(?:du |le |en )?soir(?:ee)?\b")) != null) {
        partHour = 19;
      } else if (s.take(RegExp(r"\b(?:de l'|l'|cet )?apres[- ]midi\b")) != null) {
        partHour = 15;
      } else if (s.take(RegExp(r"\b(?:du |le |au )?matin\b")) != null) {
        partHour = 9;
      }
      // « 7h du soir » => 19 h.
      if (hour != null && hour < 12 && partHour != null && partHour >= 15) {
        hour += 12;
      }
      hour ??= partHour;
    }

    if (exact != null) return AssistantWhen(exact, exact: exact);
    if (day == null) {
      if (hour == null) return null;
      // Heure seule : aujourd'hui si elle n'est pas passée, sinon demain.
      final at = DateTime(today.year, today.month, today.day, hour, minute ?? 0);
      day = at.isAfter(now) ? today : plusDays(1);
    }
    return AssistantWhen(day, hour: hour, minute: minute);
  }

  /// Date sans année : la prochaine occurrence (l'an prochain si passée).
  static DateTime? _date(int d, int m, int? y, DateTime today) {
    if (m < 1 || m > 12 || d < 1) return null;
    var year = y ?? today.year;
    if (year < 100) year += 2000;
    var date = DateTime(year, m, d);
    if (date.month != m) return null; // 31/02...
    if (y == null && date.isBefore(today)) date = DateTime(year + 1, m, d);
    return date;
  }

  static DateTime _addMonths(DateTime d, int months) {
    final first = DateTime(d.year, d.month + months);
    final last = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, d.day > last ? last : d.day);
  }

  static int _number(String word) =>
      int.tryParse(word) ??
      const {
        'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5,
        'six': 6, 'sept': 7, 'huit': 8, 'neuf': 9, 'dix': 10, 'quinze': 15,
        'vingt': 20,
      }[word] ??
      1;

  /// Retire les mots de liaison au début et à la fin d'un titre.
  static String _cleanTitle(String original, String normalized) {
    final leading = RegExp(r"^(?:[\s,;:.!?\-]+|(?:de|du|des|le|la|les|un|une|"
        r"pour|a|au|aux|que|je|dois|doit|faut|il|rappel|penser|moi|me|svp|stp)\b|"
        r"(?:d|l|j|qu)')");
    final trailing = RegExp(r"(?:[\s,;:.!?\-]+|\b(?:de|du|des|le|la|les|pour|a|"
        r"au|et|svp|stp|merci|d|l))$");
    var o = original;
    var n = normalized;
    for (var changed = true; changed && n.isNotEmpty;) {
      changed = false;
      final a = leading.firstMatch(n);
      if (a != null && a.end > 0) {
        o = o.substring(a.end);
        n = n.substring(a.end);
        changed = true;
      }
      final b = trailing.firstMatch(n);
      if (b != null && b.end > b.start) {
        o = o.substring(0, b.start);
        n = n.substring(0, b.start);
        changed = true;
      }
    }
    o = o.replaceAll(RegExp(r'\s+'), ' ').trim();
    return o.isEmpty ? o : o[0].toUpperCase() + o.substring(1);
  }

  static const _stopWords = {
    'les', 'des', 'une', 'pour', 'avec', 'comme', 'fait', 'faite', 'faits',
    'termine', 'terminee', 'marque', 'marquer', 'rappel', 'rappels', 'mon',
    'mes', 'ton', 'tes', 'son', 'ses', 'est', 'deja', 'donne', 'donner',
    'achete', 'effectue', 'pris', 'celui', 'celle', 'qui', 'que', 'quoi',
    'stp', 'svp', 'merci', 'peux', 'moi', 'aux', 'dans', 'sur', 'par',
    'plus', 'tard', 'ete', 'bien', 'matin', 'soir', 'heure', 'heures',
    'tout', 'hier', 'aujourd', 'hui', 'regle', 'valide', 'chez', 'cette',
    'leur', 'notre', 'votre', 'vos', 'nos',
  };
}

/// Texte en cours d'analyse : les expressions reconnues sont masquées au
/// fur et à mesure pour ne garder que le reste (titre, mots-clés).
class _Scan {
  _Scan(this.original) : norm = normalizeFr(original) {
    _work = norm.split('');
  }

  final String original;
  final String norm;
  late final List<String> _work;

  String get work => _work.join();

  RegExpMatch? take(RegExp re) {
    final m = re.firstMatch(work);
    if (m != null) {
      for (var i = m.start; i < m.end; i++) {
        _work[i] = ' ';
      }
    }
    return m;
  }

  /// Texte non reconnu : (version d'origine, version normalisée).
  (String, String) remainder() {
    final out = StringBuffer();
    for (var i = 0; i < _work.length; i++) {
      out.write(_work[i] == ' ' ? ' ' : original[i]);
    }
    return (out.toString(), work);
  }
}
