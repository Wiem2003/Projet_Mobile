/// Rôle d'un compte.
enum UserRole {
  user('Utilisateur'),
  admin('Administrateur');

  const UserRole(this.label);

  final String label;

  static UserRole parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => user);
}

/// Entité AppUser, une ligne de la table SQLite `users`. Le mot de passe
/// n'est jamais chargé dans cet objet (seulement son empreinte, en base).
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = UserRole.user,
    this.active = true,
    this.lastLoginAt,
    this.createdAt,
    this.photoPath,
  });

  static const maxNameLength = 40;

  final int id;
  final String name;
  final String email;
  final UserRole role;

  /// Un compte désactivé par un administrateur ne peut plus se connecter.
  final bool active;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  /// Photo de profil copiée dans le stockage de l'app (facultative).
  final String? photoPath;

  bool get isAdmin => role == UserRole.admin;

  /// Initiales affichées dans l'avatar (« Sofien Zitoun » → « SZ »).
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
    return letters.isEmpty ? '?' : letters.join();
  }

  AppUser copyWith({String? name, UserRole? role, bool? active, String? Function()? photoPath}) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        role: role ?? this.role,
        active: active ?? this.active,
        lastLoginAt: lastLoginAt,
        createdAt: createdAt,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
      );

  factory AppUser.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return AppUser(
      id: map['id'] as int,
      name: map['name'] as String,
      email: map['email'] as String,
      role: UserRole.parse(map['role'] as String?),
      active: (map['active'] as int? ?? 1) == 1,
      lastLoginAt: date('last_login_at'),
      createdAt: date('created_at'),
      photoPath: map['photo_path'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.active == active &&
      other.email == email &&
      other.photoPath == photoPath;

  @override
  int get hashCode => Object.hash(id, name, role, active, email, photoPath);

  @override
  String toString() => 'AppUser(#$id $email ${role.name})';
}

/// Ligne de la liste des comptes (écran Administration).
class UserSummary {
  const UserSummary({required this.user, this.pets = 0, this.reminders = 0});

  final AppUser user;
  final int pets;
  final int reminders;
}

/// Chiffres de l'écran Administration.
class AdminStats {
  const AdminStats({
    this.users = 0,
    this.admins = 0,
    this.disabled = 0,
    this.pets = 0,
    this.healthRecords = 0,
    this.feedingRecords = 0,
    this.activities = 0,
    this.reminders = 0,
  });

  final int users;
  final int admins;
  final int disabled;
  final int pets;
  final int healthRecords;
  final int feedingRecords;
  final int activities;
  final int reminders;
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
