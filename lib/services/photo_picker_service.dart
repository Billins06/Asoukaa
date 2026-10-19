import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Choix d'une photo (appareil photo ou galerie) — un seul endroit pour toute
/// l'application.
///
/// L'appareil photo n'existe que sur un téléphone (Android / iPhone, y compris
/// dans le navigateur d'un téléphone). Sur un ordinateur (Windows, Mac, Linux,
/// ou Chrome sur PC), « Prendre une photo » ouvrirait en réalité l'explorateur
/// de fichiers : on ne propose donc que la galerie / les fichiers.
class PhotoPickerService {
  PhotoPickerService._();

  static final ImagePicker _picker = ImagePicker();

  /// Vrai si l'appareil peut réellement ouvrir un appareil photo.
  static bool get cameraAvailable =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Affiche la feuille « Prendre une photo / Choisir dans la galerie ».
  /// Renvoie directement la galerie si aucun appareil photo n'est disponible.
  static Future<ImageSource?> askSource(BuildContext context) async {
    if (!cameraAvailable) return ImageSource.gallery;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.primary),
              title: Text('Prendre une photo', style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary),
              title: Text('Choisir dans la galerie',
                  style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Ouvre directement la source donnée (appareil photo ou galerie).
  /// `camera` est ignoré (galerie) si l'appareil n'a pas d'appareil photo.
  /// Renvoie null si l'utilisateur annule ou si l'accès est refusé.
  static Future<XFile?> pickFrom(
    BuildContext context,
    ImageSource source, {
    int imageQuality = 85,
    double? maxWidth = 1600,
    bool frontCamera = false,
  }) async {
    final effective =
        (source == ImageSource.camera && !cameraAvailable)
            ? ImageSource.gallery
            : source;
    try {
      return await _picker.pickImage(
        source: effective,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        preferredCameraDevice:
            frontCamera ? CameraDevice.front : CameraDevice.rear,
      );
    } catch (_) {
      if (context.mounted) {
        AppToast.show(
          context,
          message: effective == ImageSource.camera
              ? 'Impossible d\'ouvrir l\'appareil photo. Autorisez la caméra dans les réglages du téléphone.'
              : 'Impossible de récupérer cette photo.',
          type: ToastType.error,
        );
      }
      return null;
    }
  }

  /// Demande la source puis ouvre l'appareil photo ou la galerie.
  static Future<XFile?> pick(
    BuildContext context, {
    int imageQuality = 85,
    double? maxWidth = 1600,
    bool frontCamera = false,
  }) async {
    final source = await askSource(context);
    if (source == null || !context.mounted) return null;
    return pickFrom(
      context,
      source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      frontCamera: frontCamera,
    );
  }
}
