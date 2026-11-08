/// Erreur métier des modules Alimentation et Activités, affichable telle
/// quelle à l'utilisateur.
class RecordException implements Exception {
  const RecordException(this.message);

  const RecordException.notFound([this.message = 'Enregistrement introuvable.']);

  final String message;

  @override
  String toString() => message;
}

/// Lit un nombre saisi au clavier (« 12,5 » ou « 12.5 »).
double? parseDecimal(String text) {
  final t = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null || v.isNaN || v.isInfinite ? null : v;
}

/// Écrit un nombre dans un champ texte (« 12,5 », « 350 »).
String formatDecimal(double v, {int decimals = 2}) {
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

/// Contrôles de saisie partagés par les formulaires et les entités.
/// Chaque règle renvoie le message à afficher, ou `null` si la valeur est
/// correcte.
abstract final class InputRules {
  static final _hasLetter = RegExp(r'\p{L}', unicode: true);
  static final _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _nameChars =
      RegExp(r"^[\p{L}\p{M}\p{N} '’.\-]+$", unicode: true);
  static final _control =
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F<>{}]');

  /// Nom propre (animal, race, couleur) : lettres, chiffres, espaces,
  /// apostrophes, points et tirets ; au moins une lettre.
  static String? name(String? value, String label,
      {bool required = false, int max = 40}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return required ? '$label est obligatoire' : null;
    if (v.length > max) return '$label : $max caractères maximum';
    if (!_hasLetter.hasMatch(v)) {
      return '$label doit contenir au moins une lettre';
    }
    if (!_nameChars.hasMatch(v)) {
      return '$label : lettres, chiffres, espaces, apostrophes et tirets '
          'uniquement';
    }
    return null;
  }

  /// Texte libre (description, notes, médicament, marque, vétérinaire).
  static String? text(String? value, String label,
      {bool required = false, int max = 500}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return required ? '$label est obligatoire' : null;
    if (v.length > max) return '$label : $max caractères maximum';
    if (_control.hasMatch(v)) return '$label contient des caractères non autorisés';
    if (!_hasLetterOrDigit.hasMatch(v)) {
      return '$label doit contenir des lettres ou des chiffres';
    }
    return null;
  }

  /// Puce électronique (15 chiffres, norme ISO 11784) ou tatouage (4 à 10
  /// lettres et chiffres, au moins une lettre). Facultatif.
  static String? identification(String? value) {
    final v = (value ?? '').replaceAll(' ', '').toUpperCase();
    if (v.isEmpty) return null;
    if (RegExp(r'^\d{15}$').hasMatch(v)) return null;
    if (RegExp(r'^\d+$').hasMatch(v)) {
      return 'Une puce électronique compte 15 chiffres (${v.length} saisis)';
    }
    if (RegExp(r'^[A-Z0-9]{4,10}$').hasMatch(v) && v.contains(RegExp('[A-Z]'))) {
      return null;
    }
    return 'Numéro invalide : puce = 15 chiffres, tatouage = 4 à 10 lettres '
        'et chiffres';
  }

  static final _email = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]{2,}$');

  /// Adresse e-mail du compte (obligatoire, 100 caractères au plus).
  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return "L'adresse e-mail est obligatoire";
    if (v.length > 100 || !_email.hasMatch(v)) return 'Adresse e-mail invalide';
    return null;
  }

  static const minPasswordLength = 8;
  static const maxPasswordLength = 64;

  /// Mot de passe : 8 à 64 caractères, au moins une lettre et un chiffre.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Le mot de passe est obligatoire';
    if (v.length < minPasswordLength) {
      return 'Au moins $minPasswordLength caractères';
    }
    if (v.length > maxPasswordLength) {
      return '$maxPasswordLength caractères maximum';
    }
    if (!_hasLetter.hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Au moins une lettre et un chiffre';
    }
    return null;
  }

  /// La date d'un soin, d'un repas ou d'une activité ne peut pas précéder
  /// la naissance de l'animal.
  static String? notBeforeBirth(DateTime date, DateTime? birth, String petName) {
    if (birth == null) return null;
    final b = DateTime(birth.year, birth.month, birth.day);
    if (!DateTime(date.year, date.month, date.day).isBefore(b)) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'La date est antérieure à la naissance de $petName '
        '(${two(b.day)}/${two(b.month)}/${b.year}).';
  }
}
