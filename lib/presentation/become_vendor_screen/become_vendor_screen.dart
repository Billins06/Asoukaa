import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/category_multi_select.dart';
import '../../services/api_service.dart';
import '../../services/upload_service.dart';

/// Première demande vendeur pour un compte DÉJÀ connecté (client).
///
/// VendorReapplyScreen ne sert qu'à corriger une demande refusée, et le
/// formulaire d'inscription suppose un compte qui n'existe pas encore. Cet
/// écran comble le trou : un client existant devient vendeur sans recréer de
/// compte. Il envoie POST /api/v1/vendors/apply ; le compte reste « client »
/// jusqu'à l'approbation par l'équipe.
class BecomeVendorScreen extends StatefulWidget {
  const BecomeVendorScreen({super.key});

  @override
  State<BecomeVendorScreen> createState() => _BecomeVendorScreenState();
}

// Photo choisie : le fichier (pour l'upload) et ses octets (pour l'aperçu,
// qui doit fonctionner aussi sur le web).
class _Photo {
  final XFile file;
  final Uint8List bytes;
  const _Photo(this.file, this.bytes);
}

class _BecomeVendorScreenState extends State<BecomeVendorScreen> {
  bool _isSubmitting = false;

  final _shopNameController = TextEditingController();
  final _shopAddressController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<String> _categoryIds = [];

  _Photo? _idDocument;
  _Photo? _selfie;
  final List<_Photo> _sampleProducts = [];

  bool _termsAccepted = false;
  bool _fraudAccepted = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Choix des photos ──────────────────────────────────────────────────────

  Future<_Photo?> _prendrePhoto({required int quality, bool selfie = false}) async {
    final file = await PhotoPickerService.pick(
      context,
      imageQuality: quality,
      frontCamera: selfie,
    );
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return _Photo(file, bytes);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible de récupérer cette photo.',
          type: ToastType.error,
        );
      }
      return null;
    }
  }

  Future<void> _pickIdDocument() async {
    final photo = await _prendrePhoto(quality: 90);
    if (photo != null && mounted) setState(() => _idDocument = photo);
  }

  Future<void> _pickSelfie() async {
    final photo = await _prendrePhoto(quality: 90, selfie: true);
    if (photo != null && mounted) setState(() => _selfie = photo);
  }

  Future<void> _pickSampleProduct() async {
    if (_sampleProducts.length >= 3) return;
    final photo = await _prendrePhoto(quality: 85);
    if (photo != null && mounted) {
      setState(() => _sampleProducts.add(photo));
    }
  }

  void _removeSampleProduct(int index) {
    setState(() => _sampleProducts.removeAt(index));
  }

  // ── Envoi ─────────────────────────────────────────────────────────────────

  bool get _canSubmit =>
      _shopNameController.text.trim().length >= 3 &&
      _shopAddressController.text.trim().length >= 5 &&
      _descriptionController.text.trim().length >= 10 &&
      _categoryIds.isNotEmpty &&
      _idDocument != null &&
      _selfie != null &&
      _sampleProducts.isNotEmpty &&
      _termsAccepted &&
      _fraudAccepted;

  // Ce qui empêche encore l'envoi (affiché sous le formulaire).
  List<String> get _champsManquants => [
        if (_shopNameController.text.trim().length < 3) 'nom de la boutique',
        if (_categoryIds.isEmpty) 'catégorie',
        if (_shopAddressController.text.trim().length < 5) 'adresse',
        if (_descriptionController.text.trim().length < 10) 'description',
        if (_idDocument == null) 'pièce d\'identité',
        if (_selfie == null) 'selfie',
        if (_sampleProducts.isEmpty) 'photo d\'un produit',
        if (!_termsAccepted) 'conditions d\'utilisation',
        if (!_fraudAccepted) 'politique anti-fraude',
      ];

  String _messageErreur(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Délai dépassé. Vérifiez votre connexion internet.';
        case DioExceptionType.connectionError:
          return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
        default:
          break;
      }
      if (e.response?.statusCode == 409) {
        return 'Une demande existe déjà ou ce nom de boutique est pris.';
      }
    }
    return 'Erreur lors de l\'envoi du dossier. Réessayez.';
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
      final idDocumentUrl =
          await UploadService.instance.uploadFile(_idDocument!.file, 'documents');
      final selfieUrl =
          await UploadService.instance.uploadFile(_selfie!.file, 'selfies');
      final sampleUrls = <String>[];
      for (final item in _sampleProducts) {
        sampleUrls.add(await UploadService.instance.uploadFile(item.file, 'products'));
      }

      await ApiService.instance.client.post('/api/v1/vendors/apply', data: {
        'shopName': _shopNameController.text.trim(),
        'shopAddress': _shopAddressController.text.trim(),
        'categoryIds': _categoryIds,
        'description': _descriptionController.text.trim(),
        'idDocumentUrl': idDocumentUrl,
        'selfieUrl': selfieUrl,
        'sampleProductUrls': sampleUrls,
        'termsAccepted': true,
        'fraudPenaltiesAccepted': true,
      });

      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Demande envoyée ! Vous serez notifié par email.',
        type: ToastType.success,
        duration: const Duration(seconds: 5),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: _messageErreur(e),
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Construction ──────────────────────────────────────────────────────────

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
          'Devenir vendeur',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.storefront_rounded,
                      color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gardez votre compte actuel : il vous suffit de présenter '
                      'votre boutique. Notre équipe examine votre dossier puis '
                      'vous prévient par e-mail.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _shopNameController,
              label: 'Nom de la boutique',
              hint: 'Ex : Chez Fatou Mode',
            ),
            const SizedBox(height: 14),
            Text(
              'Catégories de la boutique (1 à 5)',
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
            if (!_canSubmit)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Il reste à compléter : ${_champsManquants.join(', ')}.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTheme.warning,
                  ),
                ),
              ),
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
                        'Envoyer ma demande',
                        style: GoogleFonts.outfit(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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
              borderSide: const BorderSide(color: AppTheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.outline),
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

  Widget _buildSinglePhotoPicker({
    required String label,
    required _Photo? value,
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
              child: value != null
                  ? Image.memory(
                      value.bytes,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    )
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
          'Photos de produits exemples (1 à 3)',
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
                      child: Image.memory(
                        item.bytes,
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
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
