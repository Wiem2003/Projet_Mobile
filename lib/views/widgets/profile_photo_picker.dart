import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Photo ronde, ou les initiales si aucune photo (ou fichier introuvable).
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({
    super.key,
    required this.initials,
    this.path,
    this.size = 44,
    this.color = AppColors.primary,
  });

  final String initials;
  final String? path;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Text(initials,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
    if (path == null) return fallback;
    return ClipOval(
      child: Image.file(
        File(path!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Choix d'une photo de profil : appareil photo, galerie ou retrait.
class ProfilePhotoPicker extends StatelessWidget {
  const ProfilePhotoPicker({
    super.key,
    required this.initials,
    required this.onPick,
    required this.onRemove,
    this.path,
    this.busy = false,
  });

  final String initials;
  final String? path;
  final bool busy;

  /// [camera] : appareil photo, sinon galerie.
  final void Function(bool camera) onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ProfilePhoto(initials: initials, path: path, size: 96),
            if (busy) const CircularProgressIndicator(),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Appareil photo'),
              onPressed: busy ? null : () => onPick(true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Galerie'),
              onPressed: busy ? null : () => onPick(false),
            ),
            if (path != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Retirer'),
                onPressed: busy ? null : onRemove,
              ),
          ],
        ),
      ],
    );
  }
}
