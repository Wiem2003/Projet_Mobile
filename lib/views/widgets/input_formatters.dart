import 'package:flutter/services.dart';

/// Nombre décimal : chiffres et une seule virgule (le point est remplacé),
/// au plus [decimals] décimales et [maxDigits] chiffres avant la virgule.
/// Les lettres et symboles sont refusés dès la frappe.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter({this.decimals = 2, this.maxDigits = 5})
      : _pattern = RegExp('^\\d{0,$maxDigits}(,\\d{0,$decimals})?\$');

  final int decimals;
  final int maxDigits;
  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll('.', ',').replaceAll(' ', '');
    if (!_pattern.hasMatch(text)) return oldValue;
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Nombre entier positif de [maxDigits] chiffres au plus (durée en minutes).
List<TextInputFormatter> integerInput({int maxDigits = 4}) => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxDigits),
    ];

/// Numéro de puce ou de tatouage : lettres et chiffres, en majuscules.
class IdentificationInputFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'^[A-Za-z0-9 ]*$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!_allowed.hasMatch(newValue.text)) return oldValue;
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
