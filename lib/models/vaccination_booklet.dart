import 'health_record.dart';
import 'pet.dart';

/// Vaccins suivis par le carnet. Ils sont reconnus dans le nom saisi au
/// dossier de santé (« CHPPi + rage » = CHPPi et rage).
enum Vaccine {
  rabies('Rage', ['rage', 'rabies', 'rabique', 'rabisin']),
  chppi('CHPPi', ['chppi', 'chpp', 'chp', 'carre', 'parvo', 'hepatite', 'dhpp']),
  leptospirosis('Leptospirose', ['lepto']),
  typhus('Typhus', ['typhus', 'panleucopenie']),
  coryza('Coryza', ['coryza']),
  leukemia('Leucose féline', ['leucose', 'felv']),
  other('Autre vaccin', []);

  const Vaccine(this.label, this.keywords);

  final String label;
  final List<String> keywords;

  /// Validité par défaut quand le dossier n'a pas d'échéance : 1 an. Une
  /// échéance saisie (ex. rage valable 3 ans) est prioritaire.
  static const defaultValidityMonths = 12;

  static String _normalize(String s) {
    const from = 'àâäéèêëîïôöùûüç';
    const to = 'aaaeeeeiioouuuc';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString();
  }

  /// Vaccins contenus dans le nom saisi (« Autre vaccin » si aucun).
  static Set<Vaccine> detect(String? medication) {
    final text = _normalize(medication ?? '');
    final found = {
      for (final v in values)
        if (v.keywords.any(text.contains)) v,
    };
    return found.isEmpty ? {other} : found;
  }

  /// Vaccins conseillés par espèce (signalés s'ils ne sont jamais saisis).
  static List<Vaccine> coreFor(Species s) => switch (s) {
        Species.dog => const [chppi, rabies],
        Species.cat => const [typhus, coryza],
        _ => const [],
      };
}

enum VaccineStatus {
  upToDate('À jour'),
  expiringSoon('Bientôt expiré'),
  expired('Expiré');

  const VaccineStatus(this.label);

  final String label;
}

/// Dernière injection d'un vaccin pour un animal.
class VaccineEntry {
  const VaccineEntry({
    required this.vaccine,
    required this.record,
    required this.expiresOn,
    required this.status,
    required this.daysLeft,
    this.previous,
  });

  final Vaccine vaccine;

  /// Dossier de santé de la dernière injection.
  final HealthRecord record;

  /// Injection précédente du même vaccin (rappel), s'il y en a une.
  final HealthRecord? previous;
  final DateTime expiresOn;
  final VaccineStatus status;

  /// Jours avant l'expiration (négatif si expiré).
  final int daysLeft;

  DateTime get injectedOn => record.date;
  String get name => vaccine == Vaccine.other ? (record.medication ?? vaccine.label) : vaccine.label;
}

/// Carnet de vaccination d'un animal : statut de chaque vaccin.
class VaccinationBooklet {
  const VaccinationBooklet({required this.pet, required this.entries, required this.missingCore});

  /// Il reste moins de 30 jours : « bientôt expiré ».
  static const soonDays = 30;

  /// La rage protège 21 jours après une première injection.
  static const rabiesDelayDays = 21;

  final Pet pet;

  /// Un par vaccin, dans l'ordre de l'énumération.
  final List<VaccineEntry> entries;

  /// Vaccins conseillés pour l'espèce jamais enregistrés.
  final List<Vaccine> missingCore;

  int count(VaccineStatus s) => entries.where((e) => e.status == s).length;
  bool get isEmpty => entries.isEmpty;
  VaccineEntry? of(Vaccine v) => entries.where((e) => e.vaccine == v).firstOrNull;

  /// Résumé de la fiche : « Vaccins à jour », « 1 vaccin expiré »...
  String get summary {
    if (entries.isEmpty) return 'Aucun vaccin enregistré';
    final expired = count(VaccineStatus.expired);
    if (expired > 0) return '$expired vaccin${expired > 1 ? 's expirés' : ' expiré'}';
    final soon = count(VaccineStatus.expiringSoon);
    if (soon > 0) return '$soon vaccin${soon > 1 ? 's bientôt expirés' : ' bientôt expiré'}';
    return 'Vaccins à jour';
  }

