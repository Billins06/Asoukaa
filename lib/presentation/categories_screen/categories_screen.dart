import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/custom_image_widget.dart';
import '../../routes/app_routes.dart';
import '../../services/product_service.dart';
import '../../services/nest_auth_service.dart';

class CategoriesScreen extends StatefulWidget {
  final String? initialCategory;
  const CategoriesScreen({super.key, this.initialCategory});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  int _currentNavIndex = 1;
  late String _selectedCategory;
  bool _isLoading = true;
  List<Map<String, dynamic>> _products = [];

  static const List<_CategoryItem> _categories = [
    _CategoryItem(
      label: 'Tous',
      icon: Icons.apps_rounded,
      color: Color(0xFFFF6210),
      dbValue: null,
    ),
    _CategoryItem(
      label: 'Mode',
      icon: Icons.checkroom_outlined,
      color: Color(0xFF8B5CF6),
      dbValue: 'Mode & Vêtements',
    ),
    _CategoryItem(
      label: 'Électronique',
      icon: Icons.devices_outlined,
      color: Color(0xFF3B82F6),
      dbValue: 'Électronique',
    ),
    _CategoryItem(
      label: 'Alimentaire',
      icon: Icons.restaurant_outlined,
      color: Color(0xFF10B981),
      dbValue: 'Alimentation',
    ),
    _CategoryItem(
      label: 'Beauté',
      icon: Icons.spa_outlined,
      color: Color(0xFFEC4899),
      dbValue: 'Beauté & Cosmétiques',
    ),
    _CategoryItem(
      label: 'Auto',
      icon: Icons.directions_car_outlined,
      color: Color(0xFFF59E0B),
      dbValue: 'Auto',
    ),
    _CategoryItem(
      label: 'Maison',
      icon: Icons.home_outlined,
      color: Color(0xFF06B6D4),
      dbValue: 'Maison & Décoration',
    ),
    _CategoryItem(
      label: 'Sports',
      icon: Icons.sports_basketball_outlined,
      color: Color(0xFFDC2626),
      dbValue: 'Sport & Loisirs',
    ),
    _CategoryItem(
      label: 'Santé',
      icon: Icons.local_hospital_outlined,
      color: Color(0xFF059669),
      dbValue: 'Santé',
    ),
    _CategoryItem(
      label: 'Livres',
      icon: Icons.menu_book_outlined,
      color: Color(0xFF7C3AED),
      dbValue: 'Livres',
    ),
    _CategoryItem(
      label: 'Jouets',
      icon: Icons.toys_outlined,
      color: Color(0xFFD97706),
      dbValue: 'Jouets & Enfants',
    ),
    _CategoryItem(
      label: 'Bijoux',
      icon: Icons.diamond_outlined,
      color: Color(0xFFDB2777),
      dbValue: 'Bijoux',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Tous';
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final selectedItem = _categories.firstWhere(
        (c) => c.label == _selectedCategory,
        orElse: () => _categories.first,
      );
      final result = await ProductService.instance.getProducts(limit: 100);
      if (mounted) {
        List<Map<String, dynamic>> products = result.data ?? [];
        if (selectedItem.dbValue != null) {
          products = products.where((p) {
            final cat = p['category'];
            if (cat is Map) return cat['name'] == selectedItem.dbValue;
            return cat?.toString() == selectedItem.dbValue;
          }).toList();
        }
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectCategory(String cat) {
    if (_selectedCategory == cat) return;
    setState(() => _selectedCategory = cat);
    _loadProducts();
  }

  Future<void> _navigateToProfile() async {
    final loggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!mounted) return;
    if (!loggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
    } else {
      Navigator.pushNamed(context, AppRoutes.buyerProfile);
    }
  }

  String _formatPrice(dynamic price) {
    final p = (price as num?)?.toInt() ?? 0;
    final s = p.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Catégories',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Color(0xFF1A1A1A)),
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.searchResults,
              arguments: '',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryGrid(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  _selectedCategory == 'Tous'
                      ? 'Tous les produits'
                      : 'Produits — $_selectedCategory',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                if (!_isLoading)
                  Text(
                    '${_products.length} résultats',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.muted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6210)),
                  )
                : _products.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _loadProducts,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: _products.length,
                      itemBuilder: (_, i) => _ProductCard(
                        product: _products[i],
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.productDetail,
                          arguments: _products[i],
                        ),
                        onAddToCart: () => _addToCart(_products[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: AsoukaaBottomNav(
        currentIndex: _currentNavIndex,
        onTap: (i) {
          setState(() => _currentNavIndex = i);
          switch (i) {
            case 0:
              Navigator.pushReplacementNamed(context, AppRoutes.home);
              break;
            case 1:
              break;
            case 2:
              Navigator.pushNamed(context, AppRoutes.chat);
              break;
            case 3:
              Navigator.pushNamed(context, AppRoutes.cart);
              break;
            case 4:
              _navigateToProfile();
              break;
          }
        },
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final isSelected = _selectedCategory == cat.label;
          return GestureDetector(
            onTap: () => _selectCategory(cat.label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected
                    ? cat.color.withAlpha(25)
                    : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? cat.color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? cat.color : cat.color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      cat.icon,
                      size: 18,
                      color: isSelected ? Colors.white : cat.color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    cat.label,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected ? cat.color : AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppTheme.muted),
          const SizedBox(height: 12),
          Text(
            'Aucun produit dans cette catégorie',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _selectCategory('Tous'),
            child: Text(
              'Voir tous les produits',
              style: GoogleFonts.outfit(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addToCart(Map<String, dynamic> product) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} ajouté au panier'),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Voir panier',
          textColor: const Color(0xFFFF6210),
          onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
        ),
      ),
    );
  }
}

class _CategoryItem {
  final String label;
  final IconData icon;
  final Color color;
  final String? dbValue;
  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.color,
    this.dbValue,
  });
}

class _ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _isFav = false;

  String _formatPrice(dynamic price) {
    final p = (price as num?)?.toInt() ?? 0;
    final s = p.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _getImageUrl(Map<String, dynamic> p) {
    final images = p['images'];
    if (images is List && images.isNotEmpty) return images.first.toString();
    if (p['image_url'] != null) return p['image_url'].toString();
    return 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final originalPrice = (p['original_price'] as num?)?.toInt() ?? price;
    final hasDiscount = originalPrice > price;
    final discount = hasDiscount
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;
    final soldCount = (p['sold_count'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Stack(
                children: [
                  CustomImageWidget(
                    imageUrl: _getImageUrl(p),
                    width: double.infinity,
                    height: 130,
                    fit: BoxFit.cover,
                    semanticLabel: p['name']?.toString() ?? 'Produit',
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '-$discount%',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() => _isFav = !_isFav),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 14,
                          color: _isFav
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p['name']?.toString() ?? 'Produit',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (soldCount > 0)
                    Text(
                      '$soldCount vendus à Cotonou',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatPrice(price)} FCFA',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFF6210),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasDiscount)
                              Text(
                                '${_formatPrice(originalPrice)} F',
                                style: GoogleFonts.outfit(
                                  fontSize: 9,
                                  color: const Color(0xFF9E9E9E),
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onAddToCart,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6210),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
