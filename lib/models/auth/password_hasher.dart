import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Empreinte des mots de passe : PBKDF2-HMAC-SHA256 avec un sel aléatoire.
///
/// Le mot de passe n'est jamais enregistré : seule l'empreinte l'est, au
/// format `pbkdf2-sha256$<itérations>$<sel>$<empreinte>` (base64).
class PasswordHasher {
  /// [iterations] réduit dans les tests pour aller plus vite.
  PasswordHasher({this.iterations = 20000, Random? random})
      : _random = random ?? Random.secure();

  static const _scheme = 'pbkdf2-sha256';
  static const _saltLength = 16;

  final int iterations;
  final Random _random;

  String hash(String password) {
    final salt = List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    final key = _pbkdf2(utf8.encode(password), salt, iterations);
    return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  bool verify(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      return _equals(_pbkdf2(utf8.encode(password), salt, rounds), expected);
    } on FormatException {
      return false;
    }
  }

  /// Un seul bloc de 32 octets (taille de SHA-256).
  static List<int> _pbkdf2(List<int> password, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.of(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  /// Comparaison en temps constant.
  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
