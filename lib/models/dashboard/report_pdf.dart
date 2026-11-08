import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_fonts.dart';
import '../validation.dart';
import 'monthly_report.dart';
import 'pet_metrics.dart';

/// Rapport mensuel au format PDF (paquet pdf, 100 % Dart).
///
/// Police Roboto intégrée à l'app (accents français) ; Helvetica si elle
/// ne peut pas être chargée. Les émojis et les flèches sont évités.
abstract final class ReportPdf {
  static const _teal = PdfColor.fromInt(0xFF0F766E);

  static Future<Uint8List> build(MonthlyReport r) async {
    final doc = pw.Document(
        title: r.title, author: 'Smart Pet Manager', theme: await PdfFonts.theme());
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text('Smart Pet Manager',
            style: pw.TextStyle(color: _teal, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Rapport mensuel - ${PetMetrics.monthLabel(r.month)}',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        _section('Dépenses'),
        pw.TableHelper.fromTextArray(
          headers: ['Module', 'Montant'],
          data: [
            ['Santé', PetMetrics.money(r.healthCost)],
            ['Alimentation', PetMetrics.money(r.feedingCost)],
            ['Total', PetMetrics.money(r.total)],
          ],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {1: pw.Alignment.centerRight},
        ),
        for (final p in r.pets) ...[
          pw.SizedBox(height: 18),
          _section('${p.pet.name} (${p.pet.species.label})'),
          pw.Bullet(
              text: 'Dépenses : ${PetMetrics.money(p.total)} (santé '
                  '${PetMetrics.money(p.healthCost)}, alimentation ${PetMetrics.money(p.feedingCost)})'),
          pw.Bullet(
              text: 'Rappels : ${p.onTime} fait(s) à temps, ${p.late} fait(s) en retard, '
                  '${p.missed} non fait(s)'),
          pw.Bullet(
              text: 'Activité : ${p.activities} séance(s), ${p.minutes} min, '
                  '${formatDecimal(p.km, decimals: 1)} km, ${p.kcal.round()} kcal'),
          pw.Bullet(text: _weight(p)),
          if (p.cares.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Soin', 'Médicament', 'Vétérinaire', 'Coût'],
              data: [
                for (final c in p.cares)
                  [
                    PetMetrics.dayMonth(c.date),
                    c.type.label,
                    c.medication ?? '',
                    c.vet ?? '',
                    PetMetrics.money(c.cost),
                  ],
              ],
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellAlignments: {4: pw.Alignment.centerRight},
            ),
          ],
        ],
        pw.SizedBox(height: 24),
        pw.Text('Document généré par Smart Pet Manager à partir des données saisies dans l\'application.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(title,
            style: pw.TextStyle(color: _teal, fontSize: 14, fontWeight: pw.FontWeight.bold)),
      );

  static String _weight(PetMonthSummary p) {
    if (p.weightEnd == null) return 'Poids : aucune pesée ce mois-ci';
    final d = p.weightDelta;
    final kg = '${formatDecimal(p.weightEnd!)} kg';
    if (d == null || d == 0) return 'Poids : $kg';
    return 'Poids : $kg (${d > 0 ? '+' : '-'}${formatDecimal(d.abs())} kg sur le mois)';
  }
}
