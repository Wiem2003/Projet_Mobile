import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'dashboard/pet_metrics.dart';
import 'health_ai_summary.dart';
import 'health_record.dart';
import 'pdf_fonts.dart';
import 'pet.dart';
import 'vaccination_booklet.dart';
import 'validation.dart';

/// Carnet de santé d'un animal au format PDF : identité, allergies, vaccins
/// et leur statut, traitements, autres soins et courbe de poids. À envoyer
/// à une pension, à un nouveau vétérinaire ou au pet-sitter.
abstract final class HealthBookletPdf {
  static const _red = PdfColor.fromInt(0xFFDC2626);
  static const _teal = PdfColor.fromInt(0xFF0F766E);

  /// Nombre maximal de lignes par tableau.
  static const maxRows = 15;

  static String fileName(Pet p) {
    final safe = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'carnet_sante_$safe.pdf';
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Future<Uint8List> build({
    required Pet pet,
    required VaccinationBooklet booklet,
    required Iterable<HealthRecord> health,
    required DateTime now,
    HealthAiSummary? aiSummary,
  }) async {
    final records = [for (final h in health) if (h.petId == pet.id) h]
      ..sort((a, b) => b.date.compareTo(a.date));
    final treatments = [for (final r in records) if (r.type == HealthType.treatment) r];
    final others = [
      for (final r in records)
        if (r.type != HealthType.treatment && r.type != HealthType.vaccination) r,
    ];
    final weights = PetMetrics.weighings(pet.id!, health);

    final doc = pw.Document(
        title: 'Carnet de santé - ${pet.name}',
        author: 'Smart Pet Manager',
        theme: await PdfFonts.theme());
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Smart Pet Manager - édité le ${_date(now)} - page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.Text('Carnet de santé',
            style: pw.TextStyle(color: _teal, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text(pet.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        if (aiSummary != null) ...[_aiSection(aiSummary), pw.SizedBox(height: 14)],
        _section('Identité'),
        _table(null, [
          ['Espèce', pet.species.label],
          ['Race', pet.breed ?? 'Non renseignée'],
          ['Sexe', pet.sex.label],
          [
            'Naissance',
            pet.birthDate == null
                ? 'Non renseignée'
                : '${_date(pet.birthDate!)} (${pet.ageLabel(now)})',
          ],
          ['Couleur', pet.color ?? 'Non renseignée'],
          ['Identification (puce / tatouage)', pet.identification ?? 'Non renseignée'],
          ['Poids actuel', pet.weightKg == null ? 'Non renseigné' : '${formatDecimal(pet.weightKg!)} kg'],
        ]),
        pw.SizedBox(height: 14),
        _section('Allergies'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: pet.allergies == null ? PdfColors.grey400 : _red),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(pet.allergies ?? 'Aucune allergie connue',
              style: pw.TextStyle(
                  color: pet.allergies == null ? PdfColors.grey700 : _red,
                  fontWeight: pet.allergies == null ? null : pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 14),
        _section('Vaccins - ${booklet.summary}'),
        if (booklet.isEmpty)
          pw.Text('Aucun vaccin enregistré.')
        else
          _table(
            ['Vaccin', 'Dernière injection', 'Produit', 'Vétérinaire', 'Valable jusqu\'au', 'Statut'],
            [
              for (final e in booklet.entries)
                [
                  e.name,
                  _date(e.injectedOn),
                  e.record.medication ?? '',
                  e.record.vet ?? '',
                  _date(e.expiresOn),
                  e.status.label,
                ],
            ],
          ),
        if (booklet.missingCore.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
                'Vaccins conseillés jamais enregistrés : '
                '${booklet.missingCore.map((v) => v.label).join(', ')}.',
                style: const pw.TextStyle(fontSize: 9, color: _red)),
          ),
        pw.SizedBox(height: 14),
        _section('Traitements'),
        if (treatments.isEmpty)
          pw.Text('Aucun traitement enregistré.')
        else
          _table(['Date', 'Médicament', 'Vétérinaire', 'Renouvellement', 'Notes'], [
            for (final t in treatments.take(maxRows))
              [
                _date(t.date),
                t.medication ?? '',
                t.vet ?? '',
                t.nextDue == null ? '' : _date(t.nextDue!),
                t.description ?? '',
              ],
          ]),
        pw.SizedBox(height: 14),
        _section('Autres soins'),
        if (others.isEmpty)
          pw.Text('Aucun autre soin enregistré.')
        else
          _table(['Date', 'Soin', 'Vétérinaire', 'Détails'], [
            for (final o in others.take(maxRows))
              [_date(o.date), o.type.label, o.vet ?? '', o.description ?? o.medication ?? ''],
          ]),
        pw.SizedBox(height: 14),
        _section('Courbe de poids'),
        if (weights.length < 2)
          pw.Text(weights.isEmpty
              ? 'Aucune pesée enregistrée.'
              : 'Une seule pesée : ${formatDecimal(weights.single.weightKg!)} kg le ${_date(weights.single.date)}.')
        else ...[
          _weightChart(weights.length > maxRows ? weights.sublist(weights.length - maxRows) : weights),
          pw.SizedBox(height: 6),
          pw.Text(
            [
              for (final w in weights.reversed.take(6))
                '${_date(w.date)} : ${formatDecimal(w.weightKg!)} kg',
            ].join('   '),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ],
    ));
    return doc.save();
  }

  /// Synthèse rédigée par Gemini, encadrée et signalée comme telle.
  static pw.Widget _aiSection(HealthAiSummary s) {
    pw.Widget list(String title, List<String> items) => items.isEmpty
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                for (final i in items)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 6, top: 2),
                    child: pw.Text('- $i', style: const pw.TextStyle(fontSize: 9.5)),
                  ),
              ],
            ),
          );
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF0FDFA),
        border: pw.Border.all(color: _teal),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Synthèse rédigée par Gemini (IA)',
              style: pw.TextStyle(color: _teal, fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(s.overview, style: const pw.TextStyle(fontSize: 10)),
          list("Points d'attention", s.attention),
          list('Conseils', s.advice),
          list('Questions à poser au vétérinaire', s.vetQuestions),
          pw.SizedBox(height: 8),
          pw.Text(
              'Texte généré automatiquement à partir des données du carnet. Il ne remplace pas '
              "l'avis d'un vétérinaire.",
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(title,
            style: pw.TextStyle(color: _teal, fontSize: 14, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _table(List<String>? headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        // Sans en-têtes (tableau Identité), la 1re ligne est une ligne normale.
        headerCount: headers == null ? 0 : 1,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
      );

  static pw.Widget _weightChart(List<HealthRecord> weights) {
    final values = [for (final w in weights) w.weightKg!];
    var low = values.reduce((a, b) => a < b ? a : b);
    var high = values.reduce((a, b) => a > b ? a : b);
    final pad = (high - low) < 0.5 ? 0.5 : (high - low) * 0.2;
    low = (low - pad) < 0 ? 0 : low - pad;
    high = high + pad;
    final step = (high - low) / 4;
    return pw.SizedBox(
      height: 170,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            [for (final w in weights) PetMetrics.dayMonth(w.date)],
            marginStart: 20,
            marginEnd: 20,
            ticks: true,
            textStyle: const pw.TextStyle(fontSize: 7),
          ),
          yAxis: pw.FixedAxis(
            [for (var i = 0; i <= 4; i++) low + step * i],
            format: (v) => formatDecimal(v.toDouble(), decimals: 1),
            divisions: true,
            textStyle: const pw.TextStyle(fontSize: 8),
          ),
        ),
        datasets: [
          pw.LineDataSet(
            color: _red,
            pointColor: _red,
            data: [
              for (final (i, w) in weights.indexed) pw.PointChartValue(i.toDouble(), w.weightKg!),
            ],
          ),
        ],
      ),
    );
  }
}
