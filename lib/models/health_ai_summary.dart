import 'dart:convert';

import 'assistant/gemini_client.dart';
import 'health_record.dart';
import 'pet.dart';
import 'vaccination_booklet.dart';

/// Synthèse du carnet de santé rédigée par Gemini, ajoutée en tête du PDF.
class HealthAiSummary {
  const HealthAiSummary({
    required this.overview,
    this.attention = const [],
    this.advice = const [],
    this.vetQuestions = const [],
  });

  /// Limites : la synthèse tient sur une page.
  static const maxItems = 5;
  static const maxOverview = 900;
  static const maxItemLength = 260;

  /// État de santé général, en quelques phrases.
  final String overview;

  /// Points d'attention (vaccin expiré, poids, traitement en cours…).
  final List<String> attention;

  /// Conseils pratiques.
  final List<String> advice;

  /// Questions à poser au vétérinaire.
  final List<String> vetQuestions;

  /// Retire ce que la police du PDF (Roboto) ne sait pas dessiner :
  /// flèches, symboles et emojis (au-delà de U+2190).
  static String pdfSafe(String s) => String.fromCharCodes([
        for (final r in s.replaceAll('→', '->').replaceAll('•', '-').runes)
          if (r < 0x2190 || (r >= 0xFB00 && r <= 0xFFFD && r != 0xFE0F)) r,
      ]);

  static String _clip(String s, int max) {
    final t = pdfSafe(s).replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
  }

  static List<String> _list(Object? v) => [
        for (final e in (v is List ? v : const []))
          if (e is String && e.trim().isNotEmpty) _clip(e, maxItemLength),
      ].take(maxItems).toList();

  /// Lit la réponse JSON de Gemini (éventuellement entourée de ```json).
  /// Lève une [FormatException] si elle est illisible ou vide.
  factory HealthAiSummary.parse(String text) {
    var t = text.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(t);
    if (fence != null) t = fence.group(1)!;
    final start = t.indexOf('{'), end = t.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('Pas de JSON');
    final json = jsonDecode(t.substring(start, end + 1));
    if (json is! Map) throw const FormatException('JSON inattendu');
    final overview = json['synthese'];
    if (overview is! String || overview.trim().isEmpty) {
      throw const FormatException('Synthèse vide');
    }
    return HealthAiSummary(
      overview: _clip(overview, maxOverview),
      attention: _list(json['points_attention']),
      advice: _list(json['conseils']),
      vetQuestions: _list(json['questions_veterinaire']),
    );
  }
}

/// Erreur de génération, affichable telle quelle.
class HealthSummaryException implements Exception {
  const HealthSummaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Demande la synthèse à Gemini. Seules les données de santé utiles sont
/// envoyées : ni le propriétaire, ni le numéro de puce.
class HealthSummaryWriter {
  const HealthSummaryWriter(this._llm);

  final LlmClient _llm;

  /// Dossiers envoyés au plus (les plus récents).
  static const maxRecords = 40;

  static const system = '''
Tu es l'assistant vétérinaire de l'application Smart Pet Manager. À partir du carnet de santé fourni en JSON, rédige en français une synthèse claire pour le propriétaire de l'animal.
Règles :
- Appuie-toi uniquement sur les données fournies ; n'invente ni maladie, ni vaccin, ni date.
- Ne pose pas de diagnostic et ne prescris pas de médicament ou de dose : oriente vers le vétérinaire quand c'est utile.
- Signale les vaccins expirés ou bientôt expirés, les échéances dépassées, une évolution de poids marquée, les allergies et les traitements récents.
- Phrases courtes, ton bienveillant, sans jargon.
Réponds uniquement avec un objet JSON, sans texte autour :
{"synthese": "3 à 5 phrases", "points_attention": ["..."], "conseils": ["..."], "questions_veterinaire": ["..."]}
Chaque liste contient de 0 à 5 éléments d'une phrase.''';

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Données envoyées à Gemini.
  static Map<String, Object?> payload({
    required Pet pet,
    required VaccinationBooklet booklet,
    required Iterable<HealthRecord> health,
    required DateTime now,
  }) {
    final records = [for (final h in health) if (h.petId == pet.id) h]
      ..sort((a, b) => b.date.compareTo(a.date));
    return {
      'date_du_jour': _date(now),
      'animal': {
        'nom': pet.name,
        'espece': pet.species.label,
        'race': ?pet.breed,
        'sexe': pet.sex.label,
        if (pet.birthDate != null) 'age': pet.ageLabel(now),
        'sterilise': pet.sterilized,
        if (pet.weightKg != null) 'poids_actuel_kg': pet.weightKg,
        'allergies': pet.allergies ?? 'aucune connue',
      },
      'vaccins': {
        'resume': booklet.summary,
        'detail': [
          for (final e in booklet.entries)
            {
              'vaccin': e.name,
              'injection': _date(e.injectedOn),
              'valable_jusqu_au': _date(e.expiresOn),
              'statut': e.status.label,
            },
        ],
        'conseilles_jamais_enregistres': [for (final v in booklet.missingCore) v.label],
      },
      'dossiers': [
        for (final r in records.take(maxRecords))
          {
            'date': _date(r.date),
            'type': r.type.label,
            'description': ?r.description,
            'medicament': ?r.medication,
            'poids_kg': ?r.weightKg,
            if (r.nextDue != null) 'prochaine_echeance': _date(r.nextDue!),
          },
      ],
      if (records.length > maxRecords) 'dossiers_plus_anciens_non_envoyes': records.length - maxRecords,
    };
  }

  Future<HealthAiSummary> write({
    required Pet pet,
    required VaccinationBooklet booklet,
    required Iterable<HealthRecord> health,
    required DateTime now,
  }) async {
    final data = payload(pet: pet, booklet: booklet, health: health, now: now);
    final LlmTurn turn;
    try {
      turn = await _llm.generate(
        system: system,
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': 'Carnet de santé :\n${jsonEncode(data)}'},
            ],
          },
        ],
        tools: const [],
      );
    } on LlmException catch (e) {
      throw HealthSummaryException(e.message);
    }
    try {
      return HealthAiSummary.parse(turn.text);
    } on FormatException {
      throw const HealthSummaryException('La réponse de Gemini est illisible.');
    }
  }
}
