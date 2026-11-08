import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pet.dart';
import 'pet_avatar.dart';

/// Photo de l'animal, ou l'emoji de son espèce si aucune photo.
class PetPhoto extends StatelessWidget {
  const PetPhoto({
    super.key,
    required this.species,
    required this.color,
    this.path,
    this.size = 96,
    this.radius,
  });

  /// Photo d'un animal enregistré.
  factory PetPhoto.of(Pet pet, {double size = 96, double? radius}) => PetPhoto(
        species: pet.species,
        path: pet.photoPath,
        color: pet.id == null ? Colors.grey : PetAvatar.colorOf(pet.toSummary()),
        size: size,
        radius: radius,
      );

  final Species species;
  final String? path;
  final Color color;
  final double size;

  /// Coins arrondis ; cercle si null.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final shape = radius == null
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius!));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: shape,
        color: color.withValues(alpha: 0.14),
      ),
      alignment: Alignment.center,
      child: path == null
          ? Text(species.emoji, style: TextStyle(fontSize: size * 0.45))
          : Image.file(
              File(path!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) =>
                  Text(species.emoji, style: TextStyle(fontSize: size * 0.45)),
            ),
    );
  }
}
