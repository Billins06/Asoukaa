import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';
import '../../../services/api_service.dart';
import '../../../services/nest_auth_service.dart';
import '../../../services/wishlist_service.dart';
import '../../../utils/price_range.dart';

// Les favoris ne sont plus demandés carte par carte : l'ensemble des ids de
// produits favoris est chargé une seule fois et partagé via WishlistService
// (voir favoriteIds()).
Future<bool>? _loggedInProbe;

Future<bool> _isLoggedIn() async {
  final probe = _loggedInProbe ??=
      NestAuthService.instance.isLoggedIn().catchError((_) => false);
  final loggedIn = await probe;
  // On ne mémorise jamais un « non » : l'utilisateur peut se connecter ensuite.
  if (!loggedIn) _loggedInProbe = null;
  return loggedIn;
}

/// Carte produit de l'accueil (même présentation que les cartes de
/// « Tendances ») utilisée par « Meilleures boutiques » et « Tous les
/// produits » : prix en fourchette (paliers dégressifs), pastille de
/// réduction, favoris, ajout au panier.
///
/// La carte remplit la place que lui donne son parent (case de grille ou
/// SizedBox) : la photo prend la hauteur restante, donc aucun débordement.
class HomeProductCard extends StatefulWidget {
  /// Produit tel que renvoyé par GET /products (déjà passé par
  /// ProductService.normalizeProduct).
  final Map<String, dynamic> product;

  /// Appelé avec le produit normalisé (comme les autres cartes de l'accueil).
  final void Function(Map<String, dynamic>) onTap;
  final VoidCallback? onCartUpdated;

  const HomeProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onCartUpdated,
  });

  /// À appeler quand l'accueil se recharge entièrement.
  static void resetCaches() {
    WishlistService.instance.invalidateFavoriteIds();
    _loggedInProbe = null;
  }

  static String _text(dynamic v) => (v ?? '').toString().trim();

  static num? _num(dynamic v) {
    if (v is num) return v;
    return num.tryParse(_text(v));
  }

  /// Forme attendue par la carte et par l'écran fiche produit.
  static Map<String, dynamic> normalize(Map<String, dynamic> p) {
    // Image : liste d'objets {url}, liste de chaînes, ou chaîne directe.
    var imageUrl = '';
    final images = p['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      imageUrl = first is Map
          ? _text(first['url'] ?? first['imageUrl'])
          : _text(first);
    } else if (images is String) {
      imageUrl = images.trim();
    }
    if (imageUrl.isEmpty) {
      imageUrl = _text(p['imageUrl'] ?? p['image_url']);
    }

    // Boutique : le serveur envoie la fiche publique dans « vendor ».
    final shopData = p['vendor'] ?? p['vendeur'] ?? p['shops'] ?? p['shop_info'];
    var shopName = shopData is Map
        ? _text(shopData['shopName'] ?? shopData['name'])
        : _text(p['shop'] ?? p['shopName']);
    if (shopName.isEmpty) shopName = 'Boutique';

    final price = _num(p['price'] ?? p['basePrice'])?.round() ?? 0;
    final originalPrice = _num(
          p['original_price'] ?? p['originalPrice'] ?? p['compareAtPrice'],
        )?.round() ??
        price;
    final discount = originalPrice > price && originalPrice > 0
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : (_num(p['discount'])?.toInt() ?? 0);

    final name = _text(p['name'] ?? p['title']);
    return <String, dynamic>{
      'id': _text(p['id']),
      'name': name,
      'shop': shopName,
      'price': price,
      // Paliers dégressifs bruts : la carte affiche une fourchette
      // « meilleur palier – prix normal » via priceRangeLabel().
      'tierPrices': p['tierPrices'] ?? p['price_tiers'] ?? p['priceTiers'],
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': _num(p['rating'] ?? p['averageRating'])?.toDouble() ?? 0.0,
      'reviewCount': _num(
            p['reviews_count'] ?? p['reviewCount'] ?? p['review_count'],
          )?.toInt() ??
          0,
      'imageUrl': imageUrl,
      'semanticLabel': 'Produit $name disponible sur Asoukaa',
      'badge': _text(p['badge']),
      'soldCount': _num(p['sold_count'] ?? p['soldCount'])?.toInt() ?? 0,
      'seller_id': p['seller_id'] ?? p['vendeurId'] ?? '',
      'shop_id': shopData is Map ? (shopData['id'] ?? '') : '',
      'variantId': p['variantId'],
    };
  }

  @override
  State<HomeProductCard> createState() => _HomeProductCardState();
}

