import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';
import 'dart:io';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';

/// Écran "Compléter mon dossier" pour un livreur dont le compte est déjà
/// créé et en attente de validation, mais à qui il manque encore un ou
/// plusieurs documents (pièce d'identité, selfie, photo du véhicule).
///
/// Même logique que VendorCompleteDocumentsScreen (voir son commentaire
/// d'en-tête) : via le PATCH /api/v1/delivery-agents/me/documents (voir
/// NestAuthService.completeAgentDocuments), qui ne met à jour que les
/// champs envoyés.
class AgentCompleteDocumentsScreen extends StatefulWidget {
  const AgentCompleteDocumentsScreen({super.key});

  @override
  State<AgentCompleteDocumentsScreen> createState() =>
      _AgentCompleteDocumentsScreenState();
}

class _AgentCompleteDocumentsScreenState
    extends State<AgentCompleteDocumentsScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  // Chaque champ garde soit l'URL déjà en base (String, document déjà
  // fourni), soit null (document manquant), soit un XFile si l'utilisateur
  // vient de (re)choisir une photo. Seuls les XFile seront uploadés et
  // envoyés au serveur ; une String inchangée n'est jamais renvoyée.
  dynamic _idDocument;
  dynamic _selfie;
  dynamic _vehiclePhoto;


  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/delivery-agents/me');
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      final idDoc = data['idDocumentUrl']?.toString();
      final selfie = data['selfieUrl']?.toString();
      final vehicle = data['vehiclePhotoUrl']?.toString();

      _idDocument = (idDoc != null && idDoc.isNotEmpty) ? idDoc : null;
      _selfie = (selfie != null && selfie.isNotEmpty) ? selfie : null;
      _vehiclePhoto = (vehicle != null && vehicle.isNotEmpty) ? vehicle : null;

      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Impossible de charger votre dossier livreur.';
        });
      }
    }
  }

  Future<void> _pickIdDocument() async {
    final file =
        await PhotoPickerService.pick(context, imageQuality: 90);
    if (file != null && mounted) setState(() => _idDocument = file);
  }

  Future<void> _pickSelfie() async {
    final file =
        await PhotoPickerService.pick(context, imageQuality: 90, frontCamera: true);
    if (file != null && mounted) setState(() => _selfie = file);
  }

  Future<void> _pickVehiclePhoto() async {
    final file =
        await PhotoPickerService.pick(context, imageQuality: 85);
    if (file != null && mounted) setState(() => _vehiclePhoto = file);
  }

  bool get _hasAnyNewFile =>
      _idDocument is XFile || _selfie is XFile || _vehiclePhoto is XFile;

  Future<void> _handleSubmit() async {
    if (!_hasAnyNewFile) {
      AppToast.show(
        context,
        message: 'Choisissez au moins un document avant d\'envoyer.',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final idDocumentUrl = _idDocument is XFile
          ? await UploadService.instance.uploadFile(_idDocument as XFile, 'documents')
          : null;
      final selfieUrl = _selfie is XFile
          ? await UploadService.instance.uploadFile(_selfie as XFile, 'selfies')
          : null;
      final vehiclePhotoUrl = _vehiclePhoto is XFile
          ? await UploadService.instance.uploadFile(_vehiclePhoto as XFile, 'vehicles')
          : null;

      final result = await NestAuthService.instance.completeAgentDocuments(
        idDocumentUrl: idDocumentUrl,
        selfieUrl: selfieUrl,
        vehiclePhotoUrl: vehiclePhotoUrl,
      );

      if (!mounted) return;

      if (result.success) {
        AppToast.show(
          context,
          message: 'Documents envoyés ! Votre dossier sera revérifié.',
          type: ToastType.success,
          duration: const Duration(seconds: 5),
        );
        Navigator.pop(context, true);
      } else {
        AppToast.show(
          context,
          message: result.error ?? 'Erreur lors de l\'envoi des documents.',
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi des documents. Réessayez.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Compléter mon dossier',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _loadError != null
              ? _buildErrorState()
              : _buildForm(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajoutez les documents qui manquent encore à votre dossier. '
            'Les documents déjà fournis sont indiqués ci-dessous et peuvent '
            'être remplacés si besoin.',
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          Text(
            'Documents de vérification',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _buildSinglePhotoPicker(
            label: 'Pièce d\'identité',
            value: _idDocument,
            onTap: _pickIdDocument,
          ),
          const SizedBox(height: 10),
          _buildSinglePhotoPicker(
            label: 'Selfie',
            value: _selfie,
            onTap: _pickSelfie,
          ),
          const SizedBox(height: 10),
          _buildSinglePhotoPicker(
            label: 'Photo du véhicule',
            value: _vehiclePhoto,
            onTap: _pickVehiclePhoto,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      'Envoyer',
                      style: GoogleFonts.outfit(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSinglePhotoPicker({
    required String label,
    required dynamic value,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    final alreadyProvided = value is String;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasValue ? AppTheme.success.withAlpha(90) : AppTheme.outline,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: hasValue
                  ? (value is String
                      ? CustomImageWidget(
                          imageUrl: value,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          semanticLabel: label,
                        )
                      : (kIsWeb
                          ? Image.network(
                              (value as XFile).path,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File((value as XFile).path),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            )))
                  : Container(
                      width: 48,
                      height: 48,
                      color: AppTheme.background,
                      child: const Icon(Icons.image_outlined,
                          color: AppTheme.muted, size: 20),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (alreadyProvided) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_rounded,
                            size: 14, color: AppTheme.success),
                      ],
                    ],
                  ),
                  Text(
                    alreadyProvided
                        ? 'Déjà fourni — toucher pour remplacer'
                        : hasValue
                            ? 'Nouvelle photo sélectionnée'
                            : 'Toucher pour ajouter',
                    style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}
