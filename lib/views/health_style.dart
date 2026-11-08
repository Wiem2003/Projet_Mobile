import 'package:flutter/material.dart';

import '../models/health_record.dart';

export 'formatters.dart';

extension HealthTypeStyle on HealthType {
  IconData get icon => switch (this) {
        HealthType.vaccination => Icons.vaccines_rounded,
        HealthType.treatment => Icons.medication_rounded,
        HealthType.consultation => Icons.medical_services_rounded,
        HealthType.dental => Icons.cleaning_services_rounded,
        HealthType.analysis => Icons.science_rounded,
        HealthType.other => Icons.healing_rounded,
      };

  Color get color => switch (this) {
        HealthType.vaccination => const Color(0xFFDC2626),
        HealthType.treatment => const Color(0xFFDB2777),
        HealthType.consultation => const Color(0xFF2563EB),
        HealthType.dental => const Color(0xFF0D9488),
        HealthType.analysis => const Color(0xFF7C3AED),
        HealthType.other => const Color(0xFF64748B),
      };
}
