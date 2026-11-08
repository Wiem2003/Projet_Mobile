import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Police des documents PDF (rapport mensuel, carnet de santé) : Roboto,
/// intégrée à l'app pour les accents français. `null` si elle ne peut pas
/// être chargée : le PDF utilise alors Helvetica.
abstract final class PdfFonts {
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData?> theme() async {
    if (_theme != null) return _theme;
    try {
      final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      return _theme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
    } on Exception {
      return null;
    }
  }
}