  /// Pire statut du carnet (`null` sans vaccin).
  VaccineStatus? get worst => entries.isEmpty
      ? null
      : count(VaccineStatus.expired) > 0
          ? VaccineStatus.expired
          : count(VaccineStatus.expiringSoon) > 0
              ? VaccineStatus.expiringSoon
              : VaccineStatus.upToDate;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _expiry(HealthRecord r) =>
      r.nextDue ?? DateTime(r.date.year, r.date.month + Vaccine.defaultValidityMonths, r.date.day);

  factory VaccinationBooklet.compute(Pet pet, Iterable<HealthRecord> health, DateTime now) {
    final today = _day(now);
    final shots = [
      for (final h in health)
        if (h.petId == pet.id && h.type == HealthType.vaccination) h,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final byVaccine = <Vaccine, List<HealthRecord>>{};
    for (final s in shots) {
      for (final v in Vaccine.detect(s.medication)) {
        byVaccine.putIfAbsent(v, () => []).add(s);
      }
    }
    final entries = <VaccineEntry>[];
    for (final v in Vaccine.values) {
      final list = byVaccine[v];
      if (list == null) continue;
      final last = list.last;
      final expires = _expiry(last);
      final days = _day(expires).difference(today).inDays;
      entries.add(VaccineEntry(
        vaccine: v,
        record: last,
        previous: list.length > 1 ? list[list.length - 2] : null,
        expiresOn: expires,
        daysLeft: days,
        status: days < 0
            ? VaccineStatus.expired
            : days < soonDays
                ? VaccineStatus.expiringSoon
                : VaccineStatus.upToDate,
      ));
    }
    return VaccinationBooklet(
      pet: pet,
      entries: entries,
      missingCore: [for (final v in Vaccine.coreFor(pet.species)) if (!byVaccine.containsKey(v)) v],
    );
  }

  /// « 15/12 » (année ajoutée si ce n'est pas l'année en cours).
  static String date(DateTime d, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.year == now.year ? '${two(d.day)}/${two(d.month)}' : '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  /// Vérification avant un voyage ou une mise en pension : rage faite
  /// depuis au moins 21 jours (sauf rappel fait à temps) et encore valide
  /// le jour du départ. Les autres vaccins expirés sont signalés.
  TravelCheck checkTravel(DateTime departure, DateTime now) {
    final day = _day(departure);
    String d(DateTime x) => date(x, now);
    final when = '${pet.name} ne peut pas voyager le ${d(day)}';
    if (day.isBefore(_day(now))) {
      return TravelCheck(ok: false, message: 'La date de départ est déjà passée.');
    }
    final rabies = of(Vaccine.rabies);
    final problems = <String>[];
    if (rabies == null) {
      problems.add('aucun vaccin contre la rage enregistré');
    } else {
      // Un rappel fait avant l'expiration du précédent protège sans délai.
      final prev = rabies.previous;
      final booster = prev != null && !rabies.injectedOn.isAfter(_expiry(prev));
      final validFrom = _day(rabies.injectedOn).add(const Duration(days: rabiesDelayDays));
      if (!booster && day.isBefore(validFrom)) {
        problems.add('vaccin contre la rage trop récent (fait le ${d(rabies.injectedOn)}, '
            'valable à partir du ${d(validFrom)})');
      }
      if (_day(rabies.expiresOn).isBefore(day)) {
        problems.add(_day(rabies.expiresOn).isBefore(_day(now))
            ? 'rage expirée le ${d(rabies.expiresOn)}'
            : 'rage expire le ${d(rabies.expiresOn)}, avant le départ');
      }
    }
    final warnings = [
      for (final e in entries)
        if (e.vaccine != Vaccine.rabies && _day(e.expiresOn).isBefore(day))
          '${e.name} expiré à cette date (souvent exigé par les pensions)',
      for (final v in missingCore)
        if (v != Vaccine.rabies) '${v.label} jamais enregistré',
    ];
    if (problems.isNotEmpty) {
      return TravelCheck(ok: false, message: '$when : ${problems.join(' ; ')}.', warnings: warnings);
    }
    return TravelCheck(
      ok: true,
      message: '${pet.name} peut voyager le ${d(day)} : rage valable jusqu\'au '
          '${date(rabies!.expiresOn, now)}.',
      warnings: warnings,
    );
  }
}

/// Résultat de la vérification avant un voyage.
class TravelCheck {
  const TravelCheck({required this.ok, required this.message, this.warnings = const []});

  final bool ok;
  final String message;

  /// Points d'attention non bloquants (autres vaccins).
  final List<String> warnings;
}
