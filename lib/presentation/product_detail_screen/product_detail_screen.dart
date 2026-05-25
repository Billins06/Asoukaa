import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import './widgets/product_action_bar_widget.dart';
import './widgets/product_gallery_widget.dart';
import './widgets/product_info_widget.dart';
import './widgets/product_price_tiers_widget.dart';
import './widgets/product_seller_card_widget.dart';
import './widgets/product_tabs_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../routes/app_routes.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? productData;

  const ProductDetailScreen({super.key, this.productData});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  // TODO: Replace with [Riverpod/Bloc] for production
  int _quantity = 1;
  bool _isFavorite = false;
  bool _isInWishlist = false;
  bool _isWishlistLoading = false;
  int _cartCount = 3;
  bool _isLoading = true;

  late Map<String, dynamic> _product;

  @override
  void initState() {
    super.initState();
    // Set system UI overlay style once, not on every build frame
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      );
    }
    _product = widget.productData ?? {};
    // Track product view
    if (_product.isNotEmpty) {
      AnalyticsService.instance.trackProductView(
        productId: (_product['id'] ?? '').toString(),
        productName: (_product['name'] ?? '').toString(),
        shopId: (_product['shopId'] ?? _product['shop_id'] ?? '').toString(),
      );
    }
    _checkWishlistStatus();
    // Load full product data from Supabase if we have an id
    _loadFullProduct();
  }

  Future<void> _loadFullProduct() async {
    final productId = (_product['id'] ?? '').toString();
    if (productId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final result = await Supabase.instance.client
          .from('products')
          .select(
            '*, shops(id, name, logo_url, rating, is_verified, owner_id), reviews(rating, comment, created_at, reviewer_id, user_profiles(full_name, avatar_url))',
          )
          .eq('id', productId)
          .maybeSingle();
      if (result != null && mounted) {
        final normalized = _normalizeSupabaseProduct(result);
        setState(() {
          _product = normalized;
          _isLoading = false;
        });
        _checkWishlistStatus();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _normalizeSupabaseProduct(Map<String, dynamic> p) {
    final shopData = p['shops'] as Map<String, dynamic>?;
    final images = p['images'];
    List<Map<String, dynamic>> imageList = [];
    if (images is List) {
      for (final img in images) {
        if (img is Map) {
          imageList.add({
            'url': img['url'] ?? '',
            'semanticLabel': img['semanticLabel'] ?? 'Image du produit',
          });
        } else if (img is String) {
          imageList.add({'url': img, 'semanticLabel': 'Image du produit'});
        }
      }
    }
    if (imageList.isEmpty) {
      imageList = [
        {
          'url':
              'https://img.rocket.new/generatedImages/rocket_gen_img_1400468a7-1773808571322.png',
          'semanticLabel': 'Image du produit',
        },
      ];
    }

    final price = (p['price'] as num? ?? 0).toInt();
    final originalPrice = (p['original_price'] as num? ?? price).toInt();
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;

    final specs = p['specs'];
    List<Map<String, dynamic>> specList = [];
    if (specs is List) {
      for (final s in specs) {
        if (s is Map) specList.add(Map<String, dynamic>.from(s));
      }
    }

    final priceTiers = p['price_tiers'] ?? p['priceTiers'];
    List<Map<String, dynamic>> tierList = [];
    if (priceTiers is List) {
      for (final t in priceTiers) {
        if (t is Map) tierList.add(Map<String, dynamic>.from(t));
      }
    }

    return {
      'id': p['id'] ?? '',
      'name': p['name'] ?? '',
      'shop': shopData?['name'] ?? '',
      'shopId': shopData?['id'] ?? '',
      'shop_id': shopData?['id'] ?? '',
      'shopLogo': shopData?['logo_url'] ?? '',
      'shopLogoSemanticLabel': 'Logo de la boutique ${shopData?['name'] ?? ''}',
      'shopRating': (shopData?['rating'] as num? ?? 4.5).toDouble(),
      'shopSales': 0,
      'shopIsOnline': true,
      'shopIsVerified': shopData?['is_verified'] as bool? ?? false,
      'seller_id': shopData?['owner_id'] ?? p['seller_id'] ?? '',
      'price': price,
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': (p['rating'] as num? ?? 4.5).toDouble(),
      'reviewCount': p['review_count'] as int? ?? 0,
      'imageUrl': imageList.first['url'] ?? '',
      'semanticLabel': imageList.first['semanticLabel'] ?? '',
      'images': imageList,
      'stockLeft': p['stock_quantity'] as int? ?? 0,
      'isHot': p['is_featured'] as bool? ?? false,
      'category': p['category'] ?? '',
      'location': p['location'] ?? 'Bénin',
      'minOrder': p['min_order'] as int? ?? 1,
      'description': p['description'] ?? '',
      'priceTiers': tierList,
      'specs': specList,
      'reviews': p['reviews'] ?? [],
    };
  }

  Future<void> _checkWishlistStatus() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final productId = (_product['id'] ?? '').toString();
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
    if (user == null) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    final productId = (_product['id'] ?? '').toString();
    if (productId.isEmpty) return;
    setState(() => _isWishlistLoading = true);
    try {
      if (_isInWishlist) {
        await Supabase.instance.client
            .from('wishlists')
            .delete()
            .eq('user_id', user.id)
            .eq('product_id', productId);
        if (mounted) {
          setState(() {
            _isInWishlist = false;
            _isWishlistLoading = false;
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Retiré de la liste de souhaits',
                style: GoogleFonts.outfit(),
              ),
              backgroundColor: AppTheme.textSecondary,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        final price = ((_product['price'] ?? 0) as num).toDouble();
        await Supabase.instance.client.from('wishlists').insert({
          'user_id': user.id,
          'product_id': productId,
          'added_price': price,
        });
        if (mounted) {
          setState(() {
            _isInWishlist = true;
            _isWishlistLoading = false;
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ajouté à la liste de souhaits',
                      style: GoogleFonts.outfit(),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.pushNamed(context, AppRoutes.wishlist);
                    },
                    child: Text(
                      'Voir',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isWishlistLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      body: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
    );
  }

  Widget _buildPhoneLayout() {
    if (_isLoading) {
      return SafeArea(
        child: Stack(
          children: [
            const ProductDetailSkeleton(),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 18),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: ProductGalleryWidget(
                product: _product,
                isFavorite: _isFavorite,
                onFavoriteTap: () => setState(() => _isFavorite = !_isFavorite),
                onBackTap: () => Navigator.pop(context),
                cartCount: _cartCount,
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFFF5F2EF)),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    ProductInfoWidget(product: _product),
                    const SizedBox(height: 8),
                    ProductPriceTiersWidget(
                      priceTiers:
                          (_product['priceTiers'] as List<dynamic>?)
                              ?.cast<Map<String, dynamic>>() ??
                          [],
                      currentQty: _quantity,
                      onQtyChanged: (q) => setState(() => _quantity = q),
                    ),
                    const SizedBox(height: 8),
                    ProductSellerCardWidget(product: _product),
                    const SizedBox(height: 8),
                    ProductTabsWidget(product: _product),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Sticky action bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wishlist button row
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _isWishlistLoading ? null : _toggleWishlist,
                    icon: _isWishlistLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFDC2626),
                            ),
                          )
                        : Icon(
                            _isInWishlist
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: const Color(0xFFDC2626),
                          ),
                    label: Text(
                      _isInWishlist
                          ? 'Dans la liste de souhaits ✓'
                          : 'Ajouter à la liste de souhaits',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _isInWishlist
                          ? const Color(0xFFFEE2E2)
                          : Colors.transparent,
                      side: const BorderSide(
                        color: Color(0xFFDC2626),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              ProductActionBarWidget(
                product: _product,
                quantity: _quantity,
                onAddToCart: () {
                  setState(() => _cartCount++);
                  // Track cart add
                  AnalyticsService.instance.trackCartAdd(
                    productId: (_product['id'] ?? '').toString(),
                    productName: (_product['name'] ?? '').toString(),
                    amount: ((_product['price'] ?? 0) as num).toDouble(),
                    quantity: _quantity,
                    shopId: (_product['shopId'] ?? _product['shop_id'] ?? '')
                        .toString(),
                  );
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ajouté au panier — ${_product['name']}'),
                      backgroundColor: const Color(0xFF1A1A1A),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                onBuyNow: () {
                  // Add to cart then navigate to checkout
                  AnalyticsService.instance.trackCartAdd(
                    productId: (_product['id'] ?? '').toString(),
                    productName: (_product['name'] ?? '').toString(),
                    amount: ((_product['price'] ?? 0) as num).toDouble(),
                    quantity: _quantity,
                  );
                  Navigator.pushNamed(context, '/checkout-screen');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return SafeArea(
      child: Column(
        children: [
          // Custom AppBar for tablet
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Color(0xFF1A1A1A),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    _isLoading ? '' : _product['name'] as String,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                      size: 24,
                      color: Color(0xFF1A1A1A),
                    ),
                    if (_cartCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6210),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_cartCount',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(child: ProductDetailSkeleton())
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Gallery
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          ProductGalleryWidget(
                            product: _product,
                            isFavorite: _isFavorite,
                            onFavoriteTap: () =>
                                setState(() => _isFavorite = !_isFavorite),
                            onBackTap: null,
                            cartCount: _cartCount,
                            isTablet: true,
                          ),
                          ProductTabsWidget(product: _product),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  // Right: Info
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ProductInfoWidget(product: _product),
                          const SizedBox(height: 12),
                          ProductPriceTiersWidget(
                            priceTiers:
                                (_product['priceTiers'] as List<dynamic>?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [],
                            currentQty: _quantity,
                            onQtyChanged: (q) => setState(() => _quantity = q),
                          ),
                          const SizedBox(height: 12),
                          ProductSellerCardWidget(product: _product),
                          const SizedBox(height: 12),
                          ProductActionBarWidget(
                            product: _product,
                            quantity: _quantity,
                            onAddToCart: () {},
                            onBuyNow: () {},
                            isInline: true,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
