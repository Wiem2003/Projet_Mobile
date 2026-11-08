import 'package:flutter/foundation.dart';

import '../models/auth/app_user.dart';
import '../models/auth/auth_model.dart';
import '../models/auth/reset_mailer.dart';
import '../models/auth/user_repository.dart';
import '../models/pet_photo_store.dart';
import '../models/validation.dart';

/// Controller de l'authentification : Sign up, Sign in, Sign out, profil.
///
/// Reçoit les actions des écrans, applique les règles via le
/// [UserRepository] puis met à jour l'[AuthModel]. La session reste
/// ouverte sur le téléphone jusqu'à la déconnexion.
class AuthController {
  AuthController({
    required this.model,
    required UserRepository repository,
    this.photos,
    this.mailer,
    DateTime Function()? clock,
    bool? showCodeWithoutMailer,
  })  : _repo = repository,
        _clock = clock ?? DateTime.now,
        _demo = showCodeWithoutMailer ?? kDebugMode;

  final AuthModel model;
  final UserRepository _repo;
  final DateTime Function() _clock;

  /// Photos de profil (appareil photo / galerie). `null` : pas de photo.
  final PetPhotoStore? photos;

  /// Envoi du code « Mot de passe oublié » (Gmail).
  final ResetMailer? mailer;

  /// Sans envoi d'e-mail configuré, en mode debug : le code est affiché à
  /// l'écran pour pouvoir tester sur l'émulateur.
  final bool _demo;

  /// Délai entre deux envois de code pour une même adresse.
  static const resendDelay = Duration(seconds: 60);
  final _lastRequest = <String, DateTime>{};

  // ------------------------------------------------- Mot de passe oublié

  /// Temps à attendre avant de pouvoir redemander un code.
  Duration resendIn(String email) {
    final last = _lastRequest[email.trim().toLowerCase()];
    if (last == null) return Duration.zero;
    final left = last.add(resendDelay).difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Envoie un code de réinitialisation. Le résultat est le même que le
  /// compte existe ou non (on ne révèle pas les comptes), sauf en cas
  /// d'erreur d'envoi.
  Future<ResetRequestResult> requestPasswordReset(String email) async {
    final mail = email.trim().toLowerCase();
    final wait = resendIn(mail);
    if (wait > Duration.zero) {
      return ResetRequestResult(
          error: 'Patientez ${(wait.inMilliseconds / 1000).ceil()} s avant de demander un nouveau code.');
    }
    final m = mailer;
    if ((m == null || !m.configured) && !_demo) {
      return const ResetRequestResult(
          error: "L'envoi d'e-mails n'est pas configuré sur cette version de l'app.");
    }
    try {
      final request = await _repo.requestPasswordReset(mail);
      _lastRequest[mail] = _clock();
      if (request == null) return const ResetRequestResult();
      if (m != null && m.configured) {
        await m.sendResetCode(user: request.user, code: request.code, expiresAt: request.expiresAt);
        return const ResetRequestResult();
      }
      return ResetRequestResult(demoCode: request.code);
    } on RecordException catch (e) {
      _lastRequest.remove(mail);
      return ResetRequestResult(error: e.message);
    }
  }

  /// Change le mot de passe avec le code reçu. Renvoie l'erreur, ou `null`.
  Future<String?> resetPassword(
      {required String email, required String code, required String newPassword}) async {
    try {
      await _repo.resetPassword(email: email, code: code, newPassword: newPassword);
      _lastRequest.remove(email.trim().toLowerCase());
      return null;
    } on RecordException catch (e) {
      return e.message;
    }
  }

  /// Au lancement : reprend le compte resté connecté, s'il est toujours actif.
  Future<void> restore() async {
    try {
      final id = await _repo.sessionUserId();
      if (id != null) {
        final user = await _repo.getById(id);
        if (user.active) return model.signedIn(user);
      }
    } on RecordException {
      // Compte supprimé entre-temps.
    }
    await _repo.clearSession();
    model.signedOut();
  }

  /// Renvoie `true` si la connexion a réussi (sinon `model.error`).
  Future<bool> signIn({required String email, required String password}) =>
      _open(() => _repo.signIn(email: email, password: password));

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    String? photoPath,
    UserRole role = UserRole.user,
  }) =>
      _open(() => _repo.signUp(
          name: name, email: email, password: password, photoPath: photoPath, role: role));

  /// Choisit une photo (copiée dans l'app). `null` si annulé ou impossible.
  Future<String?> pickPhoto({required bool camera}) async {
    try {
      return await photos?.pick(camera: camera);
    } on Exception {
      return null;
    }
  }

  /// Photo choisie puis abandonnée (formulaire fermé).
  Future<void> discardPhoto(String? path) async {
    if (path != null) await photos?.delete(path);
  }

  /// Change (ou retire si [path] est null) la photo du compte connecté.
  Future<String?> setPhoto(String? path) async {
    final user = model.user;
    if (user == null) return "Vous n'êtes pas connecté.";
    try {
      final saved = await _repo.updatePhoto(user.id, path);
      final old = user.photoPath;
      if (old != null && old != path) await photos?.delete(old);
      model.signedIn(saved);
      return null;
    } on RecordException catch (e) {
      return e.message;
    }
  }

  Future<bool> _open(Future<AppUser> Function() action) async {
    model.setBusy(true);
    try {
      final user = await action();
      await _repo.saveSession(user.id);
      model.signedIn(user);
      return true;
    } on RecordException catch (e) {
      model.setError(e.message);
      return false;
    }
  }

  Future<void> signOut() async {
    await _repo.clearSession();
    model.signedOut();
  }

  void clearError() => model.clearError();

  /// Renvoie le message d'erreur, ou `null` si c'est enregistré.
  Future<String?> updateName(String name) async {
    final user = model.user;
    if (user == null) return 'Vous n\'êtes pas connecté.';
    try {
      model.signedIn(await _repo.updateName(user.id, name));
      return null;
    } on RecordException catch (e) {
      return e.message;
    }
  }

  Future<String?> changePassword(
      {required String current, required String next}) async {
    final user = model.user;
    if (user == null) return 'Vous n\'êtes pas connecté.';
    try {
      await _repo.changePassword(user.id, current: current, next: next);
      return null;
    } on RecordException catch (e) {
      return e.message;
    }
  }
}

/// Résultat d'une demande de code : [error] si rien n'a été envoyé ;
/// [demoCode] quand l'e-mail n'est pas configuré (mode debug).
class ResetRequestResult {
  const ResetRequestResult({this.error, this.demoCode});

  final String? error;
  final String? demoCode;

  bool get ok => error == null;
}
