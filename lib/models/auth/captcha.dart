import 'dart:math' as math;

/// Code d'un captcha et graine de sa déformation (position, angle et
/// couleur de chaque caractère, traits de brouillage).
class CaptchaChallenge {
  const CaptchaChallenge(this.code, this.seed);

  final String code;
  final int seed;

  /// Saisie correcte : majuscules et minuscules confondues, espaces ignorés.
  bool accepts(String input) => input.replaceAll(RegExp(r'\s'), '').toUpperCase() == code;
}

/// Fabrique les captchas. Remplaçable dans les tests (code connu).
class CaptchaGenerator {
  CaptchaGenerator([math.Random? random]) : _random = random ?? math.Random.secure();

  /// Toujours le même code (tests).
  factory CaptchaGenerator.fixed(String code) = _FixedCaptchaGenerator;

  final math.Random _random;

  /// Sans les caractères faciles à confondre (0/O, 1/I/L).
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const length = 5;

  CaptchaChallenge next() => CaptchaChallenge(
        String.fromCharCodes([
          for (var i = 0; i < length; i++) alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
        ]),
        _random.nextInt(1 << 31),
      );
}

class _FixedCaptchaGenerator extends CaptchaGenerator {
  _FixedCaptchaGenerator(this.code);

  final String code;
  int _seed = 0;

  @override
  CaptchaChallenge next() => CaptchaChallenge(code, _seed++);
}

enum CaptchaStep { unchecked, checking, challenge, verified }

/// Règles du captcha « Je ne suis pas un robot » de la connexion et de
/// l'inscription.
///
/// 1. La case est cochée : un code déformé est affiché.
/// 2. Le code recopié est vérifié ; après [maxAttempts] erreurs, un
///    nouveau code est tiré.
/// 3. Une vérification réussie ne sert qu'une fois : après une tentative
///    de connexion ou d'inscription refusée, il faut recommencer.
class CaptchaState {
  CaptchaState(this._generator) : _challenge = _generator.next();

  static const maxAttempts = 3;

  final CaptchaGenerator _generator;
  CaptchaChallenge _challenge;
  CaptchaStep _step = CaptchaStep.unchecked;
  int _errors = 0;

  CaptchaChallenge get challenge => _challenge;
  CaptchaStep get step => _step;
  bool get verified => _step == CaptchaStep.verified;

  void check() {
    if (_step == CaptchaStep.unchecked) _step = CaptchaStep.checking;
  }

  void showChallenge() {
    if (_step == CaptchaStep.checking) _step = CaptchaStep.challenge;
  }

  /// Vérifie le code ; renvoie le message d'erreur, ou `null` si c'est bon.
  String? submit(String input) {
    if (_step == CaptchaStep.verified) return null;
    if (_step != CaptchaStep.challenge) return 'Cochez « Je ne suis pas un robot ».';
    if (input.trim().isEmpty) return 'Recopiez le code affiché.';
    if (_challenge.accepts(input)) {
      _step = CaptchaStep.verified;
      _errors = 0;
      return null;
    }
    _errors++;
    if (_errors >= maxAttempts) {
      refresh();
      return 'Code incorrect. Un nouveau code a été affiché.';
    }
    return 'Code incorrect (${maxAttempts - _errors} essai${maxAttempts - _errors > 1 ? 's' : ''} '
        'avant un nouveau code).';
  }

  /// Nouveau code (bouton ⟳ ou trop d'erreurs).
  void refresh() {
    _challenge = _generator.next();
    _errors = 0;
    if (_step == CaptchaStep.verified) _step = CaptchaStep.challenge;
  }

  /// Après une tentative refusée : tout recommencer.
  void reset() {
    _challenge = _generator.next();
    _errors = 0;
    _step = CaptchaStep.unchecked;
  }
}
