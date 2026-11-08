import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';

class PetAvatar extends StatelessWidget {
  const PetAvatar({super.key, required this.pet, this.size = 28});

  final PetSummary pet;
  final double size;

  static const _palette = [
    AppColors.pet,
    AppColors.health,
    AppColors.activity,
    AppColors.feeding,
    AppColors.reminder,
  ];

  static Color colorOf(PetSummary pet) =>
      _palette[pet.id % _palette.length];

  @override
  Widget build(BuildContext context) {
    final color = colorOf(pet);
    final photo = pet.photoPath;
    if (photo != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
          image: DecorationImage(
            image: ResizeImage(FileImage(File(photo)),
                width: (size * 3).round(), allowUpscaling: false),
            fit: BoxFit.cover,
            onError: (_, _) {},
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        pet.initial,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}
