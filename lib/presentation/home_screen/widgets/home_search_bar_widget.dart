import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/photo_picker_service.dart';

import 'dart:async';
import 'dart:typed_data';

import '../../../routes/app_routes.dart';
import '../../../services/api_service.dart';
import '../../../services/wishlist_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';

class HomeSearchBarWidget extends StatefulWidget {
  final bool isSearchOpen;
  final int cartCount;
  final bool isScrolled;
  final VoidCallback onSearchToggle;

  const HomeSearchBarWidget({
    super.key,
    required this.isSearchOpen,
    required this.cartCount,
    required this.isScrolled,
    required this.onSearchToggle,
  });

  @override
  State<HomeSearchBarWidget> createState() => _HomeSearchBarWidgetState();
}

class _HomeSearchBarWidgetState extends State<HomeSearchBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _searchAnimController;
  late Animation<double> _searchWidthAnim;
  late Animation<double> _searchOpacityAnim;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isImageSearching = false;
  int _unreadNotifCount = 0;
  Timer? _unreadPollTimer;

  @override
  void initState() {
    super.initState();
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _searchWidthAnim = CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOutCubic,
    );
    _searchOpacityAnim = CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOut,
    );
    _searchController.addListener(() => setState(() {}));
    _fetchUnreadCount();
    _unreadPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchUnreadCount(),
    );
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final res = await ApiService.instance.client
          .get('/api/v1/notifications/unread-count');
      final count = res.data is Map ? res.data['unreadCount'] as int? : null;
      if (mounted) setState(() => _unreadNotifCount = count ?? 0);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(HomeSearchBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSearchOpen != oldWidget.isSearchOpen) {
      if (widget.isSearchOpen) {
        _searchAnimController.forward();
        Future.delayed(
          const Duration(milliseconds: 100),
          () => _searchFocusNode.requestFocus(),
        );
      } else {
        _searchAnimController.reverse();
        _searchFocusNode.unfocus();
        _searchController.clear();
      }
    }
  }

  @override
  void dispose() {
    _searchAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _unreadPollTimer?.cancel();
    super.dispose();
  }

  void _navigateToCart() {
    Navigator.pushNamed(context, AppRoutes.cart);
  }

  void _navigateToNotifications() async {
    await Navigator.pushNamed(context, AppRoutes.notifications);
    _fetchUnreadCount();
  }

  /// Import d'une image (galerie ou appareil photo) depuis la barre de
  /// recherche. La vraie recherche visuelle n'existe pas encore côté backend :
  /// on affiche l'image importée et on propose de la décrire en texte, ce qui
  /// relance la recherche texte classique (même route que la barre).
  /// Quand la recherche par image sera prête, l'[XFile] choisi ci-dessous est
  /// le point de branchement (envoi au backend au lieu de la feuille).
  Future<void> _pickImageForSearch() async {
    if (_isImageSearching) return;
    final source = await _showImageSourceDialog();
    if (source == null || !mounted) return; // feuille fermée : rien à faire

    final bool fromCamera = source == ImageSource.camera;
    setState(() => _isImageSearching = true);
    XFile? image;
    Uint8List? bytes;
    try {
      image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 80,
      );
      // readAsBytes fonctionne sur mobile comme sur le web (pas de dart:io).
      if (image != null) bytes = await image.readAsBytes();
    } on PlatformException catch (e) {
      if (mounted) {
        final denied = e.code == 'camera_access_denied' ||
            e.code == 'photo_access_denied';
        AppToast.show(
          context,
          message: denied
              ? (fromCamera
                  ? 'Accès à l\'appareil photo refusé. Autorisez-le dans les réglages du téléphone.'
                  : 'Accès aux photos refusé. Autorisez-le dans les réglages du téléphone.')
              : (fromCamera
                  ? 'Impossible d\'ouvrir l\'appareil photo.'
                  : 'Impossible d\'accéder à la galerie.'),
          type: ToastType.error,
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible d\'importer cette image. Réessayez.',
          type: ToastType.error,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isImageSearching = false);
    }

    // Sélection annulée par l'utilisateur : on ne fait rien.
    if (image == null || bytes == null || !mounted) return;
    final Uint8List pickedBytes = bytes;

    final query = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ImageSearchSheet(imageBytes: pickedBytes),
    );
    if (query == null || query.trim().isEmpty || !mounted) return;

    // Même navigation que la barre de recherche texte.
    Navigator.pushNamed(
      context,
      AppRoutes.searchResults,
      arguments: query.trim(),
    );
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recherche par image',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Prenez une photo ou choisissez depuis la galerie',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 20),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6210).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFFFF6210),
                  size: 22,
                ),
              ),
              title: Text(
                'Prendre une photo',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Utiliser l\'appareil photo',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF3B82F6),
                  size: 22,
                ),
              ),
              title: Text(
                'Choisir depuis la galerie',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Sélectionner une image existante',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: widget.isScrolled
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: widget.isSearchOpen
                  ? SizeTransition(
                      key: const ValueKey('search_open'),
                      sizeFactor: _searchWidthAnim,
                      axis: Axis.horizontal,
                      child: FadeTransition(
                        opacity: _searchOpacityAnim,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: widget.onSearchToggle,
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                size: 24,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('search_closed')),
            ),
            if (!widget.isSearchOpen) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'A',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Asoukaa',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
            ],
            if (widget.isSearchOpen) ...[
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F2EF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF9E9E9E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF1A1A1A),
                          ),
                          onSubmitted: (query) {
                            if (query.trim().isNotEmpty) {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.searchResults,
                                arguments: query,
                              );
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Rechercher des produits...',
                            hintStyle: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF9E9E9E),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF9E9E9E),
                          ),
                          onPressed: () => _searchController.clear(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        )
                      else
                        // Image search button
                        _isImageSearching
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFF6210),
                                  ),
                                ),
                              )
                            : Tooltip(
                                message: 'Recherche par image',
                                child: InkWell(
                                  onTap: _pickImageForSearch,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFF6210,
                                        ).withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.image_search_rounded,
                                        size: 18,
                                        color: Color(0xFFFF6210),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              InkWell(
                onTap: widget.onSearchToggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: const Icon(
                    Icons.search_rounded,
                    size: 24,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.wishlist),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: ValueListenableBuilder<int>(
                    // Écoute directement le compteur partagé : le badge se
                    // met à jour à l'instant même où un produit est
                    // ajouté/retiré ailleurs dans l'app (fiche produit,
                    // listings...), sans attendre un rechargement de cet
                    // écran ou un retour au premier plan.
                    valueListenable: WishlistService.instance.countNotifier,
                    builder: (context, wishlistCount, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.favorite_border_rounded,
                          size: 24,
                          color: Color(0xFF1A1A1A),
                        ),
                        if (wishlistCount > 0)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6210),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                '$wishlistCount',
                                style: GoogleFonts.outfit(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _navigateToNotifications,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_outlined,
                        size: 24,
                        color: Color(0xFF1A1A1A),
                      ),
                      if (_unreadNotifCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(
                              minWidth: 15,
                              minHeight: 15,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6210),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Center(
                              child: Text(
                                _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _navigateToCart,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.shopping_cart_outlined,
                        size: 24,
                        color: Color(0xFF1A1A1A),
                      ),
                      if (widget.cartCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6210),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '${widget.cartCount}',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Feuille affichée après l'import d'une image : aperçu + message honnête
/// (recherche visuelle bientôt disponible) + champ texte pré-focalisé.
/// Renvoie (via Navigator.pop) le texte saisi, ou null si fermée.
class _ImageSearchSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const _ImageSearchSheet({required this.imageBytes});

  @override
  State<_ImageSearchSheet> createState() => _ImageSearchSheetState();
}

class _ImageSearchSheetState extends State<_ImageSearchSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    Navigator.pop(context, q);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Image importée',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 180,
                  color: AppTheme.background,
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'La recherche par image arrive bientôt. En attendant, décrivez ce que vous cherchez :',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Ex. : robe en wax, sac en cuir noir...',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    color: AppTheme.muted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                  filled: true,
                  fillColor: AppTheme.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: value.text.trim().isEmpty ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.outline,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Rechercher',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
