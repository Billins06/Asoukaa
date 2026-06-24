import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../services/nest_auth_service.dart';

class HomeTrendingWidget extends StatefulWidget {
  final void Function(Map<String, dynamic>) onProductTap;
  final List<Map<String, dynamic>> products;
  final VoidCallback? onCartUpdated;

  const HomeTrendingWidget({
    super.key,
    required this.onProductTap,
    this.products = const [],
    this.onCartUpdated,
  });

  @override
  State<HomeTrendingWidget> createState() => _HomeTrendingWidgetState();
}

class _HomeTrendingWidgetState extends State<HomeTrendingWidget> {
  // Fallback mock products only shown when no real data available
  static final List<Map<String, dynamic>> _fallbackProducts = [
    {
      'id': 't1',
      'name': 'Boubou Brodé Homme Premium',
      'shop': 'Elegance Cotonou',
      'price': 45000,
      'originalPrice': 45000,
      'discount': 0,
      'rating': 4.9,
      'reviewCount': 567,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1aa6c2e6b-1773261630993.png',
      'semanticLabel':
          'Homme en boubou blanc brodé traditionnel avec broderies bleues debout sur fond neutre',
      'stockLeft': 45,
      'badge': 'Tendance',
    },
  ];

  List<Map<String, dynamic>> get _displayProducts {
    if (widget.products.isNotEmpty) {
      return widget.products.map((p) => _normalizeProduct(p)).toList();
    }
    return _fallbackProducts;
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    // Image : supporte liste d'objets {url}, liste de strings, ou string directe
    final images = p['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map) {
        imageUrl = first['url'] as String? ?? first['imageUrl'] as String? ?? '';
      } else if (first is String) {
        imageUrl = first;
      }
    } else if (images is String) {
      imageUrl = images;
    }
    if (imageUrl.isEmpty) {
      imageUrl = p['imageUrl'] as String? ?? p['image_url'] as String? ?? '';
    }
    if (imageUrl.isEmpty) {
      imageUrl = 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
    }

    // Shop : Supabase join = shops{}, NestJS = vendeur{shopName} ou shop{}
    final shopData = p['shops'] ?? p['vendeur'] ?? p['shop_info'];
    final shopName = shopData is Map
        ? (shopData['shopName'] as String? ??
            shopData['name'] as String? ??
            'Boutique')
        : (p['shop'] as String? ?? p['shopName'] as String? ?? 'Boutique');

    final price = (p['price'] as num? ?? 0).toInt();
    final originalPrice = (p['original_price'] as num? ??
            p['originalPrice'] as num? ??
            p['compareAtPrice'] as num? ??
            price)
        .toInt();
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : (p['discount'] as int? ?? 0);

    return {
      'id': p['id'] ?? '',
      'name': p['name'] ?? p['title'] ?? '',
      'shop': shopName,
      'price': price,
      'minPrice': p['min_price'] as int? ?? p['minPrice'] as int?,
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': (p['rating'] as num? ?? p['averageRating'] as num? ?? 4.5).toDouble(),
      'reviewCount': p['review_count'] as int? ?? p['reviewCount'] as int? ?? 0,
      'imageUrl': imageUrl,
      'semanticLabel': p['semanticLabel'] as String? ??
          'Produit ${p['name'] ?? p['title'] ?? ''} disponible sur Asoukaa',
      'stockLeft': p['stock_quantity'] as int? ??
          p['stockQuantity'] as int? ??
          p['stock'] as int? ??
          p['stockLeft'] as int? ??
          10,
      'badge': p['badge'] as String? ?? '',
      'soldCount': p['sold_count'] as int? ?? p['soldCount'] as int? ?? 0,
      'seller_id': p['seller_id'] ?? p['vendeurId'] ?? '',
      'shop_id': shopData is Map ? (shopData['id'] ?? '') : '',
    };
  }

  void _addToCart(BuildContext context, Map<String, dynamic> product) async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn();
    if (!context.mounted) return;
    if (!isLoggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    ScaffoldMessenger.of(context).clearSnackBars();
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
    widget.onCartUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final crossAxisCount = isTablet ? 3 : 2;
    final products = _displayProducts;

    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDE3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      size: 16,
                      color: Color(0xFFFF6210),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tendances',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.searchResults,
                  arguments: '',
                ),
                child: Text(
                  'Voir tout',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF6210),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (_, index) {
              final product = products[index];
              return _TrendingProductCard(
                product: product,
                onTap: () => widget.onProductTap(product),
                onAddToCart: () => _addToCart(context, product),
                animationDelay: Duration(milliseconds: index * 60),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendingProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final Duration animationDelay;

  const _TrendingProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    required this.animationDelay,
  });

  @override
  State<_TrendingProductCard> createState() => _TrendingProductCardState();
}

class _TrendingProductCardState extends State<_TrendingProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isInWishlist = false;
  bool _wishlistLoading = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    Future.delayed(
      widget.animationDelay,
      () => mounted ? _entranceController.forward() : null,
    );
    _checkWishlist();
  }

  Future<void> _checkWishlist() async {
    // Wishlist sera implémenté avec l'API NestJS
  }

  Future<void> _toggleWishlist() async {
    if (_wishlistLoading) return;
    setState(() => _wishlistLoading = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
        _isInWishlist = !_isInWishlist;
        _wishlistLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final minPrice = p['minPrice'] as int?;
    final price = p['price'] as int? ?? 0;
    final hasPriceRange = minPrice != null && minPrice < price;
    final discount = p['discount'] as int? ?? 0;
    final badge = p['badge'] as String? ?? '';

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
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
                    top: Radius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      Hero(
                        tag: 'product-${p['id']}',
                        child: CustomImageWidget(
                          imageUrl: p['imageUrl'] as String? ?? '',
                          width: double.infinity,
                          height: 140,
                          fit: BoxFit.cover,
                          semanticLabel: p['semanticLabel'] as String? ?? '',
                        ),
                      ),
                      if (discount > 0)
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
                      if (badge.isNotEmpty && discount == 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              badge,
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
                          onTap: _toggleWishlist,
                          behavior: HitTestBehavior.opaque,
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
                            child: _wishlistLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Color(0xFFDC2626),
                                    ),
                                  )
                                : Icon(
                                    _isInWishlist
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 14,
                                    color: _isInWishlist
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
                        p['name'] as String? ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p['shop'] as String? ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9E9E9E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${p['rating'] ?? 0}',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '(${p['reviewCount'] ?? 0})',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                        ],
                      ),
                      if ((p['soldCount'] as int? ?? 0) > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${p['soldCount']} vendus',
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasPriceRange
                                      ? '${_formatPrice(minPrice)}-${_formatPrice(price)} F'
                                      : '${_formatPrice(price)} FCFA',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFFF6210),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (discount > 0)
                                  Text(
                                    '${_formatPrice(p['originalPrice'] as int? ?? 0)} F',
                                    style: GoogleFonts.outfit(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF9E9E9E),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onAddToCart,
                            behavior: HitTestBehavior.opaque,
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
        ),
      ),
    );
  }
}
