import 'package:flutter/material.dart';

import '../models/feeding_record.dart';

export 'formatters.dart';

extension FoodTypeStyle on FoodType {
  IconData get icon => switch (this) {
        FoodType.kibble => Icons.grain_rounded,
        FoodType.wet => Icons.soup_kitchen_rounded,
        FoodType.treats => Icons.cookie_rounded,
        FoodType.homemade => Icons.restaurant_rounded,
        FoodType.other => Icons.fastfood_rounded,
      };

  Color get color => switch (this) {
        FoodType.kibble => const Color(0xFFB45309),
        FoodType.wet => const Color(0xFFDB2777),
        FoodType.treats => const Color(0xFFEA580C),
        FoodType.homemade => const Color(0xFF65A30D),
        FoodType.other => const Color(0xFF64748B),
      };
}
