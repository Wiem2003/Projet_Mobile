/// Notification immédiate d'un exploit (nouveau record d'activité).
abstract interface class AchievementNotifier {
  Future<void> showAchievement({required String title, required String body});
}
