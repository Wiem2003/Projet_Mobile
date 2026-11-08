import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

import '../validation.dart';
import 'app_user.dart';

/// Envoi du code « Mot de passe oublié ». Les erreurs sont des
/// `RecordException` affichables telles quelles.
abstract interface class ResetMailer {
  /// Faux si l'envoi n'est pas configuré (pas de mot de passe Gmail).
  bool get configured;

  Future<void> sendResetCode(
      {required AppUser user, required String code, required DateTime expiresAt});
}

/// Contenu de l'e-mail (texte et HTML).
abstract final class ResetEmail {
  static const subject = 'Smart Pet : votre code de réinitialisation';

  static String _hour(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')} h ${d.minute.toString().padLeft(2, '0')}';

  static String text(String name, String code, DateTime expiresAt, int minutes) => '''
Bonjour $name,

Vous avez demandé à réinitialiser le mot de passe de votre compte Smart Pet.

Votre code : $code

Saisissez-le dans l'application, écran « Nouveau mot de passe ». Il est valable $minutes minutes (jusqu'à ${_hour(expiresAt)}) et ne sert qu'une fois.

Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail : votre mot de passe ne change pas.

L'équipe Smart Pet''';

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String html(String name, String code, DateTime expiresAt, int minutes) => '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:auto;color:#1f2937">
  <h2 style="color:#0f766e;margin-bottom:4px">Smart Pet</h2>
  <p>Bonjour ${_escape(name)},</p>
  <p>Vous avez demandé à réinitialiser le mot de passe de votre compte Smart Pet.</p>
  <p style="margin:24px 0;text-align:center">
    <span style="display:inline-block;font-size:32px;font-weight:bold;letter-spacing:8px;
      padding:12px 20px;border-radius:12px;background:#ccfbf1;color:#134e4a">$code</span>
  </p>
  <p>Saisissez ce code dans l'application, écran « Nouveau mot de passe ». Il est valable
    <b>$minutes minutes</b> (jusqu'à ${_hour(expiresAt)}) et ne sert qu'une fois.</p>
  <p style="color:#6b7280;font-size:13px">Si vous n'êtes pas à l'origine de cette demande,
    ignorez cet e-mail : votre mot de passe ne change pas.</p>
</div>''';
}

/// Envoi par Gmail (SMTP) depuis [sender], avec un mot de passe
/// d'application Google (pas le mot de passe du compte).
class GmailResetMailer implements ResetMailer {
  GmailResetMailer({
    required this.sender,
    required String appPassword,
    this.senderName = 'Smart Pet',
    this.validityMinutes = 15,
  }) : _password = appPassword.replaceAll(' ', '');

  final String sender;
  final String senderName;
  final int validityMinutes;
  final String _password;

  @override
  bool get configured => sender.isNotEmpty && _password.isNotEmpty;

  @override
  Future<void> sendResetCode(
      {required AppUser user, required String code, required DateTime expiresAt}) async {
    if (!configured) {
      throw const RecordException('L\'envoi d\'e-mails n\'est pas configuré.');
    }
    final message = Message()
      ..from = Address(sender, senderName)
      ..recipients.add(Address(user.email, user.name))
      ..subject = ResetEmail.subject
      ..text = ResetEmail.text(user.name, code, expiresAt, validityMinutes)
      ..html = ResetEmail.html(user.name, code, expiresAt, validityMinutes);
    try {
      await send(message, gmail(sender, _password), timeout: const Duration(seconds: 25));
    } on SmtpClientAuthenticationException {
      throw const RecordException(
          'Gmail a refusé la connexion : vérifiez le mot de passe d\'application.');
    } on MailerException {
      throw const RecordException('L\'e-mail n\'a pas pu être envoyé. Réessayez plus tard.');
    } on SocketException {
      throw const RecordException(
          'Pas de connexion Internet : l\'e-mail n\'a pas pu être envoyé.');
    } on TimeoutException {
      throw const RecordException('Gmail ne répond pas. Réessayez dans un instant.');
    }
  }
}
