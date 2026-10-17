import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/wishlist_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/custom_image_widget.dart';
import '../../widgets/app_toast.dart';
import '../../utils/price_range.dart';
import '../../utils/lecture_json.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _wishlistItems = [];

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    setState(() => _isLoading = true);
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final response =
          await ApiService.instance.client.get('/api/v1/wishlist');
      final rawData = response.data;
      final rawList = rawData is List
          ? rawData
          : (rawData is Map ? (rawData['data'] ?? rawData['items'] ?? []) as List : []);

      if (mounted) {
        setState(() {
          _wishlistItems = rawList
              .whereType<Map>()
              .map((e) => _normalizeItem(Map<String, dynamic>.from(e)))
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _normalizeItem(Map<String, dynamic> item) {
    final nestProduct =
        (item['product'] ?? item['products']) as Map<String, dynamic>?;
    if (nestProduct == null) return item;

    // Image : product.images > variant.imageUrl > placeholder
    final images = nestProduct['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      imageUrl = first is Map
          ? (first['url'] as String? ?? first['imageUrl'] as String? ?? '')
          : first.toString();
    }
    if (imageUrl.isEmpty) {
      imageUrl = nestProduct['imageUrl'] as String? ??
          nestProduct['image_url'] as String? ??
          '';
    }
    // Chercher dans les variants si disponibles
    if (imageUrl.isEmpty) {
      final variants = nestProduct['variants'] as List?;
      if (variants != null && variants.isNotEmpty) {
        final v = variants.first;
        if (v is Map) imageUrl = (v['imageUrl'] as String? ?? '');
      }
    }

    // Shop
    final shopData = nestProduct['shops'] ??
        nestProduct['vendor'] ??
        nestProduct['vendeur'] ??
        nestProduct['shop_info'];
    final shopName = shopData is Map
        ? (shopData['shopName'] as String? ??
            shopData['name'] as String? ??
            '')
        : (nestProduct['shop'] as String? ?? '');

    // Nom : NestJS retourne prod_name
    final name = (nestProduct['prod_name'] ??
            nestProduct['name'] ??
            nestProduct['title'] ??
            '').toString();

    // Prix : basePrice (string) > price
    final rawPrice = nestProduct['basePrice'] ?? nestProduct['price'];
    final price = rawPrice != null
        ? (double.tryParse(rawPrice.toString()) ?? 0.0)
        : 0.0;
    final originalPrice = lireDoubleOuNull(
      nestProduct['original_price'] ?? nestProduct['originalPrice'],
    );
    // Nouveau serveur : `stock` (entier), `defaultVariantId` (UUID ou null) et
    // `variantCount` (entier) sont fournis. Ancien serveur : ces champs sont
    // absents et on garde l'ancien comportement (stock lu sous les anciens
    // noms, sinon 0 = bouton désactivé).
    final stockQty = lireIntOuNull(nestProduct['stock']) ??
        lireIntOuNull(
          nestProduct['stock_quantity'] ?? nestProduct['stockQuantity'],
        ) ??
        0;
    final defaultVariantId = nestProduct['defaultVariantId']?.toString();
    final variantCount = lireIntOuNull(nestProduct['variantCount']);
    final addedPrice = lireDoubleOuNull(
      item['addedPrice'] ?? item['added_price'],
    );

    return {
      'id': item['id'] ?? '',
      'product_id': nestProduct['id'] ?? item['productId'] ?? '',
      'added_price': addedPrice,
      'products': {
        'id': nestProduct['id'] ?? '',
        'name': name,
        'price': price,
        // Paliers dégressifs bruts, conservés pour que la carte affiche la
        // fourchette « meilleur palier – prix normal » (priceRangeLabel).
        'tierPrices': nestProduct['tierPrices'] ??
            nestProduct['price_tiers'] ??
            nestProduct['priceTiers'],
        'original_price': originalPrice,
        'images': imageUrl.isNotEmpty ? [imageUrl] : <String>[],
        'stock_quantity': stockQty,
        // Ajoutés seulement si le serveur les fournit (sinon : ancien
        // serveur, voir _doitChoisirVariante).
        if (nestProduct.containsKey('defaultVariantId'))
          'defaultVariantId':
              (defaultVariantId == null || defaultVariantId.isEmpty)
                  ? null
                  : defaultVariantId,
        if (nestProduct.containsKey('variantCount'))
          'variantCount': variantCount,
        'shops': {'name': shopName},
      },
    };
  }

  Future<void> _removeFromWishlist(
      String wishlistId, String productId) async {
    try {
      await ApiService.instance.client
          .delete('/api/v1/wishlist/$productId');
      WishlistService.instance.refreshCount();
      if (mounted) {
        setState(() =>
            _wishlistItems.removeWhere((item) => item['id'] == wishlistId));
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
    // Produit à plusieurs variantes (taille, couleur...) ou sans variante par
    // défaut : le client doit choisir sur la fiche produit.
    if (_doitChoisirVariante(product)) {
      AppToast.show(
        context,
        message: 'Choisissez une variante sur la fiche produit',
        type: ToastType.info,
      );
      Navigator.pushNamed(
        context,
        AppRoutes.productDetail,
        arguments: product,
      );
      return;
    }
    try {
      await ApiService.instance.client.post(
        '/api/v1/cart/items',
        data: {
          'quantity': 1,
          'variantId': product['defaultVariantId'] ?? product['variantId'],
        },
      );
      if (mounted) AppToast.show(context, message: 'Ajouté au panier !');
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
                  const hasPriceChange = false;
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

/// Vrai si l'ajout direct au panier est impossible : plusieurs variantes
/// (`variantCount` > 1) ou aucune variante par défaut (`defaultVariantId`
/// absent). Avec un ancien serveur (champs absents) : jamais d'obligation de
/// choisir, on garde le comportement d'origine.
bool _doitChoisirVariante(Map<String, dynamic> product) {
  final variantCount = lireIntOuNull(product['variantCount']);
  final defaultId = product['defaultVariantId']?.toString() ?? '';
  final nouveauServeur =
      product.containsKey('variantCount') || product.containsKey('defaultVariantId');
  if (!nouveauServeur) return false;
  if (variantCount != null && variantCount > 1) return true;
  return defaultId.isEmpty;
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
    final price = lireDouble(product['price']);
    final originalPrice = lireDoubleOuNull(product['original_price']);
    final addedPrice = lireDoubleOuNull(item['added_price']);
    final shopName =
        (product['shops'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final inStock = lireInt(product['stock_quantity']);
    final choisir = inStock > 0 && _doitChoisirVariante(product);

    final priceDrop = addedPrice != null && price < addedPrice;

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
                        Flexible(
                          child: Text(
                            // « 25 – 39 F » quand un palier dégressif existe,
                            // sinon le prix normal seul.
                            priceRangeLabel(
                              product,
                              currency: 'F',
                            ),
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: priceDrop
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                          inStock <= 0
                              ? 'Rupture de stock'
                              : (choisir
                                    ? 'Choisir une variante'
                                    : 'Ajouter au panier'),
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
