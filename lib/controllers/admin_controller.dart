import '../models/auth/admin_model.dart';
import '../models/auth/app_user.dart';
import '../models/auth/user_repository.dart';
import '../models/pet_photo_store.dart';
import '../models/validation.dart';

/// Controller de l'écran Administration : liste des comptes, changement de
/// rôle, activation / désactivation, suppression d'un compte.
/// Les erreurs métier remontent en [RecordException] à la View.
class AdminController {
  AdminController({
    required this.model,
    required UserRepository repository,
    required this.adminId,
    required this.photos,
    this.userPhotos,
  }) : _repo = repository;

  final AdminModel model;
  final UserRepository _repo;

  /// Photos des animaux d'un compte supprimé.
  final PetPhotoStore photos;

  /// Photos de profil des comptes.
  final PetPhotoStore? userPhotos;

  /// Administrateur connecté (il ne peut pas se modifier lui-même ici).
  final int adminId;

  void setFilter(UserFilter f) => model.setFilter(f);
  void setQuery(String q) => model.setQuery(q);

  Future<void> load() async {
    try {
      model.setData(await _repo.getAll(), await _repo.stats());
    } on Exception catch (e) {
      model.setError('Impossible de charger les comptes : $e');
    }
  }

  Future<AppUser> setRole(AppUser u, UserRole role) async {
    final saved = await _repo.setRole(u.id, role, actorId: adminId);
    await load();
    return saved;
  }

  Future<AppUser> setActive(AppUser u, bool active) async {
    final saved = await _repo.setActive(u.id, active, actorId: adminId);
    await load();
    return saved;
  }

  /// Crée un compte « user » ou « admin » (avec photo facultative).
  Future<AppUser> create({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? photoPath,
  }) async {
    final saved = await _repo.createAccount(
        name: name, email: email, password: password, role: role,
        photoPath: photoPath, actorId: adminId);
    await load();
    return saved;
  }

  /// Modifie un compte ; l'ancienne photo remplacée est supprimée.
  Future<AppUser> update(
    AppUser u, {
    required String name,
    required String email,
    required UserRole role,
    required bool active,
    String? photoPath,
    String? newPassword,
  }) async {
    final saved = await _repo.updateAccount(u.id,
        name: name, email: email, role: role, active: active,
        photoPath: photoPath, newPassword: newPassword, actorId: adminId);
    if (u.photoPath != null && u.photoPath != photoPath) await userPhotos?.delete(u.photoPath!);
    await load();
    return saved;
  }

  Future<String?> pickPhoto({required bool camera}) async {
    try {
      return await userPhotos?.pick(camera: camera);
    } on Exception {
      return null;
    }
  }

  Future<void> discardPhoto(String? path) async {
    if (path != null) await userPhotos?.delete(path);
  }

  /// Supprime le compte, ses animaux, toutes leurs données et leurs photos.
  Future<void> delete(AppUser u) async {
    final files = await _repo.delete(u.id, actorId: adminId);
    for (final path in files) {
      // Chaque magasin ne supprime que les fichiers de son dossier.
      await photos.delete(path);
      await userPhotos?.delete(path);
    }
    await load();
  }
}
