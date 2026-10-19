import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';
import 'dart:io';

/// Écran de re-soumission après un refus de la demande livreur.
///
/// Même logique que VendorReapplyScreen (voir son commentaire d'en-tête) :
/// le serveur (DeliveryAgentsService.submitProfile) sait déjà transformer
/// une re-soumission en mise à jour du même profil refusé, mais rien dans
/// l'app ne permettait d'y accéder après l'inscription initiale. Cet
/// écran comble ce manque, pré-rempli avec l'ancien dossier du livreur.
class AgentReapplyScreen extends StatefulWidget {
  const AgentReapplyScreen({super.key});

  @override
  State<AgentReapplyScreen> createState() => _AgentReapplyScreenState();
}

class _AgentReapplyScreenState extends State<AgentReapplyScreen> {
  static const List<Map<String, String>> _vehicleTypes = [
    {'value': 'moto', 'label': 'Moto'},
    {'value': 'voiture', 'label': 'Voiture'},
    {'value': 'tricycle', 'label': 'Tricycle'},
    {'value': 'velo', 'label': 'Vélo'},
  ];

  static const List<Map<String, String>> _availabilities = [
    {'value': 'Temps_plein', 'label': 'Temps plein'},
    {'value': 'Temps_partiel', 'label': 'Temps partiel'},
  ];

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _rejectionReason;

  final _villeController = TextEditingController();
  final _quartierController = TextEditingController();
  final _preciseAddressController = TextEditingController();
  final _licensePlateController = TextEditingController();

  String _vehicleType = 'moto';
  String _availability = 'Temps_plein';

  // String (URL déjà en base) ou XFile (nouveau fichier choisi).
  dynamic _idDocument;
  dynamic _selfie;
  dynamic _vehiclePhoto;


  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _villeController.dispose();
    _quartierController.dispose();
    _preciseAddressController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/delivery-agents/me');
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      if (data['status'] != 'rejeté') {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = 'Cette demande n\'est pas (ou plus) refusée.';
          });
        }
        return;
      }

      _villeController.text = data['ville']?.toString() ?? '';
      _quartierController.text = data['quartier']?.toString() ?? '';
      _preciseAddressController.text = data['preciseAddress']?.toString() ?? '';
      _licensePlateController.text = data['licensePlate']?.toString() ?? '';
      final vehicle = data['vehicleType']?.toString() ?? '';
      _vehicleType = _vehicleTypes.any((v) => v['value'] == vehicle)
          ? vehicle
          : 'moto';
      final avail = data['availability']?.toString() ?? '';
      _availability = _availabilities.any((a) => a['value'] == avail)
          ? avail
          : 'Temps_plein';
      _idDocument = data['idDocumentUrl']?.toString();
      _selfie = data['selfieUrl']?.toString();
      _vehiclePhoto = data['vehiclePhotoUrl']?.toString();
      _rejectionReason = data['motifRefus']?.toString();

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

  bool get _licensePlateValid => RegExp(r'^[A-Z0-9\s\-]{3,20}$', caseSensitive: false)
      .hasMatch(_licensePlateController.text.trim());

  bool get _canSubmit =>
      _villeController.text.trim().length >= 2 &&
      _quartierController.text.trim().length >= 2 &&
      _preciseAddressController.text.trim().length >= 5 &&
      _licensePlateValid &&
      _idDocument != null &&
      _selfie != null &&
      _vehiclePhoto != null;

  Future<String> _resolveUrl(dynamic value, String uploadType) async {
    if (value is String) return value;
    if (value is XFile) {
      return UploadService.instance.uploadFile(value, uploadType);
    }
    throw StateError('Fichier manquant');
  }

  Future<void> _handleSubmit() async {
    if (_villeController.text.trim().length < 2) {
      AppToast.show(context, message: 'La ville est trop courte.', type: ToastType.error);
      return;
    }
    if (_quartierController.text.trim().length < 2) {
      AppToast.show(context, message: 'Le quartier est trop court.', type: ToastType.error);
      return;
    }
    if (_preciseAddressController.text.trim().length < 5) {
      AppToast.show(context,
          message: 'L\'adresse précise est trop courte.', type: ToastType.error);
      return;
    }
    if (!_licensePlateValid) {
      AppToast.show(context,
          message: 'Format de plaque invalide (ex : AB 1234 CD).',
          type: ToastType.error);
      return;
    }
    if (_idDocument == null || _selfie == null || _vehiclePhoto == null) {
      AppToast.show(context,
          message:
              'Merci de fournir la pièce d\'identité, le selfie et la photo du véhicule.',
          type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final idDocumentUrl = await _resolveUrl(_idDocument, 'documents');
      final selfieUrl = await _resolveUrl(_selfie, 'selfies');
      final vehiclePhotoUrl = await _resolveUrl(_vehiclePhoto, 'vehicles');

      final result = await NestAuthService.instance.submitAgentProfile(
        vehicleType: _vehicleType,
        availability: _availability,
        ville: _villeController.text.trim(),
        quartier: _quartierController.text.trim(),
        preciseAddress: _preciseAddressController.text.trim(),
        idDocumentUrl: idDocumentUrl,
        selfieUrl: selfieUrl,
        vehiclePhotoUrl: vehiclePhotoUrl,
        licensePlate: _licensePlateController.text.trim(),
      );

      if (!mounted) return;

      if (result.success) {
        AppToast.show(
          context,
          message: 'Dossier renvoyé ! Vous serez notifié par email.',
          type: ToastType.success,
          duration: const Duration(seconds: 5),
        );
        Navigator.pop(context, true);
      } else {
        AppToast.show(
          context,
          message: result.error ?? 'Erreur lors de l\'envoi du dossier.',
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi du dossier. Réessayez.',
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
          'Corriger ma demande',
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
          if (_rejectionReason != null && _rejectionReason!.isNotEmpty)
            _buildRejectionBanner(),
          const SizedBox(height: 16),
          Text(
            'Corrigez les informations ci-dessous puis renvoyez votre dossier. '
            'Il repassera par une nouvelle validation.',
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          _buildDropdown(
            label: 'Type d\'engin',
            value: _vehicleType,
            options: _vehicleTypes,
            onChanged: (v) => setState(() => _vehicleType = v),
          ),
          const SizedBox(height: 14),
          _buildDropdown(
            label: 'Disponibilité',
            value: _availability,
            options: _availabilities,
            onChanged: (v) => setState(() => _availability = v),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _villeController,
            label: 'Ville',
            hint: 'Ex : Cotonou',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _quartierController,
            label: 'Quartier',
            hint: 'Ex : Fidjrossè',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _preciseAddressController,
            label: 'Adresse précise',
            hint: 'Ex : Rue 234, non loin du carrefour',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _licensePlateController,
            label: 'Numéro de plaque',
            hint: 'Ex : AB 1234 CD',
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
              onPressed: (_isSubmitting || !_canSubmit) ? null : _handleSubmit,
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
                      'Renvoyer ma demande',
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

  Widget _buildRejectionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppTheme.error),
              const SizedBox(width: 8),
              Text(
                'Motif du refus',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _rejectionReason ?? '',
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.muted),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.outline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.muted),
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textPrimary),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o['value'],
                        child: Text(o['label'] ?? ''),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSinglePhotoPicker({
    required String label,
    required dynamic value,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
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
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    hasValue ? 'Toucher pour remplacer' : 'Toucher pour ajouter',
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
