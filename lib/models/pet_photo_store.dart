import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Photos (animaux et comptes) : prise de vue / galerie, puis copie dans le
/// stockage privé de l'app (la photo reste disponible même si l'original
/// est effacé).
abstract interface class PetPhotoStore {
  /// Renvoie le chemin de la photo enregistrée, ou `null` si annulé.
  Future<String?> pick({required bool camera});

  Future<void> delete(String path);
}

class DevicePetPhotoStore implements PetPhotoStore {
  DevicePetPhotoStore({ImagePicker? picker, this.folder = petFolder})
      : _picker = picker ?? ImagePicker();

  static const petFolder = 'pet_photos';
  static const userFolder = 'user_photos';

  /// Dossier des copies ; seules ces copies sont supprimées.
  final String folder;

  final ImagePicker _picker;

  @override
  Future<String?> pick({required bool camera}) async {
    final image = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) return null;
    final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, folder));
    await dir.create(recursive: true);
    final ext = p.extension(image.path);
    final dest = p.join(dir.path,
        'photo_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}');
    await image.saveTo(dest);
    return dest;
  }

  @override
  Future<void> delete(String path) async {
    // Seules les copies faites par l'app sont supprimées.
    if (!p.split(path).contains(folder)) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Déjà supprimée.
    }
  }
}
