import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../services/auth_service.dart';

class HomeFlashDealsWidget extends StatefulWidget {
  final void Function(Map<String, dynamic>) onProductTap;
  final List<Map<String, dynamic>> products;
  final VoidCallback? onCartUpdated;

  const HomeFlashDealsWidget({
    super.key,
    required this.onProductTap,
    this.products = const [],
    this.onCartUpdated,
  });

  @override
  State<HomeFlashDealsWidget> createState() => _HomeFlashDealsWidgetState();
}

class _HomeFlashDealsWidgetState extends State<HomeFlashDealsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _countdownController;
  int _secondsLeft = 5400;

  // Fallback mock products only shown when no real data available
  static final List<Map<String, dynamic>> _fallbackProducts = [
    {
      'id': 'fp1',
      'name': 'Tissu Wax Ankara 6 Yards',
      'shop': 'Maison Konaté Tissus',
      'price': 18500,
      'minPrice': 14000,
      'originalPrice': 32000,
      'discount': 42,
      'rating': 4.8,
      'reviewCount': 234,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1c0579dd1-1773189871928.png',
      'semanticLabel':
          'Tissu wax africain coloré avec motifs géométriques orange et bleu plié sur une table',
      'stockLeft': 7,
      'isHot': true,
    },
  ];

  List<Map<String, dynamic>> get _displayProducts {
    if (widget.products.isNotEmpty) {
      return widget.products.map((p) => _normalizeProduct(p)).toList();
    }
    return _fallbackProducts;
  }

  /// Normalize Supabase product to display format
  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    final images = p['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map) {
        imageUrl = first['url'] as String? ?? '';
      } else if (first is String) {
        imageUrl = first;
      }
    } else if (images is String) {
      imageUrl = images;
    }
    if (imageUrl.isEmpty) {
      imageUrl =
          'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
    }

    final shopData = p['shops'];
    final shopName = shopData is Map
        ? (shopData['name'] as String? ?? 'Boutique')
        : (p['shop'] as String? ?? 'Boutique');

    final price = (p['price'] as num? ?? 0).toInt();
    final originalPrice =
        (p['original_price'] as num? ?? p['originalPrice'] as num? ?? price)
            .toInt();
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : (p['discount'] as int? ?? 0);

    return {
      'id': p['id'] ?? '',
      'name': p['name'] ?? '',
      'shop': shopName,
      'price': price,
      'minPrice': p['min_price'] as int? ?? p['minPrice'] as int?,
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': (p['rating'] as num? ?? 4.5).toDouble(),
      'reviewCount': p['review_count'] as int? ?? p['reviewCount'] as int? ?? 0,
      'imageUrl': imageUrl,
      'semanticLabel':
          p['semanticLabel'] as String? ??
          'Produit ${p['name'] ?? ''} disponible sur Asoukaa',
      'stockLeft': p['stock_quantity'] as int? ?? p['stockLeft'] as int? ?? 10,
      'isHot': p['is_featured'] as bool? ?? p['isHot'] as bool? ?? false,
      'seller_id': p['seller_id'] ?? '',
      'shop_id': shopData is Map ? shopData['id'] ?? '' : '',
    };
  }

  @override
  void initState() {
    super.initState();
    _countdownController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            if (mounted) {
              setState(() {
                if (_secondsLeft > 0) _secondsLeft--;
              });
            }
          });
    _countdownController.repeat();
  }

  @override
  void dispose() {
    _countdownController.dispose();
    super.dispose();
  }

  String _formatTime() {
    final h = _secondsLeft ~/ 3600;
    final m = (_secondsLeft % 3600) ~/ 60;
    final s = _secondsLeft % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final products = _displayProducts;
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Ventes Flash',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatTime(),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
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
        if (isTablet)
          _buildTabletGrid(products)
        else
          _buildPhoneScroll(products),
      ],
    );
  }

  Widget _buildPhoneScroll(List<Map<String, dynamic>> products) {
    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: products.length,
        itemBuilder: (_, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 160,
              child: _FlashProductCard(
                product: products[index],
                onTap: () => widget.onProductTap(products[index]),
                onAddToCart: () => _addToCart(context, products[index]),
                animationDelay: Duration(milliseconds: index * 80),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabletGrid(List<Map<String, dynamic>> products) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (_, index) => _FlashProductCard(
          product: products[index],
          onTap: () => widget.onProductTap(products[index]),
          onAddToCart: () => _addToCart(context, products[index]),
          animationDelay: Duration(milliseconds: index * 80),
        ),
      ),
    );
  }

  void _addToCart(BuildContext context, Map<String, dynamic> product) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    final productId = product['id']?.toString() ?? '';
    if (productId.isEmpty) return;
    try {
      await Supabase.instance.client.from('cart_items').upsert({
        'user_id': user.id,
        'product_id': productId,
        'quantity': 1,
      }, onConflict: 'user_id,product_id');
      widget.onCartUpdated?.call();
    } catch (_) {}
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
  }
}

class _FlashProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final Duration animationDelay;

  const _FlashProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    required this.animationDelay,
  });

  @override
  State<_FlashProductCard> createState() => _FlashProductCardState();
}

class _FlashProductCardState extends State<_FlashProductCard>
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
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
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
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final productId = widget.product['id']?.toString() ?? '';
    if (productId.isEmpty) return;
    try {
      final result = await Supabase.instance.client
          .from('wishlists')
          .select('id')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .maybeSingle();
      if (mounted) setState(() => _isInWishlist = result != null);
    } catch (_) {}
  }

  Future<void> _toggleWishlist() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final productId = widget.product['id']?.toString() ?? '';
    if (productId.isEmpty || _wishlistLoading) return;
    setState(() => _wishlistLoading = true);
    try {
      if (_isInWishlist) {
        await Supabase.instance.client
            .from('wishlists')
            .delete()
            .eq('user_id', user.id)
            .eq('product_id', productId);
        if (mounted) setState(() => _isInWishlist = false);
      } else {
        final price = ((widget.product['price'] ?? 0) as num).toDouble();
        await Supabase.instance.client.from('wishlists').insert({
          'user_id': user.id,
          'product_id': productId,
          'added_price': price,
        });
        if (mounted) setState(() => _isInWishlist = true);
      }
    } catch (_) {}
    if (mounted) setState(() => _wishlistLoading = false);
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
                  color: Colors.black.withAlpha(18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                          height: 130,
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
                                fontSize: 11,
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
                      const SizedBox(height: 3),
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
