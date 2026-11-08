import 'package:flutter/material.dart';

import '../models/activity.dart';

export 'formatters.dart';

extension ActivityTypeStyle on ActivityType {
  IconData get icon => switch (this) {
        ActivityType.walk => Icons.directions_walk_rounded,
        ActivityType.run => Icons.directions_run_rounded,
        ActivityType.play => Icons.sports_tennis_rounded,
        ActivityType.swim => Icons.pool_rounded,
        ActivityType.other => Icons.pets_rounded,
      };

  Color get color => switch (this) {
        ActivityType.walk => const Color(0xFF2563EB),
        ActivityType.run => const Color(0xFFDC2626),
        ActivityType.play => const Color(0xFFF59E0B),
        ActivityType.swim => const Color(0xFF0891B2),
        ActivityType.other => const Color(0xFF7C3AED),
      };
}
