import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/auth/captcha.dart';

/// Captcha « Je ne suis pas un robot » : la case, puis un code déformé à
/// recopier. L'écran appelle [CaptchaBoxState.ensureVerified] avant
/// d'envoyer le formulaire et [CaptchaBoxState.reset] si la tentative est
/// refusée.
class CaptchaBox extends StatefulWidget {
  const CaptchaBox({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<CaptchaBox> createState() => CaptchaBoxState();
}

class CaptchaBoxState extends State<CaptchaBox> {
  /// Délai de « vérification » après la case cochée.
  static const checkingDelay = Duration(milliseconds: 700);

  late final CaptchaState _captcha;
  final _text = TextEditingController();
  Timer? _timer;
  String? _error;

  bool get verified => _captcha.verified;

  @override
  void initState() {
    super.initState();
    // Générateur remplaçable (tests) ; aléatoire sécurisé par défaut.
    _captcha = CaptchaState(context.read<CaptchaGenerator?>() ?? CaptchaGenerator());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _check() {
    if (!widget.enabled || _captcha.step != CaptchaStep.unchecked) return;
    setState(() {
      _captcha.check();
      _error = null;
    });
    _timer = Timer(checkingDelay, () {
      if (mounted) setState(_captcha.showChallenge);
    });
  }

  void _verify() {
    final error = _captcha.submit(_text.text);
    setState(() {
      _error = error;
      if (error != null) _text.clear();
    });
    if (error == null) FocusScope.of(context).unfocus();
  }

  void _refresh() => setState(() {
        _captcha.refresh();
        _text.clear();
        _error = null;
      });

  /// Vérifie le captcha avant l'envoi du formulaire (affiche l'erreur).
  bool ensureVerified() {
    if (_captcha.verified) return true;
    if (_captcha.step == CaptchaStep.challenge) {
      _verify();
    } else {
      setState(() => _error = 'Cochez « Je ne suis pas un robot ».');
    }
    return _captcha.verified;
  }

  /// Tentative refusée : le captcha est à refaire.
  void reset() {
    _timer?.cancel();
    setState(() {
      _captcha.reset();
      _text.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _captcha.step;
    final showError = _error != null && step != CaptchaStep.challenge;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: showError ? AppColors.danger : scheme.outlineVariant,
            width: showError ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: step == CaptchaStep.unchecked ? _check : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: switch (step) {
                        CaptchaStep.unchecked => Checkbox(
                            value: false,
                            onChanged: widget.enabled ? (_) => _check() : null,
                          ),
                        CaptchaStep.checking => const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        CaptchaStep.challenge => Icon(Icons.pending_outlined,
                            color: scheme.primary, size: 26),
                        CaptchaStep.verified => const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 28),
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      step == CaptchaStep.verified ? 'Vérifié : vous n\'êtes pas un robot' : 'Je ne suis pas un robot',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: step == CaptchaStep.verified ? AppColors.success : null,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_outlined, color: scheme.primary, size: 22),
                      Text('Captcha',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (step == CaptchaStep.challenge)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 60,
                              child: CustomPaint(
                                key: const ValueKey('captcha-image'),
                                painter: CaptchaPainter(_captcha.challenge),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nouveau code',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _text,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(CaptchaGenerator.length),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Recopiez le code',
                      prefixIcon: const Icon(Icons.keyboard_alt_outlined),
                      errorText: _error,
                      errorMaxLines: 2,
                      isDense: true,
                    ),
                    onChanged: (v) {
                      if (v.length == CaptchaGenerator.length) _verify();
                    },
                    onSubmitted: (_) => _verify(),
                  ),
                ],
              ),
            ),
          if (showError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

/// Dessine le code : caractères tournés, décalés et de couleurs variées,
/// traits et points de brouillage. Même graine = même image.
class CaptchaPainter extends CustomPainter {
  CaptchaPainter(this.challenge);

  final CaptchaChallenge challenge;

  static const _inks = [
    Color(0xFF1E3A8A),
    Color(0xFF7C2D12),
    Color(0xFF14532D),
    Color(0xFF581C87),
    Color(0xFF111827),
    Color(0xFF9F1239),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(challenge.seed);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF8FAFC)],
        ).createShader(rect),
    );

    // Points de fond.
    final dot = Paint();
    for (var i = 0; i < 70; i++) {
      dot.color = _inks[r.nextInt(_inks.length)].withValues(alpha: 0.25);
      canvas.drawCircle(Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          0.8 + r.nextDouble() * 1.2, dot);
    }

    void noise(int count, double alpha) {
      for (var i = 0; i < count; i++) {
        final p = Paint()
          ..color = _inks[r.nextInt(_inks.length)].withValues(alpha: alpha)
          ..strokeWidth = 1 + r.nextDouble() * 1.5
          ..style = PaintingStyle.stroke;
        final path = Path()
          ..moveTo(0, r.nextDouble() * size.height)
          ..cubicTo(
            size.width * 0.3, r.nextDouble() * size.height,
            size.width * 0.7, r.nextDouble() * size.height,
            size.width, r.nextDouble() * size.height,
          );
        canvas.drawPath(path, p);
      }
    }

    noise(3, 0.35);

    // Caractères.
    final code = challenge.code;
    final slot = size.width / (code.length + 1);
    for (var i = 0; i < code.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: code[i],
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 26 + r.nextDouble() * 8,
            fontWeight: FontWeight.w800,
            fontStyle: r.nextBool() ? FontStyle.italic : FontStyle.normal,
            color: _inks[r.nextInt(_inks.length)],
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final center = Offset(
        slot * (i + 1) + (r.nextDouble() - 0.5) * slot * 0.3,
        size.height / 2 + (r.nextDouble() - 0.5) * 12,
      );
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate((r.nextDouble() - 0.5) * 0.8);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    noise(2, 0.55);
  }

  @override
  bool shouldRepaint(CaptchaPainter old) =>
      old.challenge.code != challenge.code || old.challenge.seed != challenge.seed;
}
