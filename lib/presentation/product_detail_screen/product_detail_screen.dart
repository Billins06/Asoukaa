import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import './widgets/product_action_bar_widget.dart';
import './widgets/product_gallery_widget.dart';
import './widgets/product_info_widget.dart';
import './widgets/product_price_tiers_widget.dart';
import './widgets/product_seller_card_widget.dart';
import './widgets/product_tabs_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/product_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/wishlist_service.dart';
import '../../routes/app_routes.dart';
import '../../utils/lecture_json.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? productData;

  const ProductDetailScreen({super.key, this.productData});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  // TODO: Replace with [Riverpod/Bloc] for production
  int _quantity = 1;
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
      final result = await ProductService.instance.getProductById(productId);
      if (result.success && result.data != null && mounted) {
        setState(() {
          _product = _normalizeNestProduct(result.data!);
          _isLoading = false;
        });
        _checkWishlistStatus();
        _loadSellerPresence((_product['shopId'] ?? '').toString());
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Présence du vendeur (« En ligne » / « Vu … ») : GET /products/:id (public)
  // ne la renvoie plus, on la demande à la route légère
  // GET /vendors/:id/presence (elle ne compte pas de visite de boutique), en
  // essai « best-effort » : en cas d'échec (hors connexion, boutique
  // masquée...), rien n'est affiché plutôt qu'une information fausse.
  Future<void> _loadSellerPresence(String vendorId) async {
    if (vendorId.isEmpty) return;
    try {
      final loggedIn = await NestAuthService.instance.isLoggedIn();
      if (!loggedIn) return;
      final res = await ApiService.instance.client
          .get('/api/v1/vendors/$vendorId/presence');
      final data = res.data;
      if (data is! Map || !mounted) return;
      // Le produit affiché a pu changer pendant l'appel.
      if ((_product['shopId'] ?? '').toString() != vendorId) return;
      final seen = data['lastSeenAt'];
      setState(() {
        _product = {
          ..._product,
          'shopPresenceKnown': true,
          'shopIsOnline': data['isOnline'] == true,
          'shopLastSeenAt': seen is String ? seen : null,
        };
      });
    } catch (_) {}
  }

  Map<String, dynamic> _normalizeNestProduct(Map<String, dynamic> p) {
    // Image
    final images = p['images'];
    List<Map<String, dynamic>> imageList = [];
    if (images is List) {
      for (final img in images) {
        // Les vidéos (isVideo: true) sont lues à part, voir videoList.
        if (img is Map && img['isVideo'] == true) continue;
        if (img is Map) {
          imageList.add({
            'url': img['url'] ?? img['imageUrl'] ?? '',
            'semanticLabel': img['semanticLabel'] ?? 'Image du produit',
          });
        } else if (img is String) {
          imageList.add({'url': img, 'semanticLabel': 'Image du produit'});
        }
      }
    }
    // Vidéos du produit : ProductService._normalize() les fournit sous
    // 'videos' (URL String) ; on accepte aussi des Map et d'éventuelles
    // entrées isVideo restées dans 'images'. Affichées après les photos.
    final videoList = <String>[];
    void addVideo(dynamic v) {
      final url = (v is Map ? (v['url'] ?? v['imageUrl'] ?? '') : (v ?? ''))
          .toString()
          .trim();
      if (url.isNotEmpty && !videoList.contains(url)) videoList.add(url);
    }

    final rawVideos = p['videos'];
    if (rawVideos is List) {
      for (final v in rawVideos) {
        addVideo(v);
      }
    }
    if (images is List) {
      for (final img in images) {
        if (img is Map && img['isVideo'] == true) addVideo(img);
      }
    }

    if (imageList.isEmpty) {
      // image_url est défini par ProductService._normalize() depuis variant.imageUrl
      final directUrl = (p['imageUrl'] ?? p['image_url'] ?? '').toString().trim();
      imageList = [
        {
          'url': directUrl.isNotEmpty
              ? directUrl
              : 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400',
          'semanticLabel': 'Image du produit',
        },
      ];
    }

    final price = lireInt(p['price']);
    final originalPrice = lireInt(
      p['original_price'] ?? p['originalPrice'] ?? p['compareAtPrice'],
      price,
    );
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;

    // Shop : NestJS = vendor{shopName, id, userId, user{id}} (clé réelle du backend)
    final shopData = p['vendor'] ?? p['shops'] ?? p['vendeur'] ?? p['shop_info'];
    final shopName = shopData is Map
        ? (shopData['shopName'] as String? ?? shopData['name'] as String? ?? '')
        : (p['shop'] as String? ?? '');
    final shopId = shopData is Map ? (shopData['id'] ?? '') : (p['shop_id'] ?? '');
    final shopLogo = shopData is Map
        ? (shopData['logoUrl'] as String? ?? shopData['logo_url'] as String? ?? '')
        : '';
    final shopRating = shopData is Map
        ? lireDouble(shopData['rating'], 4.5)
        : 4.5;
    final shopVerified = shopData is Map
        ? (shopData['isVerified'] as bool? ?? shopData['is_verified'] as bool? ?? false)
        : false;

    final specs = p['specs'];
    List<Map<String, dynamic>> specList = [];
    if (specs is List) {
      for (final s in specs) {
        if (s is Map) specList.add(Map<String, dynamic>.from(s));
      }
    }

    // Prix dégressifs : GET /products/:id les renvoie sous `tierPrices`
    // [{minQuantity, maxQuantity, price: "1500.00"}] (décimal en chaîne).
    // ⚠️ Avant, seules les clés price_tiers/priceTiers étaient lues : la
    // section "Prix dégressifs" n'apparaissait donc jamais.
    final rawTiers = p['tierPrices'] ??
        p['tier_prices'] ??
        p['price_tiers'] ??
        p['priceTiers'];
    final List<Map<String, int>> parsedTiers = [];
    if (rawTiers is List) {
      for (final t in rawTiers) {
        if (t is! Map) continue;
        final minQty = int.tryParse(
          '${t['minQuantity'] ?? t['min_quantity'] ?? t['qty'] ?? ''}',
        );
        final tierPrice = double.tryParse('${t['price'] ?? ''}');
        if (minQty == null || minQty < 1) continue;
        if (tierPrice == null || tierPrice <= 0) continue;
        parsedTiers.add({'minQuantity': minQty, 'price': tierPrice.round()});
      }
    }
    parsedTiers.sort(
      (a, b) => a['minQuantity']!.compareTo(b['minQuantity']!),
    );
    // Lignes affichées par ProductPriceTiersWidget ({qty, label, price}) :
    // une ligne "prix normal" pour les petites quantités, puis un palier par
    // ligne. Même règle que le backend (tier-pricing.util.ts) : un palier
    // plus cher que le prix normal n'est jamais appliqué.
    final List<Map<String, dynamic>> tierList = [];
    if (parsedTiers.isNotEmpty) {
      final firstMin = parsedTiers.first['minQuantity']!;
      if (firstMin > 1) {
        tierList.add({
          'qty': 1,
          'label': firstMin == 2 ? '1 unité' : '1 à ${firstMin - 1} unités',
          'price': price,
        });
      }
      for (final t in parsedTiers) {
        final minQty = t['minQuantity']!;
        final tierPrice = t['price']!;
        tierList.add({
          'qty': minQty,
          'label': 'À partir de $minQty unité${minQty > 1 ? 's' : ''}',
          'price': (price > 0 && price < tierPrice) ? price : tierPrice,
        });
      }
    }

    // Localisation : adresse réelle de la boutique (VendorProfile.shopAddress,
    // renvoyée sous `vendor` par GET /products/:id), sinon le "Lieu" saisi à
    // la publication, sinon une mention neutre.
    // ⚠️ Avant : p['location'] ?? 'Bénin' — le produit n'a pas de champ
    // location côté backend, la fiche affichait donc toujours "Bénin".
    final shopAddress = shopData is Map
        ? (shopData['shopAddress'] ?? shopData['shop_address'] ?? '')
            .toString()
            .trim()
        : '';
    var productLieu = (p['location'] ?? p['lieu'] ?? '').toString().trim();
    if (productLieu.isEmpty) {
      // Le "Lieu" n'a pas de colonne dédiée : publier_produit_screen l'envoie
      // dans `tags` avec la marque (optionnelle), en minuscules. Un seul tag
      // = forcément le lieu (champ obligatoire) ; avec deux tags on ne peut
      // pas distinguer la marque du lieu, donc on ne devine pas.
      final tags = (p['tags'] as List?)
              ?.whereType<Map>()
              .map((t) => (t['tag'] ?? '').toString().trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          const <String>[];
      if (tags.length == 1) {
        productLieu = tags.first[0].toUpperCase() + tags.first.substring(1);
      }
    }
    final location = shopAddress.isNotEmpty
        ? shopAddress
        : (productLieu.isNotEmpty ? productLieu : 'Localisation non précisée');

    return {
      'id': p['id'] ?? '',
      'variantId': p['variantId'],
      'name': p['name'] ?? '',
      'shop': shopName,
      'shopId': shopId,
      'shop_id': shopId,
      'shopLogo': shopLogo,
      'shopLogoSemanticLabel': 'Logo de la boutique $shopName',
      'shopRating': shopRating,
      'shopSales': 0,
      'shopIsVerified': shopVerified,
      'seller_id': (shopData is Map ? shopData['userId'] as String? : null) ?? p['seller_id'] ?? p['vendeurId'] ?? '',
      'price': price,
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': lireDouble(p['rating'] ?? p['averageRating'], 4.5),
      'reviewCount': p['review_count'] as int? ?? p['reviewCount'] as int? ?? 0,
      'imageUrl': imageList.first['url'] ?? '',
      'semanticLabel': imageList.first['semanticLabel'] ?? '',
      'images': imageList,
      'videos': videoList,
      'stockLeft': p['stock_quantity'] as int? ?? p['stockQuantity'] as int? ?? 0,
      'isHot': p['is_featured'] as bool? ?? p['isFeatured'] as bool? ?? false,
      'category': p['category'] ?? '',
      'categoryId': (p['categories'] is List && (p['categories'] as List).isNotEmpty)
          ? ((p['categories'] as List).first is Map
              ? ((p['categories'] as List).first['id'] ?? '')
              : '')
          : (p['categoryId'] ?? ''),
      'location': location,
      'minOrder': p['min_order'] as int? ?? p['minOrder'] as int? ?? 1,
      'description': p['description'] ?? '',
      'priceTiers': tierList,
      // Paliers bruts {minQuantity, price} (int) pour _unitPriceForQty()
      'tierPrices': parsedTiers,
      'specs': specList,
      'reviews': p['reviews'] ?? [],
    };
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return (double.tryParse('${v ?? ''}') ?? 0).toInt();
  }

  // Prix unitaire applicable à [qty] : palier dont la minQuantity est la
  // plus haute tout en restant <= qty, plafonné au prix normal. Réplique
  // pour l'affichage de resolveTierUnitPrice() (backend,
  // common/utils/tier-pricing.util.ts) — c'est le backend qui fixe le prix
  // réellement facturé au panier et à la commande.
  int _unitPriceForQty(int qty) {
    final base = _toInt(_product['price']);
    final tiers = _product['tierPrices'];
    if (tiers is! List) return base;
    int? bestMin;
    int? bestPrice;
    for (final t in tiers) {
      if (t is! Map) continue;
      final minQty = int.tryParse('${t['minQuantity'] ?? ''}');
      final tierPrice = double.tryParse('${t['price'] ?? ''}')?.round();
      if (minQty == null || tierPrice == null || tierPrice <= 0) continue;
      if (minQty <= qty && (bestMin == null || minQty > bestMin)) {
        bestMin = minQty;
        bestPrice = tierPrice;
      }
    }
    if (bestPrice == null) return base;
    return (base > 0 && base < bestPrice) ? base : bestPrice;
  }

  // Produit tel qu'affiché dans l'en-tête prix et la barre d'achat : si la
  // quantité choisie atteint un palier dégressif, le prix unitaire devient
  // celui du palier (prix normal barré + % d'économie), et le total de la
  // barre d'achat suit. Sinon, produit inchangé.
  Map<String, dynamic> get _pricedProduct {
    final base = _toInt(_product['price']);
    final unit = _unitPriceForQty(_quantity);
    if (unit >= base) return _product;
    final originalRaw = _toInt(_product['originalPrice']);
    final original = originalRaw > base ? originalRaw : base;
    return {
      ..._product,
      'price': unit,
      'originalPrice': original,
      'discount':
          original > 0 ? (((original - unit) / original) * 100).round() : 0,
    };
  }

  Future<void> _addToCart() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!mounted) return;
    if (!isLoggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    final variantId = _product['variantId'];
    if (variantId == null || variantId.toString().isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce produit n\'est pas disponible à l\'achat pour le moment'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await ApiService.instance.client.post(
        '/api/v1/cart/items',
        data: {
          'variantId': variantId,
          'quantity': _quantity,
        },
      );
      if (!mounted) return;
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
          action: SnackBarAction(
            label: 'Voir panier',
            textColor: const Color(0xFFFF6210),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
          ),
        ),
      );
      // ⚠️ Filet de sécurité : sur certains environnements (onglet Chrome
      // arrière-plan, TickerMode suspendu par une navigation), le timer
      // interne du SnackBar ne se déclenche pas de façon fiable et le
      // message reste affiché indéfiniment. On force sa disparition avec
      // un vrai minuteur, indépendant de l'état d'animation du Scaffold.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'ajout au panier'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _ensureInCart() async {
    final variantId = _product['variantId'];
    if (variantId == null || variantId.toString().isEmpty) return false;
    try {
      await ApiService.instance.client.post(
        '/api/v1/cart/items',
        data: {
          'variantId': variantId,
          'quantity': _quantity,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkWishlistStatus() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!isLoggedIn || !mounted) return;
    final productId = (_product['id'] ?? '').toString();
    if (productId.isEmpty) return;
    try {
      final res = await ApiService.instance.client
          .get('/api/v1/wishlist/check/$productId');
      final inWishlist = res.data?['inWishlist'] as bool? ?? false;
      if (mounted) setState(() => _isInWishlist = inWishlist);
    } catch (_) {}
  }

  Future<void> _toggleWishlist() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    final productId = (_product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    setState(() => _isWishlistLoading = true);
    try {
      if (_isInWishlist) {
        await ApiService.instance.client.delete('/api/v1/wishlist/$productId');
        WishlistService.instance.markFavorite(productId, false);
        WishlistService.instance.refreshCount();
        if (!mounted) return;
        setState(() { _isInWishlist = false; _isWishlistLoading = false; });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retiré de la liste de souhaits', style: GoogleFonts.outfit()),
            backgroundColor: AppTheme.textSecondary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        await ApiService.instance.client.post(
          '/api/v1/wishlist',
          data: {'productId': productId},
        );
        WishlistService.instance.markFavorite(productId, true);
        WishlistService.instance.refreshCount();
        if (!mounted) return;
        setState(() { _isInWishlist = true; _isWishlistLoading = false; });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('Ajouté à la liste de souhaits', style: GoogleFonts.outfit())),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    Navigator.pushNamed(context, AppRoutes.wishlist);
                  },
                  child: Text('Voir', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isWishlistLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur, veuillez réessayer', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
                isFavorite: _isInWishlist,
                onFavoriteTap: _isWishlistLoading ? () {} : _toggleWishlist,
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
                    ProductInfoWidget(product: _pricedProduct),
                    const SizedBox(height: 8),
                    ProductPriceTiersWidget(
                      priceTiers:
                          (_product['priceTiers'] as List<dynamic>?)
                              ?.cast<Map<String, dynamic>>() ??
                          [],
                      basePrice: _toInt(_product['price']),
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
              ProductActionBarWidget(
                product: _pricedProduct,
                quantity: _quantity,
                onAddToCart: () {
                  setState(() => _cartCount++);
                  _addToCart();
                },
                onBuyNow: () async {
                  final added = await _ensureInCart();
                  if (!mounted) return;
                  if (!added) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Erreur lors de l\'ajout au panier'),
                        backgroundColor: Color(0xFFDC2626),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  // Avant : direction directe vers '/checkout-screen' SANS aucun
                  // argument. CheckoutScreen ne charge jamais le panier lui-meme (voir
                  // son commentaire "recus ici via les arguments de navigation") : ca
                  // atterrissait sur un recapitulatif vide (0 FCFA), un frais de
                  // livraison toujours a 2500 FCFA par defaut, et surtout aucun moyen
                  // de choisir sa commune (ce champ n'existe que sur la page panier,
                  // via DeliverySelectorWidget). On passe donc par le panier, qui
                  // contient deja cet article, pour que le choix de commune et le vrai
                  // total soient corrects avant de continuer vers le paiement.
                  Navigator.pushNamed(context, AppRoutes.cart);
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
                            isFavorite: _isInWishlist,
                            onFavoriteTap:
                                _isWishlistLoading ? () {} : _toggleWishlist,
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
                          ProductInfoWidget(product: _pricedProduct),
                          const SizedBox(height: 12),
                          ProductPriceTiersWidget(
                            priceTiers:
                                (_product['priceTiers'] as List<dynamic>?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [],
                            basePrice: _toInt(_product['price']),
                            currentQty: _quantity,
                            onQtyChanged: (q) => setState(() => _quantity = q),
                          ),
                          const SizedBox(height: 12),
                          ProductSellerCardWidget(product: _product),
                          const SizedBox(height: 12),
                          ProductActionBarWidget(
                            product: _pricedProduct,
                            quantity: _quantity,
                            onAddToCart: () {
                              setState(() => _cartCount++);
                              _addToCart();
                            },
                            onBuyNow: () async {
                              final added = await _ensureInCart();
                              if (!mounted) return;
                              if (!added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Erreur lors de l\'ajout au panier'),
                                    backgroundColor: Color(0xFFDC2626),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              // Avant : direction directe vers '/checkout-screen' SANS aucun
                              // argument. CheckoutScreen ne charge jamais le panier lui-meme (voir
                              // son commentaire "recus ici via les arguments de navigation") : ca
                              // atterrissait sur un recapitulatif vide (0 FCFA), un frais de
                              // livraison toujours a 2500 FCFA par defaut, et surtout aucun moyen
                              // de choisir sa commune (ce champ n'existe que sur la page panier,
                              // via DeliverySelectorWidget). On passe donc par le panier, qui
                              // contient deja cet article, pour que le choix de commune et le vrai
                              // total soient corrects avant de continuer vers le paiement.
                              Navigator.pushNamed(context, AppRoutes.cart);
                            },
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
