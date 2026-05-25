import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/storage_service.dart';
import '../../services/database_service.dart';
import '../../services/error_handler.dart';
import '../../services/auth_service.dart';

class PublierProduitScreen extends StatefulWidget {
  const PublierProduitScreen({super.key});

  @override
  State<PublierProduitScreen> createState() => _PublierProduitScreenState();
}

class _PublierProduitScreenState extends State<PublierProduitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _prixController = TextEditingController();
  final _stockController = TextEditingController();
  final _qteMinController = TextEditingController();
  final _lieuController = TextEditingController();
  final _marqueController = TextEditingController();

  // Real-time validation states
  String? _nomError;
  String? _prixError;
  String? _stockError;
  String? _lieuError;

  bool _nomValid = false;
  bool _prixValid = false;
  bool _stockValid = false;
  bool _lieuValid = false;
  bool _categoryValid = false;

  String? _selectedCategory;
  String? _selectedSize;
  String? _selectedColor;
  final List<String> _categories = [
    'Mode & Vêtements',
    'Électronique',
    'Alimentation',
    'Beauté & Cosmétiques',
    'Maison & Décoration',
    'Sport & Loisirs',
    'Artisanat',
    'Agriculture',
    'Autres',
  ];

  final List<String> _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Unique'];

  final List<String> _colorOptions = [
    'Noir',
    'Blanc',
    'Rouge',
    'Bleu',
    'Vert',
    'Jaune',
    'Orange',
    'Violet',
    'Rose',
    'Marron',
    'Gris',
    'Multicolore',
  ];

  // Image slots with real URLs from Supabase Storage
  final List<String?> _imageSlots = List.filled(8, null);
  final List<bool> _imageUploading = List.filled(8, false);
  // Mock video slots (up to 2)
  final List<String?> _videoSlots = List.filled(2, null);

  // Tiered pricing rows
  final List<Map<String, TextEditingController>> _tiers = [];

  bool _isSubmitting = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _addTier();
    _nomController.addListener(_validateNom);
    _prixController.addListener(_validatePrix);
    _stockController.addListener(_validateStock);
    _lieuController.addListener(_validateLieu);
  }

  // ── Real-time validators ──────────────────────────────────────────────────

  void _validateNom() {
    final v = _nomController.text;
    if (v.isEmpty) {
      setState(() {
        _nomError = null;
        _nomValid = false;
      });
    } else if (v.trim().length < 3) {
      setState(() {
        _nomError = 'Nom trop court (min. 3 caractères)';
        _nomValid = false;
      });
    } else if (v.trim().length > 100) {
      setState(() {
        _nomError = 'Nom trop long (max. 100 caractères)';
        _nomValid = false;
      });
    } else {
      setState(() {
        _nomError = null;
        _nomValid = true;
      });
    }
  }

  void _validatePrix() {
    final v = _prixController.text;
    if (v.isEmpty) {
      setState(() {
        _prixError = null;
        _prixValid = false;
      });
    } else {
      final price = int.tryParse(v);
      if (price == null || price <= 0) {
        setState(() {
          _prixError = 'Prix invalide (doit être > 0)';
          _prixValid = false;
        });
      } else if (price > 100000000) {
        setState(() {
          _prixError = 'Prix trop élevé';
          _prixValid = false;
        });
      } else {
        setState(() {
          _prixError = null;
          _prixValid = true;
        });
      }
    }
  }

  void _validateStock() {
    final v = _stockController.text;
    if (v.isEmpty) {
      setState(() {
        _stockError = null;
        _stockValid = false;
      });
    } else {
      final stock = int.tryParse(v);
      if (stock == null || stock < 0) {
        setState(() {
          _stockError = 'Stock invalide (doit être ≥ 0)';
          _stockValid = false;
        });
      } else {
        setState(() {
          _stockError = null;
          _stockValid = true;
        });
      }
    }
  }

  void _validateLieu() {
    final v = _lieuController.text;
    if (v.isEmpty) {
      setState(() {
        _lieuError = null;
        _lieuValid = false;
      });
    } else if (v.trim().length < 2) {
      setState(() {
        _lieuError = 'Lieu trop court';
        _lieuValid = false;
      });
    } else {
      setState(() {
        _lieuError = null;
        _lieuValid = true;
      });
    }
  }

  void _addTier() {
    if (_tiers.length < 5) {
      setState(() {
        _tiers.add({
          'qte': TextEditingController(),
          'prix': TextEditingController(),
        });
      });
    }
  }

  void _removeTier(int index) {
    setState(() {
      _tiers[index]['qte']!.dispose();
      _tiers[index]['prix']!.dispose();
      _tiers.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nomController.removeListener(_validateNom);
    _prixController.removeListener(_validatePrix);
    _stockController.removeListener(_validateStock);
    _lieuController.removeListener(_validateLieu);
    _nomController.dispose();
    _descriptionController.dispose();
    _prixController.dispose();
    _stockController.dispose();
    _qteMinController.dispose();
    _lieuController.dispose();
    _marqueController.dispose();
    for (final t in _tiers) {
      t['qte']!.dispose();
      t['prix']!.dispose();
    }
    super.dispose();
  }

  // ── Pick and upload image ─────────────────────────────────────────────────

  Future<void> _pickAndUploadImage(
    int index, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final image = await StorageService.instance.pickImage(source: source);
    if (image == null) return;

    setState(() => _imageUploading[index] = true);

    final url = await StorageService.instance.uploadProductImage(image);

    if (!mounted) return;
    setState(() {
      _imageUploading[index] = false;
      if (url != null) {
        _imageSlots[index] = url;
      } else {
        AppToast.show(
          context,
          message: 'Échec de l\'upload. Réessayez.',
          type: ToastType.error,
        );
      }
    });
  }

  void _showImageSourceDialog(int index) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(index, source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(index, source: ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _submitForm() async {
    _validateNom();
    _validatePrix();
    _validateStock();
    _validateLieu();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    // Get shop_id for the current seller
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() => _isSubmitting = false);
      AppToast.show(
        context,
        message: 'Vous devez être connecté.',
        type: ToastType.error,
      );
      return;
    }

    final shop = await DatabaseService.instance.getShopByOwnerId(user.id);
    if (shop == null) {
      setState(() => _isSubmitting = false);
      AppToast.show(
        context,
        message: 'Boutique introuvable. Créez d\'abord votre boutique.',
        type: ToastType.error,
      );
      return;
    }

    final images = _imageSlots.where((s) => s != null).map((s) => s!).toList();
    final priceTiers = _tiers
        .where((t) => t['qte']!.text.isNotEmpty && t['prix']!.text.isNotEmpty)
        .map(
          (t) => {
            'min_qty': int.tryParse(t['qte']!.text) ?? 0,
            'price': int.tryParse(t['prix']!.text) ?? 0,
          },
        )
        .toList();

    final result = await DatabaseService.instance.createProduct({
      'name': _nomController.text.trim(),
      'description': _descriptionController.text.trim(),
      'category': _selectedCategory ?? '',
      'price': int.tryParse(_prixController.text) ?? 0,
      'original_price': int.tryParse(_prixController.text) ?? 0,
      'stock_quantity': int.tryParse(_stockController.text) ?? 0,
      'images': images,
      'price_tiers': priceTiers,
      'shop_id': shop['id'] as String,
      'seller_id': user.id,
      'is_active': true,
      'tags': [
        if (_marqueController.text.trim().isNotEmpty)
          _marqueController.text.trim(),
        if (_selectedSize != null) _selectedSize!,
        if (_selectedColor != null) _selectedColor!,
        if (_lieuController.text.trim().isNotEmpty) _lieuController.text.trim(),
      ],
    });

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isSuccess) {
      setState(() => _isSuccess = true);
      AppToast.show(
        context,
        message: 'Produit publié avec succès ! Il sera visible sous peu.',
        type: ToastType.success,
        actionLabel: 'OK',
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.pop(context);
      });
    } else {
      ErrorHandler.showErrorDialog(
        context,
        message: result.errorMessage ?? 'Erreur lors de la publication.',
        onRetry: _submitForm,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMediaSection(),
            const SizedBox(height: 20),
            _buildInfoSection(),
            const SizedBox(height: 20),
            _buildSpecificationsSection(),
            const SizedBox(height: 20),
            _buildPricingSection(),
            const SizedBox(height: 20),
            _buildTieredPricingSection(),
            const SizedBox(height: 20),
            _buildStockSection(),
            const SizedBox(height: 20),
            _buildLocationSection(),
            const SizedBox(height: 28),
            _buildSubmitButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Publier un produit',
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.outlineVariant),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppTheme.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildValidatedFormField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    String? errorText,
    bool isValid = false,
    int maxLines = 1,
    String? suffixText,
    bool alignLabelWithHint = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final showError = errorText != null && controller.text.isNotEmpty;
    final showSuccess = isValid && !showError;

    Color borderColor() {
      if (showError) return const Color(0xFFDC2626);
      if (showSuccess) return const Color(0xFF16A34A);
      return AppTheme.outline;
    }

    Color fillColor() {
      if (showError) return const Color(0xFFFEF2F2);
      if (showSuccess) return const Color(0xFFF0FDF4);
      return AppTheme.surface;
    }

    Color iconColor() {
      if (showError) return const Color(0xFFDC2626);
      if (showSuccess) return const Color(0xFF16A34A);
      return AppTheme.muted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          validator: validator,
          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            alignLabelWithHint: alignLabelWithHint,
            suffixText: suffixText,
            prefixIcon: Icon(prefixIcon, size: 20, color: iconColor()),
            suffixIcon: showSuccess
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Color(0xFF16A34A),
                  )
                : showError
                ? const Icon(
                    Icons.error_rounded,
                    size: 20,
                    color: Color(0xFFDC2626),
                  )
                : null,
            filled: true,
            fillColor: fillColor(),
            labelStyle: GoogleFonts.outfit(fontSize: 14, color: iconColor()),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor()),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: borderColor(),
                width: showSuccess ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showError
                    ? const Color(0xFFDC2626)
                    : showSuccess
                    ? const Color(0xFF16A34A)
                    : AppTheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
            ),
            errorStyle: GoogleFonts.outfit(
              fontSize: 11,
              color: const Color(0xFFDC2626),
            ),
          ),
        ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: const Color(0xFFDC2626),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (showSuccess)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 13,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 4),
                Text(
                  'Valide ✓',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── MEDIA SECTION ──────────────────────────────────────────────────────────

  Widget _buildMediaSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Photos & Vidéos',
            'Jusqu\'à 8 photos et 2 vidéos',
          ),
          const SizedBox(height: 14),
          Text(
            'Photos (${_imageSlots.where((s) => s != null).length}/8)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 8,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _buildImageSlot(i),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Vidéos (${_videoSlots.where((s) => s != null).length}/2)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildVideoSlot(0),
              const SizedBox(width: 10),
              _buildVideoSlot(1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageSlot(int index) {
    final hasImage = _imageSlots[index] != null;
    final isUploading = _imageUploading[index];

    return GestureDetector(
      onTap: isUploading ? null : () => _showImageSourceDialog(index),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? AppTheme.primary.withAlpha(80) : AppTheme.outline,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: isUploading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                  ),
                ),
              )
            : hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      _imageSlots[index]!,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      semanticLabel: 'Image produit ${index + 1}',
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _imageSlots[index] = null),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Principale',
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    index == 0
                        ? Icons.add_photo_alternate_outlined
                        : Icons.add_rounded,
                    color: AppTheme.muted,
                    size: index == 0 ? 26 : 22,
                  ),
                  if (index == 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Principale',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildVideoSlot(int index) {
    final hasVideo = _videoSlots[index] != null;
    return GestureDetector(
      onTap: () {
        setState(() {
          _videoSlots[index] = 'video_${index + 1}.mp4';
        });
      },
      child: Container(
        width: 120,
        height: 72,
        decoration: BoxDecoration(
          color: hasVideo ? AppTheme.primaryMuted : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVideo ? AppTheme.primary.withAlpha(80) : AppTheme.outline,
            width: hasVideo ? 2 : 1,
          ),
        ),
        child: hasVideo
            ? Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    color: AppTheme.primary,
                    size: 28,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _videoSlots[index] = null),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'Vidéo ${index + 1}',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.video_call_outlined,
                    color: AppTheme.muted,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vidéo ${index + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── INFO SECTION ───────────────────────────────────────────────────────────

  Widget _buildInfoSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Informations produit',
            'Nom, description et catégorie',
          ),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _nomController,
            label: 'Nom du produit *',
            hintText: 'Ex: Tissu Wax Ankara 6 yards',
            prefixIcon: Icons.inventory_2_outlined,
            errorText: _nomError,
            isValid: _nomValid,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Champ requis';
              if (v.trim().length < 3) {
                return 'Nom trop court (min. 3 caractères)';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _buildCategoryDropdown(),
          const SizedBox(height: 14),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Décrivez votre produit en détail...',
              prefixIcon: const Icon(Icons.description_outlined, size: 20),
              alignLabelWithHint: true,
              labelStyle: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    final showCategoryError = !_categoryValid && _selectedCategory == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: InputDecoration(
            labelText: 'Catégorie *',
            prefixIcon: Icon(
              Icons.category_outlined,
              size: 20,
              color: showCategoryError
                  ? const Color(0xFFDC2626)
                  : AppTheme.muted,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            labelStyle: GoogleFonts.outfit(fontSize: 14, color: AppTheme.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showCategoryError
                    ? const Color(0xFFDC2626)
                    : AppTheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
          ),
          hint: Text(
            'Sélectionner une catégorie',
            style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.muted),
          ),
          items: _categories
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: GoogleFonts.outfit(fontSize: 14)),
                ),
              )
              .toList(),
          onChanged: (val) {
            setState(() {
              _selectedCategory = val;
              _categoryValid = val != null;
            });
          },
          validator: (v) => v == null ? 'Catégorie requise' : null,
        ),
      ],
    );
  }

  // ── SPECIFICATIONS SECTION ─────────────────────────────────────────────────

  Widget _buildSpecificationsSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Spécificités', 'Marque, taille, couleur'),
          const SizedBox(height: 16),
          // Marque
          TextFormField(
            controller: _marqueController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Marque (optionnel)',
              hintText: 'Ex: Samsung, Artisanal...',
              prefixIcon: const Icon(
                Icons.branding_watermark_outlined,
                size: 20,
              ),
              labelStyle: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Taille
          Text(
            'Taille (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sizes.map((size) {
              final isSelected = _selectedSize == size;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedSize = isSelected ? null : size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryMuted
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    size,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // Couleur
          Text(
            'Couleur (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colorOptions.map((color) {
              final isSelected = _selectedColor == color;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedColor = isSelected ? null : color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryMuted
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    color,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PRICING SECTION ────────────────────────────────────────────────────────

  Widget _buildPricingSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Prix', 'Prix unitaire en FCFA'),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _prixController,
            label: 'Prix unitaire *',
            hintText: 'Ex: 5000',
            prefixIcon: Icons.sell_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            suffixText: 'FCFA',
            errorText: _prixError,
            isValid: _prixValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Prix requis';
              final price = int.tryParse(v);
              if (price == null || price <= 0) return 'Prix invalide';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _buildValidatedFormField(
            controller: _qteMinController,
            label: 'Quantité minimum de commande',
            hintText: 'Ex: 1',
            prefixIcon: Icons.shopping_basket_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ),
    );
  }

  // ── TIERED PRICING SECTION ─────────────────────────────────────────────────

  Widget _buildTieredPricingSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Prix dégressifs',
            'Optionnel — réductions par quantité',
          ),
          const SizedBox(height: 14),
          ..._tiers.asMap().entries.map((e) => _buildTierRow(e.key)),
          if (_tiers.length < 5)
            TextButton.icon(
              onPressed: _addTier,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Ajouter un palier',
                style: GoogleFonts.outfit(fontSize: 13),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildTierRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _tiers[index]['qte'],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Qté min',
                prefixIcon: const Icon(Icons.format_list_numbered, size: 18),
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.outfit(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _tiers[index]['prix'],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Prix FCFA',
                prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.outfit(fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          if (_tiers.length > 1)
            IconButton(
              onPressed: () => _removeTier(index),
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Color(0xFFDC2626),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  // ── STOCK SECTION ──────────────────────────────────────────────────────────

  Widget _buildStockSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Stock', 'Quantité disponible'),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _stockController,
            label: 'Quantité en stock *',
            hintText: 'Ex: 50',
            prefixIcon: Icons.warehouse_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            errorText: _stockError,
            isValid: _stockValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Stock requis';
              final stock = int.tryParse(v);
              if (stock == null || stock < 0) return 'Stock invalide';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── LOCATION SECTION ───────────────────────────────────────────────────────

  Widget _buildLocationSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Localisation', 'Lieu de vente ou d\'expédition'),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _lieuController,
            label: 'Lieu *',
            hintText: 'Ex: Dakar, Sénégal',
            prefixIcon: Icons.location_on_outlined,
            textCapitalization: TextCapitalization.words,
            errorText: _lieuError,
            isValid: _lieuValid,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requis';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── SUBMIT BUTTON ──────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: _isSuccess
              ? const LinearGradient(
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : const LinearGradient(
                  colors: [AppTheme.primary, Color(0xFFFF8C42)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (_isSuccess ? const Color(0xFF16A34A) : AppTheme.primary)
                  .withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: (_isSubmitting || _isSuccess) ? null : _submitForm,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : _isSuccess
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Produit publié !',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.rocket_launch_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Publier le produit',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
