import 'package:intl/intl.dart';

/// Dates en français, partagées par tous les modules.
abstract final class Fmt {
  static final _long = DateFormat('EEEE d MMMM y', 'fr_FR');
  static final _medium = DateFormat('EEE d MMM', 'fr_FR');
  static final _short = DateFormat('d MMM', 'fr_FR');
  static final _time = DateFormat('HH:mm', 'fr_FR');
  static final _weekday = DateFormat('EEE', 'fr_FR');
  static final _month = DateFormat('MMMM y', 'fr_FR');
  static final _monthShort = DateFormat('MMM', 'fr_FR');
  static final _dayMonth = DateFormat('dd/MM', 'fr_FR');

  static String long(DateTime d) => _cap(_long.format(d));
  static String medium(DateTime d) => _cap(_medium.format(d));
  static String short(DateTime d) => _short.format(d);
  static String time(DateTime d) => _time.format(d);
  static String weekday(DateTime d) =>
      _cap(_weekday.format(d)).replaceAll('.', '');
  static String dateTime(DateTime d) => '${medium(d)} · ${time(d)}';

  /// « Novembre 2026 ».
  static String month(DateTime d) => _cap(_month.format(d));

  /// « Nov » (axes des graphiques).
  static String monthShort(DateTime d) =>
      _cap(_monthShort.format(d)).replaceAll('.', '');

  /// « 03/11 ».
  static String dayMonth(DateTime d) => _dayMonth.format(d);

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Nombres et unités (modules Alimentation et Activités).
abstract final class Units {
  /// Devise affichée pour les prix.
  static const currency = 'DT';

  static final _int = NumberFormat('#,##0', 'fr_FR');
  static final _one = NumberFormat('#,##0.0', 'fr_FR');
  static final _two = NumberFormat('#,##0.00', 'fr_FR');
  static final _upToTwo = NumberFormat('#,##0.##', 'fr_FR');

  static String money(double v) => '${_two.format(v)} $currency';

  /// « 350 g » ou « 1,25 kg ».
  static String grams(double g) => g.abs() >= 1000
      ? '${_upToTwo.format(g / 1000)} kg'
      : '${_int.format(g)} g';

  static String km(double v) => '${_one.format(v)} km';
  static String kg(double v) => '${_upToTwo.format(v)} kg';
  static String kcal(double v) => '${_int.format(v)} kcal';
  static String speed(double v) => '${_one.format(v)} km/h';

  /// Valeur sans unité (étiquettes des graphiques).
  static String number(double v, {int decimals = 1}) =>
      (decimals == 0 ? _int : decimals == 1 ? _one : _two).format(v);

  /// « 45 min », « 1 h », « 1 h 05 ».
  static String minutes(num m) {
    final t = m.round();
    if (t < 60) return '$t min';
    final h = t ~/ 60, r = t % 60;
    return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
  }

  /// Variation relative : 0.18 => « +18 % ».
  static String percent(double ratio) {
    final v = (ratio * 100).round();
    return '${v > 0 ? '+' : ''}$v %';
  }

  /// Chronomètre : « 05:42 » ou « 1:05:42 ».
  static String stopwatch(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
