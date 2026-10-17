import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/product_service.dart';
import '../../services/vitrine_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/grille_produits.dart';
import '../../utils/price_range.dart';
import '../shops_list_screen/widgets/shops_list_view.dart';
import 'widgets/catalog_product_card.dart';
import 'widgets/featured_shop_block.dart';
import 'widgets/product_fields.dart';
import 'widgets/round_icon_button.dart';

/// Tri appliqué côté appli aux produits déjà chargés.
enum _SortMode { pertinence, nouveau, prixCroissant, prixDecroissant, ventes }

/// Page G : produits d'une catégorie / sous-catégorie, ou d'un rayon de la
/// Vitrine.
///
/// Arguments (route AppRoutes.categoryProducts) :
/// `{ 'mode': 'category' | 'rayon', 'id': String, 'title': String,
///    'parentTitle': String? }`
/// - mode 'category' → ProductService.getProducts(categoryId: id) (le
///   serveur inclut les sous-catégories descendantes) ;
/// - mode 'rayon'    → VitrineService.getRayonProducts(id).
class CategoryProductsScreen extends StatefulWidget {
  final Map<String, dynamic> args;

  const CategoryProductsScreen({super.key, required this.args});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  static const int _pageSize = 20;
  static const Color _chipBorder = Color(0xFFD9D3CC);
  static const Color _greyText = Color(0xFF5C5651);
  static const Color _softGrey = Color(0xFF8A827B);
  static const Color _gridGap = Color(0xFFEFEAE4);

  final ScrollController _scrollController = ScrollController();

  // Onglets : 0 = Produits, 1 = Boutiques (construit au premier affichage).
  int _tab = 0;
  bool _shopsTabOpened = false;

  List<Map<String, dynamic>> _products = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  String? _loadMoreError;
  String? _featuredShopId;
  int _cartCount = 0;
  // Incrémenté à chaque rechargement complet : une page « suivante » arrivée
  // après un pull-to-refresh est ignorée (sinon doublons / mélange).
  int _generation = 0;

  _SortMode _sort = _SortMode.pertinence;
  bool _verifiedOnly = false;
  bool _wholesaleOnly = false;
  // Pages chargées automatiquement pour remplir un filtre (plafonné).
  int _autoFills = 0;

  bool get _isRayon => widget.args['mode']?.toString() == 'rayon';

  String get _id => (widget.args['id'] ?? '').toString().trim();

  String get _title {
    final t = (widget.args['title'] ?? '').toString().trim();
    return t.isEmpty ? 'Produits' : t;
  }

