import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/category_multi_select.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';

/// Écran de re-soumission après un refus de la demande vendeur.
///
/// Avant cet écran, un vendeur refusé n'avait AUCUN moyen, depuis
/// l'application, de corriger et renvoyer son dossier : le formulaire
/// vendeur ne s'affichait que lors de la toute première inscription
/// (voir sign_up_login_screen.dart + otp_verification_screen.dart), qui
/// suppose un compte qui n'existe pas encore. Or côté serveur,
/// VendorsService.submitProfile() gère déjà très bien la re-soumission :
/// si le profil existant a status = REJECTED, il est mis à jour (nouveau
/// statut "en attente") au lieu de créer un doublon. Cet écran est donc
/// juste la porte d'entrée manquante vers ce mécanisme déjà en place,
/// pré-remplie avec l'ancien dossier pour ne pas faire tout retaper.
class VendorReapplyScreen extends StatefulWidget {
  const VendorReapplyScreen({super.key});

  @override
  State<VendorReapplyScreen> createState() => _VendorReapplyScreenState();
}

class _VendorReapplyScreenState extends State<VendorReapplyScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _rejectionReason;

  final _shopNameController = TextEditingController();
  final _shopAddressController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<String> _categoryIds = [];

  // Chaque doc/photo garde soit l'URL déjà en base (String, si on ne la
  // remplace pas), soit un nouveau fichier choisi (XFile, uploadé
  // seulement au moment d'envoyer le formulaire).
  dynamic _idDocument; // String? ou XFile?
  dynamic _selfie; // String? ou XFile?
  final List<dynamic> _sampleProducts = []; // List<String|XFile>

  bool _termsAccepted = true;
  bool _fraudAccepted = true;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await ApiService.instance.client.get('/api/v1/vendors/me');
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      if (data['status'] != 'rejeté') {
        // Sécurité : cet écran n'a de sens que pour un dossier refusé.
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = 'Cette demande n\'est pas (ou plus) refusée.';
          });
        }
        return;
      }

      _shopNameController.text = data['shopName']?.toString() ?? '';
      _shopAddressController.text = data['shopAddress']?.toString() ?? '';
      _descriptionController.text = data['description']?.toString() ?? '';
      // Precharge les categories deja choisies (vide pour les anciens
      // vendeurs qui n'avaient qu'un texte libre : ils en choisissent).
      _categoryIds = _categoryIdsFrom(data);
      _idDocument = data['idDocumentUrl']?.toString();
      _selfie = data['selfieUrl']?.toString();
      _sampleProducts
        ..clear()
        ..addAll(
          (data['sampleProductUrls'] as List?)?.map((e) => e.toString()) ??
              const [],
        );
      _rejectionReason = data['motifRefus']?.toString();

      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Impossible de charger votre dossier vendeur.';
        });
      }
    }
  }

  Future<void> _pickIdDocument() async {
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null) setState(() => _idDocument = file);
  }

  Future<void> _pickSelfie() async {
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null) setState(() => _selfie = file);
  }

  Future<void> _pickSampleProduct() async {
    if (_sampleProducts.length >= 3) return;
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _sampleProducts.add(file));
  }

  void _removeSampleProduct(int index) {
    setState(() => _sampleProducts.removeAt(index));
  }

  bool get _canSubmit =>
      _shopNameController.text.trim().length >= 3 &&
      _shopAddressController.text.trim().length >= 5 &&
      _descriptionController.text.trim().length >= 10 &&
      _idDocument != null &&
      _selfie != null &&
      _sampleProducts.isNotEmpty &&
      _termsAccepted &&
      _fraudAccepted;

  // Ids des categories choisies : categoryIds, sinon (reponse sans ce champ)
  // les ids des objets de 'categories'.
  List<String> _categoryIdsFrom(Map<String, dynamic>? data) {
    final ids = data?['categoryIds'];
    if (ids is List && ids.isNotEmpty) {
      return ids.map((e) => e.toString()).toList();
    }
    final cats = data?['categories'];
    if (cats is List) {
      return cats
          .whereType<Map>()
          .map((c) => (c['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  Future<String> _resolveUrl(dynamic value, String uploadType) async {
    if (value is String) return value;
    if (value is XFile) {
      return UploadService.instance.uploadFile(value, uploadType);
    }
    throw StateError('Fichier manquant');
  }

  Future<void> _handleSubmit() async {
    if (_shopNameController.text.trim().length < 3) {
      AppToast.show(context,
          message: 'Le nom de la boutique est trop court (min. 3 caractères).',
          type: ToastType.error);
      return;
    }
    if (_shopAddressController.text.trim().length < 5) {
      AppToast.show(context,
          message: 'L\'adresse de la boutique est trop courte.',
          type: ToastType.error);
      return;
    }
    if (_descriptionController.text.trim().length < 10) {
      AppToast.show(context,
          message: 'La description est trop courte (min. 10 caractères).',
          type: ToastType.error);
      return;
    }
    if (_categoryIds.isEmpty) {
      AppToast.show(context,
          message: 'Choisissez au moins une catégorie pour votre boutique.',
          type: ToastType.error);
      return;
    }
    if (_idDocument == null || _selfie == null || _sampleProducts.isEmpty) {
      AppToast.show(context,
          message:
              'Merci de fournir la pièce d\'identité, le selfie et au moins une photo produit.',
          type: ToastType.error);
      return;
    }
    if (!_termsAccepted || !_fraudAccepted) {
      AppToast.show(context,
          message:
              'Merci d\'accepter les conditions d\'utilisation et la politique anti-fraude.',
          type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final idDocumentUrl = await _resolveUrl(_idDocument, 'documents');
      final selfieUrl = await _resolveUrl(_selfie, 'selfies');
      final sampleUrls = <String>[];
      for (final item in _sampleProducts) {
        sampleUrls.add(await _resolveUrl(item, 'products'));
      }

      final result = await NestAuthService.instance.submitVendorProfile(
        shopName: _shopNameController.text.trim(),
        shopAddress: _shopAddressController.text.trim(),
        categoryIds: _categoryIds,
        description: _descriptionController.text.trim(),
        idDocumentUrl: idDocumentUrl,
        selfieUrl: selfieUrl,
        sampleProductUrls: sampleUrls,
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
          _buildTextField(
            controller: _shopNameController,
            label: 'Nom de la boutique',
            hint: 'Ex : Chez Fatou Mode',
          ),
          const SizedBox(height: 14),
          _buildActivityDropdown(),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _shopAddressController,
            label: 'Adresse de la boutique',
            hint: 'Ex : Cotonou, quartier Fidjrossè',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _descriptionController,
            label: 'Description de la boutique',
            hint: 'Décrivez brièvement ce que vous vendez',
            maxLines: 4,
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
          const SizedBox(height: 14),
          _buildSampleProductsPicker(),
          const SizedBox(height: 20),
          _buildCheckbox(
            value: _termsAccepted,
            label: 'J\'accepte les conditions d\'utilisation',
            onChanged: (v) => setState(() => _termsAccepted = v),
          ),
          _buildCheckbox(
            value: _fraudAccepted,
            label: 'J\'accepte la politique anti-fraude',
            onChanged: (v) => setState(() => _fraudAccepted = v),
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
    int maxLines = 1,
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
          maxLines: maxLines,
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

  Widget _buildActivityDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catégories de la boutique (5 maximum)',
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        CategoryMultiSelect(
          selectedIds: _categoryIds,
          maxSelection: 5,
          onChanged: (ids) => setState(() => _categoryIds = ids),
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
                      : Image.file(
                          File((value as XFile).path),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ))
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

  Widget _buildSampleProductsPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos de produits exemples (max. 3)',
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ..._sampleProducts.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: item is String
                          ? CustomImageWidget(
                              imageUrl: item,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              semanticLabel: 'Photo produit',
                            )
                          : Image.file(
                              File((item as XFile).path),
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => _removeSampleProduct(index),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_sampleProducts.length < 3)
              GestureDetector(
                onTap: _pickSampleProduct,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.outline),
                  ),
                  child: const Icon(Icons.add_rounded, color: AppTheme.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckbox({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: AppTheme.primary,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
