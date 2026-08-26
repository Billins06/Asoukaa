import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../routes/app_routes.dart';

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
    super.dispose();
  }

  void _navigateToCart() {
    Navigator.pushNamed(context, AppRoutes.cart);
  }

  void _navigateToNotifications() {
    Navigator.pushNamed(context, AppRoutes.notifications);
  }

  Future<void> _pickImageForSearch() async {
    setState(() => _isImageSearching = true);
    try {
      final picker = ImagePicker();
      final source = await _showImageSourceDialog();
      if (source == null) {
        setState(() => _isImageSearching = false);
        return;
      }
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (image != null && mounted) {
        Navigator.pushNamed(
          context,
          AppRoutes.searchResults,
          arguments: {
            'imageSearch': true,
            'imagePath': image.path,
            'query': 'Recherche par image',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'accéder à la galerie')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImageSearching = false);
    }
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
                  child: const Icon(
                    Icons.favorite_border_rounded,
                    size: 24,
                    color: Color(0xFF1A1A1A),
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
                    children: [
                      const Icon(
                        Icons.notifications_outlined,
                        size: 24,
                        color: Color(0xFF1A1A1A),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6210),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
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