  String? get _parentTitle {
    final t = (widget.args['parentTitle'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
    _loadCartCount();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Chargement ──────────────────────────────────────────────────────

  Future<ProductResult<List<Map<String, dynamic>>>> _fetch(int page) {
    if (_isRayon) {
      return VitrineService.instance.getRayonProducts(
        _id,
        page: page,
        limit: _pageSize,
      );
    }
    return ProductService.instance.getProducts(
      categoryId: _id,
      page: page,
      limit: _pageSize,
    );
  }

  List<Map<String, dynamic>> _dedupe(
    List<Map<String, dynamic>> incoming, [
    List<Map<String, dynamic>> existing = const [],
  ]) {
    final seen = <String>{
      for (final p in existing) (p['id'] ?? '').toString(),
    };
    final out = <Map<String, dynamic>>[];
    for (final p in incoming) {
      final id = (p['id'] ?? '').toString();
      if (id.isNotEmpty && !seen.add(id)) continue;
      out.add(p);
    }
    return out;
  }

  Future<void> _loadFirstPage({bool showLoader = true}) async {
    if (_id.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Cette page est introuvable.';
      });
      return;
    }
    final generation = ++_generation;
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
        _loadMoreError = null;
      });
    }
    final result = await _fetch(1);
    if (!mounted || generation != _generation) return;

    if (result.success) {
      final data = result.data ?? <Map<String, dynamic>>[];
      setState(() {
        _products = _dedupe(data);
        _page = 1;
        _hasMore = data.length >= _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
        _loadMoreError = null;
        _featuredShopId = _pickFeaturedShopId(_products);
      });
      _maybeFillPage();
    } else {
      final message = result.error ?? 'Impossible de charger les produits.';
      if (showLoader || _products.isEmpty) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _products = [];
          _error = message;
        });
      } else {
        // Pull-to-refresh raté : on garde la liste affichée.
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        _showErrorSnack(message);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _error != null) return;
    final generation = _generation;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    final next = _page + 1;
    final result = await _fetch(next);
    if (!mounted || generation != _generation) return;

    if (result.success) {
      final data = result.data ?? <Map<String, dynamic>>[];
      setState(() {
        _products = [..._products, ..._dedupe(data, _products)];
        _page = next;
        _hasMore = data.length >= _pageSize;
        _isLoadingMore = false;
      });
      _maybeFillPage();
    } else {
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = result.error ?? 'Impossible de charger la suite.';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400 &&
        _loadMoreError == null) {
      _loadMore();
    }
  }

  /// Charge la page suivante tant que l'écran n'est pas rempli (liste
  /// courte, ou filtres qui ne laissent que peu de produits visibles).
  void _maybeFillPage() {
    if (!mounted || !_hasMore || _isLoadingMore || _loadMoreError != null) {
      return;
    }
    if ((_verifiedOnly || _wholesaleOnly) &&
        _displayProducts.length < 10 &&
        _autoFills < 4) {
      _autoFills++;
      _loadMore();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  Future<void> _loadCartCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) setState(() => _cartCount = 0);
        return;
      }
      final response = await ApiService.instance.client.get('/api/v1/cart');
      final data = response.data;
      final count = (data is Map)
          ? (data['itemCount'] as int? ??
              (data['items'] as List?)?.length ??
              0)
          : 0;
      if (mounted) setState(() => _cartCount = count);
    } catch (_) {
      if (mounted) setState(() => _cartCount = 0);
    }
  }

  // ─── Données dérivées ────────────────────────────────────────────────

  /// Boutique « à la une » : celle qui a le plus de produits dans la liste
  /// chargée. null s'il n'y a qu'une boutique (ou aucune donnée vendeur).
  String? _pickFeaturedShopId(List<Map<String, dynamic>> products) {
    final counts = <String, int>{};
    for (final p in products) {
      if (productVendor(p) == null) continue;
      final id = productShopId(p);
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.length < 2) return null;
    String? best;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  int _sales(Map<String, dynamic> p) =>
      int.tryParse('${p['totalVentes'] ?? p['sold_count'] ?? 0}') ?? 0;

  DateTime _createdAt(Map<String, dynamic> p) =>
      DateTime.tryParse('${p['createdAt'] ?? ''}') ?? DateTime(2000);

  double _basePrice(Map<String, dynamic> p) => productBasePrice(p) ?? 0;

  bool get _hasVerifiedInfo =>
      _products.any((p) => shopIsVerified(productVendor(p)) != null);

  bool get _hasWholesale => _products.any((p) => hasPriceRange(p));

  bool get _hasSales => _products.any((p) => _sales(p) > 0);

  bool get _hasActiveFilters =>
      _sort != _SortMode.pertinence || _verifiedOnly || _wholesaleOnly;

  List<Map<String, dynamic>> get _displayProducts {
    final list = _products.where((p) {
      if (_verifiedOnly && shopIsVerified(productVendor(p)) != true) {
        return false;
      }
      if (_wholesaleOnly && !hasPriceRange(p)) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _SortMode.pertinence:
        break;
      case _SortMode.nouveau:
        list.sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
        break;
      case _SortMode.prixCroissant:
        list.sort((a, b) => _basePrice(a).compareTo(_basePrice(b)));
        break;
      case _SortMode.prixDecroissant:
        list.sort((a, b) => _basePrice(b).compareTo(_basePrice(a)));
        break;
      case _SortMode.ventes:
        list.sort((a, b) => _sales(b).compareTo(_sales(a)));
        break;
    }
    return list;
  }

  List<MapEntry<_SortMode, String>> get _sortOptions => [
        MapEntry(
          _SortMode.pertinence,
          _isRayon ? 'Ordre de la vitrine' : 'Plus récents',
        ),
        if (_isRayon) MapEntry(_SortMode.nouveau, 'Nouveau'),
        if (_hasSales || _sort == _SortMode.ventes)
          MapEntry(_SortMode.ventes, 'Meilleures ventes'),
      ];

  // ─── Actions ─────────────────────────────────────────────────────────

  void _openSearch() {
    Navigator.pushNamed(
      context,
      AppRoutes.searchResults,
      arguments: _title,
    ).then((_) => _loadCartCount());
  }

  void _openCart() {
    Navigator.pushNamed(context, AppRoutes.cart).then((_) => _loadCartCount());
  }

  void _openProduct(Map<String, dynamic> product) {
    Navigator.pushNamed(
      context,
      AppRoutes.productDetail,
      arguments: product,
    ).then((_) => _loadCartCount());
  }

  /// Mêmes arguments que la page « Boutiques suivies »
  /// (followed_shops_screen.dart → _openShop) : BoutiqueVendeurScreen
  /// recharge ensuite la boutique via GET /vendors/:id/public.
  void _openShop(Map<String, dynamic> vendor, String shopId) {
    final name = shopNameOf(vendor).isEmpty ? 'Boutique' : shopNameOf(vendor);
    final logo = shopLogoOf(vendor);
    final banner = validImageUrl(vendor['bannerUrl']);
    final location = shopLocationOf(vendor);
    Navigator.pushNamed(
      context,
      AppRoutes.boutiqueVendeur,
      arguments: <String, dynamic>{
        'id': shopId,
        'name': name,
        if (logo.isNotEmpty) 'logo': logo,
        'logoSemanticLabel': 'Logo de la boutique $name',
        if (banner.isNotEmpty) 'banner': banner,
        if (location.isNotEmpty) 'location': location,
      },
    ).then((_) => _loadCartCount());
  }

  void _toggleSort(_SortMode mode) {
    setState(() => _sort = _sort == mode ? _SortMode.pertinence : mode);
  }

  void _clearFilters() {
    setState(() {
      _sort = _SortMode.pertinence;
      _verifiedOnly = false;
      _wholesaleOnly = false;
    });
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Logique d'ajout au panier reprise telle quelle de l'écran Catégories /
  // des widgets de la page d'accueil (home_trending_widget.dart), avec les
  // mêmes messages.
  Future<void> _addToCart(Map<String, dynamic> product) async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn();
    if (!mounted) return;
    if (!isLoggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    try {
      await ApiService.instance.client.post(
        '/api/v1/cart/items',
        data: {
          'quantity': 1,
          if (product['variantId'] != null) 'variantId': product['variantId'],
        },
      );
      if (!mounted) return;
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
      // ⚠️ Filet de sécurité (comme ailleurs dans l'appli) : le minuteur
      // interne du SnackBar n'est pas toujours fiable, on force sa
      // disparition.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
      _loadCartCount();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'ajout au panier'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openFilterSheet() async {
    var sort = _sort;
    var verified = _verifiedOnly;
    var wholesale = _wholesaleOnly;
    final options = _sortOptions;
    final showVerified = _hasVerifiedInfo || _verifiedOnly;
    final showWholesale = _hasWholesale || _wholesaleOnly;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _chipBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Trier et filtrer',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sheetSectionTitle('Trier par'),
                    for (final option in options)
                      _sheetChoice(
                        label: option.value,
                        selected: sort == option.key,
                        radio: true,
                        onTap: () => setSheet(() => sort = option.key),
                      ),
                    if (showVerified || showWholesale) ...[
                      const SizedBox(height: 10),
                      _sheetSectionTitle('Filtrer'),
                      if (showVerified)
                        _sheetChoice(
                          label: 'Boutique vérifiée',
                          selected: verified,
                          radio: false,
                          onTap: () => setSheet(() => verified = !verified),
                        ),
                      if (showWholesale)
                        _sheetChoice(
                          label: 'Prix de gros (prix dégressif)',
                          selected: wholesale,
                          radio: false,
                          onTap: () => setSheet(() => wholesale = !wholesale),
                        ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => setSheet(() {
                            sort = _SortMode.pertinence;
                            verified = false;
                            wholesale = false;
                          }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: const BorderSide(color: _chipBorder),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            'Réinitialiser',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Afficher les résultats',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _sort = sort;
        _verifiedOnly = verified;
        _wholesaleOnly = wholesale;
        _autoFills = 0;
      });
      _maybeFillPage();
    }
  }

  // ─── Construction de l'écran ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Un rayon de la Vitrine n'est pas une catégorie : il n'existe pas de
    // « boutiques du rayon ». L'onglet Boutiques n'est donc proposé qu'en
    // mode catégorie (sinon il afficherait toutes les boutiques, hors sujet).
    final showShopsTab = !_isRayon;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            if (showShopsTab)
              _buildTabs()
            else
              const Divider(height: 1, thickness: 1, color: _gridGap),
            Expanded(
              child: showShopsTab
                  ? IndexedStack(
                      index: _tab,
                      children: [
                        _buildProductsTab(),
                        _shopsTabOpened
                            ? ShopsListView(categoryId: _id, showSearch: false)
                            : const SizedBox.shrink(),
                      ],
                    )
                  : _buildProductsTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final parent = _parentTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            semanticLabel: 'Retour',
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: const Color(0xFFF0ECE8),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _openSearch,
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (parent != null)
                                Text(
                                  parent,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 10.5,
                                    color: _softGrey,
                                    height: 1.2,
                                  ),
                                ),
                              Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.search_rounded,
                            size: 21,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.shopping_cart_outlined,
            badgeCount: _cartCount,
            semanticLabel: 'Panier',
            onTap: _openCart,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _gridGap)),
      ),
      child: Row(
        children: [
          _tabButton('Produits', 0),
          _tabButton('Boutiques', 1),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final active = _tab == index;
    return InkWell(
      onTap: () => setState(() {
        _tab = index;
        if (index == 1) _shopsTabOpened = true;
      }),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppTheme.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppTheme.textPrimary : _greyText,
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    final display = _displayProducts;
    final featured = (_isLoading || _error != null) ? null : _buildFeatured();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
        final tile = (width - 2 * (columns - 1)) / columns;
        // Hauteur de la carte alignée sur le réglage commun des grilles
        // (kProductGridRatio) ; la photo prend ce qui reste au-dessus de la
        // zone texte (jamais moins de 60 % ni plus de 120 % de la largeur).
        final photo = (tile / kProductGridRatio - kCatalogCardInfoHeight)
            .clamp(tile * 0.6, tile * 1.2)
            .toDouble();

        return ColoredBox(
          color: _gridGap,
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () => _loadFirstPage(showLoader: false),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (_isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ColoredBox(
                      color: Colors.white,
                      child: _buildError(),
                    ),
                  )
                else ...[
                  if (featured != null) SliverToBoxAdapter(child: featured),
                  SliverToBoxAdapter(child: _buildFilterRow()),
                  if (display.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ColoredBox(
                        color: Colors.white,
                        child: _buildEmpty(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 2),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final p = display[i];
                            return CatalogProductCard(
                              product: p,
                              imageSize: photo,
                              onTap: () => _openProduct(p),
                              onAddToCart: () => _addToCart(p),
                            );
                          },
                          childCount: display.length,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                          mainAxisExtent: photo + kCatalogCardInfoHeight,
                        ),
                      ),
                    ),
                  if (display.isNotEmpty)
                    SliverToBoxAdapter(child: _buildFooter()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget? _buildFeatured() {
    final shopId = _featuredShopId;
    if (shopId == null) return null;
    final items =
        _products.where((p) => productShopId(p) == shopId).take(10).toList();
    if (items.isEmpty) return null;
    final vendor = productVendor(items.first);
    if (vendor == null) return null;
    return FeaturedShopBlock(
      vendor: vendor,
      products: items,
      onOpenShop: () => _openShop(vendor, shopId),
      onOpenProduct: _openProduct,
    );
  }

  Widget _buildFilterRow() {
    final chips = <Widget>[
      _filterIconChip(),
      if (_isRayon)
        _chip(
          'Nouveau',
          _sort == _SortMode.nouveau,
          () => _toggleSort(_SortMode.nouveau),
        ),
      if (_hasSales || _sort == _SortMode.ventes)
        _chip(
          'Meilleures ventes',
          _sort == _SortMode.ventes,
          () => _toggleSort(_SortMode.ventes),
        ),
      if (_hasVerifiedInfo || _verifiedOnly)
        _chip('Boutique vérifiée', _verifiedOnly, () {
          setState(() {
            _verifiedOnly = !_verifiedOnly;
            _autoFills = 0;
          });
          _maybeFillPage();
        }),
      if (_hasWholesale || _wholesaleOnly)
        _chip('Prix de gros', _wholesaleOnly, () {
          setState(() {
            _wholesaleOnly = !_wholesaleOnly;
            _autoFills = 0;
          });
          _maybeFillPage();
        }),
    ];

    return Container(
      color: Colors.white,
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _filterIconChip() {
    final active = _hasActiveFilters;
    return Material(
      color: active ? AppTheme.primaryMuted : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: active ? AppTheme.primary : _chipBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _openFilterSheet,
        child: SizedBox(
          width: 48,
          height: 40,
          child: Icon(
            Icons.tune_rounded,
            size: 20,
            color: active ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppTheme.primaryMuted : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppTheme.primary : _chipBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _greyText,
        ),
      ),
    );
  }

  Widget _sheetChoice({
    required String label,
    required bool selected,
    required bool radio,
    required VoidCallback onTap,
  }) {
    final IconData icon;
    if (radio) {
      icon = selected
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded;
    } else {
      icon = selected
          ? Icons.check_box_rounded
          : Icons.check_box_outline_blank_rounded;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? AppTheme.primary : _chipBorder,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    Widget child;
    if (_isLoadingMore) {
      child = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppTheme.primary,
        ),
      );
    } else if (_loadMoreError != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _loadMoreError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 13, color: _greyText),
          ),
          TextButton(
            onPressed: _loadMore,
            child: Text(
              'Réessayer',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      );
    } else if (!_hasMore) {
      child = Text(
        'Vous avez tout vu',
        style: GoogleFonts.outfit(fontSize: 12, color: _softGrey),
      );
    } else {
      child = const SizedBox(height: 24);
    }
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 2),
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildEmpty() {
    final filtered = _products.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 52,
              color: AppTheme.muted,
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'Aucun produit ne correspond à ces filtres'
                  : 'Aucun produit pour le moment',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Essayez d’enlever un filtre.'
                  : 'De nouveaux articles arrivent régulièrement, revenez bientôt.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: _greyText),
            ),
            if (filtered) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _clearFilters,
                child: Text(
                  'Effacer les filtres',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: AppTheme.muted,
            ),
            const SizedBox(height: 12),
            Text(
              'Chargement impossible',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Une erreur est survenue.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: _greyText),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _loadFirstPage(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Réessayer',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
