import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:smart_pet/controllers/feeding_plan_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_plan.dart';
import 'package:smart_pet/models/health_model.dart';

/// Providers des sacs, programmes de poids et budget pour les tests de
/// l'écran Alimentation ([health] : ajoute un HealthModel vide).
List<SingleChildWidget> feedingPlanProviders(
  FeedingModel feeding, {
  FeedingPlanStore? store,
  RemindersController? reminders,
  bool health = true,
}) {
  final model = FeedingPlanModel();
  final controller = FeedingPlanController(
    model: model,
    planStore: store ?? MemoryFeedingPlanStore(),
    petList: () => feeding.pets,
    feedingRecords: () => feeding.all,
    reminders: reminders,
    clock: () => feeding.now,
  );
  controller.load();
  return [
    ChangeNotifierProvider.value(value: model),
    Provider.value(value: controller),
    if (health) ChangeNotifierProvider.value(value: HealthModel(clock: () => feeding.now)),
  ];
}
