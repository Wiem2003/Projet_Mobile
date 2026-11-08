import 'dart:typed_data';

import '../models/assistant/gemini_client.dart';
import '../models/dashboard/report_sharer.dart';
import '../models/health_ai_summary.dart';
import '../models/health_booklet_pdf.dart';
import '../models/health_record.dart';
import '../models/pet.dart';
import '../models/vaccination_booklet.dart';

/// Controller du carnet de santé : vérification avant un voyage et partage
/// du carnet en PDF (pension, nouveau vétérinaire, pet-sitter), avec une
/// synthèse rédigée par Gemini si une clé est configurée.
class HealthBookletController {
  HealthBookletController({
    ReportSharer reportSharer = const SystemReportSharer(),
    DateTime Function()? clock,
    LlmClient? llm,
  })  : _sharer = reportSharer,
        _clock = clock ?? DateTime.now,
        _writer = llm == null ? null : HealthSummaryWriter(llm);

  final ReportSharer _sharer;
  final DateTime Function() _clock;
  final HealthSummaryWriter? _writer;

  /// Une clé Gemini est configurée : synthèse possible.
  bool get aiAvailable => _writer != null;

  DateTime get now => _clock();

  VaccinationBooklet booklet(Pet pet, Iterable<HealthRecord> health) =>
      VaccinationBooklet.compute(pet, health, now);

  TravelCheck checkTravel(Pet pet, Iterable<HealthRecord> health, DateTime departure) =>
      booklet(pet, health).checkTravel(departure, now);

  /// Construit le carnet en PDF. Avec [withAi], Gemini rédige d'abord une
  /// synthèse ; s'il échoue (hors ligne, surcharge…), le carnet est fait
  /// sans elle et le résultat donne la raison.
  Future<BookletShareResult> prepareBooklet(Pet pet, Iterable<HealthRecord> health,
      {bool withAi = false}) async {
    final b = booklet(pet, health);
    HealthAiSummary? summary;
    String? aiError;
    final writer = _writer;
    if (withAi) {
      if (writer == null) {
        aiError = 'Aucune clé Gemini configurée.';
      } else {
        try {
          summary = await writer.write(pet: pet, booklet: b, health: health, now: now);
        } on HealthSummaryException catch (e) {
          aiError = e.message;
        }
      }
    }
    final bytes = await HealthBookletPdf.build(
        pet: pet, booklet: b, health: health, now: now, aiSummary: summary);
    return BookletShareResult(pet: pet, bytes: bytes, summary: summary, aiError: aiError);
  }

  /// Ouvre le partage Android (e-mail, WhatsApp, Drive…).
  Future<void> share(BookletShareResult booklet) => _sharer.sharePdf(
        fileName: HealthBookletPdf.fileName(booklet.pet),
        subject: 'Carnet de santé de ${booklet.pet.name}',
        bytes: booklet.bytes,
      );

  /// Prépare puis partage le carnet.
  Future<BookletShareResult> shareBooklet(Pet pet, Iterable<HealthRecord> health,
      {bool withAi = false}) async {
    final result = await prepareBooklet(pet, health, withAi: withAi);
    await share(result);
    return result;
  }
}

/// Carnet prêt à partager : le PDF et la synthèse ajoutée, ou pourquoi elle
/// manque.
class BookletShareResult {
  const BookletShareResult(
      {required this.pet, required this.bytes, this.summary, this.aiError});

  final Pet pet;
  final Uint8List bytes;
  final HealthAiSummary? summary;
  final String? aiError;

  bool get withAi => summary != null;
}
