import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/custom_image_widget.dart';
import '../../widgets/app_toast.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _wishlistItems = [];
  RealtimeChannel? _priceChannel;
  final Set<String> _priceChangedIds = {};

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  @override
  void dispose() {
    _priceChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadWishlist() async {
    setState(() => _isLoading = true);
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final result = await client
          .from('wishlists')
          .select(
            'id, product_id, added_price, products(id, name, price, original_price, images, stock_quantity, shops(name))',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _wishlistItems = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
        _subscribeToPriceChanges();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToPriceChanges() {
    final productIds = _wishlistItems
        .map((item) => item['product_id'] as String?)
        .whereType<String>()
        .toList();
    if (productIds.isEmpty) return;

    _priceChannel?.unsubscribe();
    _priceChannel = Supabase.instance.client
        .channel('wishlist_prices')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final updated = payload.newRecord;
            final productId = updated['id'] as String?;
            if (productId == null || !productIds.contains(productId)) return;

            final newPrice = (updated['price'] as num?)?.toDouble();
            if (newPrice == null || !mounted) return;

            final idx = _wishlistItems.indexWhere(
              (item) => item['product_id'] == productId,
            );
            if (idx == -1) return;

            final oldPrice =
                (_wishlistItems[idx]['products']?['price'] as num?)
                    ?.toDouble() ??
                0;
            if (newPrice != oldPrice) {
              setState(() {
                _wishlistItems[idx]['products']['price'] = newPrice;
                _priceChangedIds.add(productId);
              });
              _showPriceAlert(
                _wishlistItems[idx]['products']?['name'] ?? 'Produit',
                oldPrice,
                newPrice,
              );
            }
          },
        )
        .subscribe();
  }

  void _showPriceAlert(String name, double oldPrice, double newPrice) {
    final dropped = newPrice < oldPrice;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              dropped ? Icons.trending_down_rounded : Icons.trending_up_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dropped
                    ? 'Prix baissé ! "$name" : ${newPrice.toStringAsFixed(0)} F (était ${oldPrice.toStringAsFixed(0)} F)'
                    : 'Prix augmenté : "$name" : ${newPrice.toStringAsFixed(0)} F',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: dropped ? AppTheme.success : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _removeFromWishlist(String wishlistId, String productId) async {
    try {
      await Supabase.instance.client
          .from('wishlists')
          .delete()
          .eq('id', wishlistId);
      if (mounted) {
        setState(() {
          _wishlistItems.removeWhere((item) => item['id'] == wishlistId);
          _priceChangedIds.remove(productId);
        });
        AppToast.show(context, message: 'Retiré de la liste de souhaits');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de la suppression',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('carts').upsert({
        'user_id': user.id,
        'product_id': product['id'] as String,
        'quantity': 1,
      }, onConflict: 'user_id,product_id');
      if (mounted) {
        AppToast.show(context, message: 'Ajouté au panier !');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Erreur', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Liste de souhaits',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (_wishlistItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_wishlistItems.length} article${_wishlistItems.length > 1 ? 's' : ''}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _wishlistItems.isEmpty
          ? EmptyStateWidget(
              icon: Icons.favorite_border_rounded,
              title: 'Liste de souhaits vide',
              description:
                  'Ajoutez des produits à votre liste pour les retrouver facilement',
              ctaLabel: 'Explorer les produits',
              onCtaTap: () => Navigator.pushNamed(context, AppRoutes.home),
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _loadWishlist,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                itemCount: _wishlistItems.length,
                separatorBuilder: (_, __) => SizedBox(height: 1.5.h),
                itemBuilder: (context, index) {
                  final item = _wishlistItems[index];
                  final product =
                      item['products'] as Map<String, dynamic>? ?? {};
                  final productId = item['product_id'] as String? ?? '';
                  final hasPriceChange = _priceChangedIds.contains(productId);
                  return _WishlistCard(
                    item: item,
                    product: product,
                    hasPriceChange: hasPriceChange,
                    onRemove: () =>
                        _removeFromWishlist(item['id'] as String, productId),
                    onAddToCart: () => _addToCart(product),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.productDetail,
                      arguments: product,
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _WishlistCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> product;
  final bool hasPriceChange;
  final VoidCallback onRemove;
  final VoidCallback onAddToCart;
  final VoidCallback onTap;

  const _WishlistCard({
    required this.item,
    required this.product,
    required this.hasPriceChange,
    required this.onRemove,
    required this.onAddToCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final images = product['images'] as List<dynamic>? ?? [];
    final imageUrl = images.isNotEmpty ? images.first as String : '';
    final name = product['name'] as String? ?? 'Produit';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final originalPrice = (product['original_price'] as num?)?.toDouble();
    final addedPrice = (item['added_price'] as num?)?.toDouble();
    final shopName =
        (product['shops'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final inStock = (product['stock_quantity'] as num?)?.toInt() ?? 0;

    final priceDrop = addedPrice != null && price < addedPrice;
    final priceRise = addedPrice != null && price > addedPrice;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: hasPriceChange
              ? Border.all(
                  color: priceDrop ? AppTheme.success : const Color(0xFFDC2626),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: imageUrl.isNotEmpty
                      ? CustomImageWidget(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          semanticLabel: 'Image de $name',
                        )
                      : Container(
                          color: AppTheme.background,
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppTheme.muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Remove button
                        GestureDetector(
                          onTap: onRemove,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFDC2626),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (shopName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        shopName,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Price row
                    Row(
                      children: [
                        Text(
                          '${price.toStringAsFixed(0)} F',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: priceDrop
                                ? AppTheme.success
                                : AppTheme.primary,
                          ),
                        ),
                        if (originalPrice != null && originalPrice > price) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${originalPrice.toStringAsFixed(0)} F',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.muted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        if (hasPriceChange) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: priceDrop
                                  ? AppTheme.successContainer
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  priceDrop
                                      ? Icons.trending_down_rounded
                                      : Icons.trending_up_rounded,
                                  size: 10,
                                  color: priceDrop
                                      ? AppTheme.success
                                      : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  priceDrop ? 'Baisse !' : 'Hausse',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: priceDrop
                                        ? AppTheme.success
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (addedPrice != null && hasPriceChange) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ajouté à ${addedPrice.toStringAsFixed(0)} F',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Add to cart button
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: ElevatedButton.icon(
                        onPressed: inStock > 0 ? onAddToCart : null,
                        icon: const Icon(Icons.shopping_cart_rounded, size: 14),
                        label: Text(
                          inStock > 0
                              ? 'Ajouter au panier'
                              : 'Rupture de stock',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: inStock > 0
                              ? AppTheme.primary
                              : AppTheme.muted,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
