import 'app_user.dart';

/// Code de réinitialisation à envoyer par e-mail.
class PasswordResetRequest {
  const PasswordResetRequest({required this.user, required this.code, required this.expiresAt});

  final AppUser user;
  final String code;
  final DateTime expiresAt;
}

/// Accès aux comptes et règles métier (inscription, connexion, rôles).
/// Les erreurs sont des `RecordException` affichables telles quelles.
abstract interface class UserRepository {
  // ------------------------------------------------------- Sign up / Sign in

  /// Crée un compte avec le rôle choisi ([role]). Le tout premier compte du
  /// téléphone est toujours administrateur et récupère les données saisies
  /// avant les comptes.
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? photoPath,
    UserRole role = UserRole.user,
  });

  /// Vérifie l'e-mail et le mot de passe.
  Future<AppUser> signIn({required String email, required String password});

  // ------------------------------------------------- Mot de passe oublié

  /// Prépare une réinitialisation : nouveau code à 6 chiffres, valable
  /// 15 minutes (il remplace le précédent). `null` si aucun compte actif
  /// n'a cet e-mail.
  Future<PasswordResetRequest?> requestPasswordReset(String email);

  /// Vérifie le code reçu par e-mail puis remplace le mot de passe ; le
  /// blocage après des essais ratés est levé.
  Future<AppUser> resetPassword(
      {required String email, required String code, required String newPassword});

  /// Compte gardé connecté sur le téléphone (`null` si aucun).
  Future<int?> sessionUserId();
  Future<void> saveSession(int userId);
  Future<void> clearSession();

  // ------------------------------------------------------------------ Profil

  Future<AppUser> getById(int id);
  Future<AppUser> updateName(int id, String name);
  Future<void> changePassword(int id,
      {required String current, required String next});

  /// Photo de profil (`null` : retirée).
  Future<AppUser> updatePhoto(int id, String? photoPath);

  // -------------------------------------------------------- Administration

  /// Tous les comptes, du plus récent au plus ancien, avec leurs compteurs.
  Future<List<UserSummary>> getAll();
  Future<AdminStats> stats();

  /// [actorId] : l'administrateur qui agit (il ne peut pas se modifier
  /// lui-même, et il reste toujours un administrateur actif).
  Future<AppUser> setRole(int id, UserRole role, {required int actorId});
  Future<AppUser> setActive(int id, bool active, {required int actorId});

  /// Création d'un compte « user » ou « admin » par un administrateur.
  Future<AppUser> createAccount({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? photoPath,
    required int actorId,
  });

  /// Modification complète d'un compte par un administrateur ; un nouveau
  /// mot de passe est facultatif.
  Future<AppUser> updateAccount(
    int id, {
    required String name,
    required String email,
    required UserRole role,
    required bool active,
    String? photoPath,
    String? newPassword,
    required int actorId,
  });

  /// Supprime le compte et toutes ses données ; renvoie les photos de ses
  /// animaux, à effacer du téléphone.
  Future<List<String>> delete(int id, {required int actorId});
}
