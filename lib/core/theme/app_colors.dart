import 'package:flutter/material.dart';

/// Palette Smart Pet : chaque module a sa couleur (cf. document de présentation).
abstract final class AppColors {
  static const primary = Color(0xFF0F766E); // Teal - Dashboard / marque

  static const pet = Color(0xFFD97706); // Module 1 - Animaux
  static const health = Color(0xFFDC2626); // Module 2 - Santé
  static const feeding = Color(0xFF65A30D); // Module 3 - Alimentation
  static const activity = Color(0xFF2563EB); // Module 4 - Activités
  static const reminder = Color(0xFF7C3AED); // Module 5 - Rappels

  static const petDeep = Color(0xFF92400E);
  static const healthDeep = Color(0xFF991B1B);
  static const feedingDeep = Color(0xFF3F6212);
  static const activityDeep = Color(0xFF1E40AF);
  static const reminderDeep = Color(0xFF5B21B6);
  static const reminderSoft = Color(0xFFA78BFA);

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
}
