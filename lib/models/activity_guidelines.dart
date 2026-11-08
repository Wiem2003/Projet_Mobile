import 'pet.dart';

/// Activité conseillée selon l'espèce et la taille. Source unique des
/// objectifs : module Activités, indice Smart Pet et ration conseillée.
abstract final class ActivityGuidelines {
  /// Minutes par jour conseillées (min, max), `null` sans référence.
  ///
  /// | Profil                         | par jour      |
  /// | petit chien (moins de 10 kg)   | 30 à 60 min   |
  /// | chien moyen (10 à 25 kg)       | 60 à 90 min   |
  /// | grand chien (plus de 25 kg)    | 90 à 120 min  |
  /// | chat : 2 séances de jeu de 15 min | 30 à 60 min |
  static (int, int)? dailyMinutes(Species s, double? kg) => switch (s) {
        Species.dog when kg != null && kg < 10 => (30, 60),
        Species.dog when kg != null && kg > 25 => (90, 120),
        Species.dog => (60, 90),
        Species.cat => (30, 60),
        _ => null,
      };

  /// « grand chien (plus de 25 kg) », « chat ».
  static String? profile(Species s, double? kg) => switch (s) {
        Species.dog when kg != null && kg < 10 => 'petit chien (moins de 10 kg)',
        Species.dog when kg != null && kg > 25 => 'grand chien (plus de 25 kg)',
        Species.dog => 'chien moyen (10 à 25 kg)',
        Species.cat => 'chat',
        _ => null,
      };

  /// « grand chien », « chat » (dans les messages).
  static String? shortProfile(Species s, double? kg) => profile(s, kg)?.split(' (').first;

  /// Objectif par semaine (minutes) : le minimum conseillé × 7 pour les
  /// chiens et les chats ; repères fixes pour le lapin et le cheval.
  static int? weeklyGoalMinutes(Species s, double? kg) {
    final daily = dailyMinutes(s, kg);
    if (daily != null) return daily.$1 * 7;
    return switch (s) {
      Species.rabbit => 120,
      Species.horse => 420,
      _ => null,
    };
  }
}