class _HomeProductCardState extends State<HomeProductCard> {
  bool _isInWishlist = false;
  bool _wishlistLoading = false;

  String get _id => (widget.product['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    final cached = WishlistService.instance.cachedFavoriteIds;
    if (cached != null) {
      _isInWishlist = cached.contains(_id);
    } else {
      _checkWishlist();
    }
  }

  Future<void> _checkWishlist() async {
    final id = _id;
    if (id.isEmpty) return;
    // Un seul chargement partagé par toutes les cartes (null = visiteur non
    // connecté ou erreur : on n'affiche alors aucun cœur plein).
    final ids = await WishlistService.instance.favoriteIds();
    if (!mounted || ids == null || _wishlistLoading) return;
    final inWishlist = ids.contains(id);
    if (inWishlist != _isInWishlist) setState(() => _isInWishlist = inWishlist);
  }

  Future<void> _toggleWishlist() async {
    final id = _id;
    if (id.isEmpty || _wishlistLoading) return;
    final loggedIn = await _isLoggedIn();
    if (!mounted) return;
    if (!loggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    setState(() => _wishlistLoading = true);
    try {
      if (_isInWishlist) {
        await ApiService.instance.client.delete('/api/v1/wishlist/$id');
        WishlistService.instance.markFavorite(id, false);
        if (mounted) {
          setState(() {
            _isInWishlist = false;
            _wishlistLoading = false;
          });
        }
      } else {
        await ApiService.instance.client
            .post('/api/v1/wishlist', data: {'productId': id});
        WishlistService.instance.markFavorite(id, true);
        if (mounted) {
          setState(() {
            _isInWishlist = true;
            _wishlistLoading = false;
          });
        }
      }
      // Le badge cœur de l'accueil écoute ce service.
      WishlistService.instance.refreshCount();
    } catch (_) {
      if (mounted) setState(() => _wishlistLoading = false);
    }
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final variantId = product['variantId'];
    if (variantId == null) {
      // Pas de variante connue : on laisse choisir sur la fiche produit.
      widget.onTap(product);
      return;
    }
    final isLoggedIn = await _isLoggedIn();
    if (!mounted) return;
    if (!isLoggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.client.post(
        '/api/v1/cart/items',
        data: {'quantity': 1, 'variantId': variantId},
      );
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
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
      // Filet de sécurité : le minuteur interne du SnackBar n'est pas fiable
      // partout, on force sa disparition.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) messenger.hideCurrentSnackBar();
      });
      widget.onCartUpdated?.call();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'ajout au panier'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFF3EEE9),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 28,
        color: Color(0xFFBDB5AD),
      ),
    );
  }

  Widget _buildImage(String url) {
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return _imagePlaceholder();
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 500,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, _) => Container(color: const Color(0xFFF3EEE9)),
      errorWidget: (context, _, __) => _imagePlaceholder(),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HomeProductCard.normalize(widget.product);
    // « 14 000 – 18 500 F » dès qu'un palier dégressif est moins cher,
    // sinon le prix normal seul.
    final priceLabel = priceRangeLabel(p, rangeCurrency: 'F');
    final discount = p['discount'] as int;
    final badge = p['badge'] as String;
    final rating = p['rating'] as double;
    final reviewCount = p['reviewCount'] as int;
    final soldCount = p['soldCount'] as int;

    return GestureDetector(
      onTap: () => widget.onTap(p),
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
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Semantics(
                  label: p['semanticLabel'] as String,
                  image: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(p['imageUrl'] as String),
                      if (discount > 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _badge('-$discount%', const Color(0xFFDC2626)),
                        ),
                      if (badge.isNotEmpty && discount == 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _badge(badge, const Color(0xFF7C3AED)),
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p['name'] as String,
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
                    p['shop'] as String,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF9E9E9E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rating > 0 || soldCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (rating > 0) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          if (reviewCount > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              '($reviewCount)',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF9E9E9E),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                        ],
                        if (soldCount > 0)
                          Flexible(
                            child: Text(
                              '$soldCount vendus',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
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
                              priceLabel,
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
                                '${formatPriceAmount(p['originalPrice'] as int)} F',
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
                        onTap: () => _addToCart(p),
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
    );
  }
}
