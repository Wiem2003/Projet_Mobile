import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Partage du rapport mensuel (texte ou PDF) avec une autre application :
/// e-mail, messagerie, WhatsApp...
abstract interface class ReportSharer {
  Future<void> shareText({required String subject, required String text});
  Future<void> sharePdf({required String fileName, required String subject, required Uint8List bytes});
}

/// Feuille de partage du téléphone (paquet share_plus).
class SystemReportSharer implements ReportSharer {
  const SystemReportSharer();

  @override
  Future<void> shareText({required String subject, required String text}) =>
      SharePlus.instance.share(ShareParams(subject: subject, text: text));

  @override
  Future<void> sharePdf(
          {required String fileName, required String subject, required Uint8List bytes}) =>
      SharePlus.instance.share(ShareParams(
        subject: subject,
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
        fileNameOverrides: [fileName],
      ));
}
