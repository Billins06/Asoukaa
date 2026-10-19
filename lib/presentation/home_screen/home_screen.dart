import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../routes/app_routes.dart';
import '../../utils/grille_produits.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../services/vitrine_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/mode_service.dart';
import '../../services/api_service.dart';
import './widgets/home_banner_widget.dart';
import './widgets/home_categories_widget.dart';
import './widgets/home_flash_deals_widget.dart';
import './widgets/home_search_bar_widget.dart';
import './widgets/home_trending_widget.dart';
import './widgets/home_best_shops_widget.dart';
import './widgets/home_product_card.dart';
import './widgets/home_section_title.dart';
import '../../services/product_service.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import '../../services/wishlist_service.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentNavIndex = 0;
  bool _isSearchOpen = false;
  int _cartCount = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<Map<String, dynamic>> _featuredProducts = [];
  List<Map<String, dynamic>> _trendingProducts = [];
  // Rayons de la Vitrine (admin) alimentant les blocs « Ventes flash » et
  // « Tendances ». null => le bloc affiche des produits de repli.
  Map<String, dynamic>? _flashRayon;
  Map<String, dynamic>? _trendingRayon;

  // « Meilleures boutiques » (GET /vitrine/best-shops). Vide => la section
  // n'apparait pas (ni repli, ni message d'erreur).
  List<Map<String, dynamic>> _bestShops = [];
  int _shopsGen = 0;
  // Incrémenté à chaque rechargement de l'accueil : relit les bannières.
  int _bannerRefresh = 0;

  // « Tous les produits » : défilement infini de GET /products?page=N.
  static const int _productsPageSize = 20;
  final List<Map<String, dynamic>> _allProducts = [];
  final Set<String> _allProductIds = <String>{};
  int _productsPage = 0; // dernière page reçue
  bool _productsHasMore = true;
  bool _productsLoading = false;
  bool _productsError = false;
  // Incrémenté à chaque rechargement complet : une réponse tardive d'une
  // ancienne génération est ignorée.
  int _productsGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 10;
      if (scrolled != _isScrolled) {
        setState(() => _isScrolled = scrolled);
      }
      _maybeLoadMoreProducts();
    });
    _loadData();
    _connectivitySub =
        _connectivityService.onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final isOnline =
          !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (isOnline && (_hasConnectionError || _isOfflineCached)) {
        _loadData();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh cart count when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _loadCartCount();
      WishlistService.instance.refreshCount();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh cart/wishlist counts when returning to this screen
    _loadCartCount();
    WishlistService.instance.refreshCount();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasConnectionError = false;
      // Rechargement complet : boutiques et grille repartent de zéro.
      _bestShops = [];
      _shopsGen++;
      _productsGen++;
      _bannerRefresh++;
      _allProducts.clear();
      _allProductIds.clear();
      _productsPage = 0;
      _productsHasMore = true;
      _productsLoading = false;
      _productsError = false;
    });
    HomeProductCard.resetCaches();

    final offline = await _connectivityService.isOffline();
    if (!mounted) return;
    if (offline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOfflineCached = true;
          _hasConnectionError = false;
          _productsHasMore = false;
        });
      }
      return;
    }

    // Sections du bas : chargées en parallèle des rayons, sans bloquer
    // l'accueil ni déclencher l'écran d'erreur de connexion.
    _loadBestShops();
    _loadMoreProducts();

    try {
      // 1) La Vitrine d'abord : premier rayon actif de type 'flash' et
      //    'tendance' (titre, produits choisis par l'admin, échéance).
      final vitrine = await Future.wait([
        VitrineService.instance.getByType('flash', limit: 10, throwOnError: true),
        VitrineService.instance
            .getByType('tendance', limit: 20, throwOnError: true),
      ]);
      final flashProducts = vitrine[0].products;
      final trendingProducts = vitrine[1].products;
      final flashRayon = flashProducts.isNotEmpty ? vitrine[0].rayon : null;
      final trendingRayon =
          trendingProducts.isNotEmpty ? vitrine[1].rayon : null;

      // Pas de repli : si l'admin n'a créé aucun rayon actif de ce type
      // (ou l'a désactivé, ou il n'a plus aucun produit visible), le bloc
      // n'apparait tout simplement pas sur l'accueil.

      if (mounted) {
        setState(() {
          _featuredProducts = flashProducts;
          _trendingProducts = trendingProducts;
          _flashRayon = flashRayon;
          _trendingRayon = trendingRayon;
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
    } catch (_) {
      // Serveur injoignable / erreur : on affiche l'écran d'erreur de
      // connexion avec son bouton « Réessayer » plutôt qu'un accueil vide.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasConnectionError = true;
          _featuredProducts = [];
          _trendingProducts = [];
          _flashRayon = null;
          _trendingRayon = null;
        });
      }
    }

    // Le squelette disparu, la grille « Tous les produits » peut déjà être
    // trop courte pour remplir l'écran : on enchaîne sans attendre un geste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMoreProducts();
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
      final response =
          await ApiService.instance.client.get('/api/v1/cart');
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _buildPhoneLayout(),
      bottomNavigationBar: AsoukaaBottomNav(
              currentIndex: _currentNavIndex,
              onTap: _handleNavTap,
            ),
    );
  }

  Widget _buildPhoneLayout() {
    return SafeArea(
      child: Column(
        children: [
          HomeSearchBarWidget(
            isSearchOpen: _isSearchOpen,
            cartCount: _cartCount,
            isScrolled: _isScrolled,
            onSearchToggle: () =>
                setState(() => _isSearchOpen = !_isSearchOpen),
          ),
          if (_isOfflineCached) OfflineCachedBanner(onRetry: _loadData),
          Expanded(
            child: _isLoading
                ? const HomeScreenSkeleton()
                : _hasConnectionError
                ? ConnectionErrorScreen(onRetry: _loadData)
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: _buildHomeSlivers(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _handleNavTap(int index) {
    debugPrint('[Nav] Tab tapped: $index');
    switch (index) {
      case 0:
        setState(() => _currentNavIndex = 0);
      case 1:
        Navigator.pushNamed(context, AppRoutes.categories);
      case 2:
        _navigateToMessages();
      case 3:
        _navigateToDashboard();
      case 4:
        _navigateToProfile();
    }
  }

  Future<void> _navigateToDashboard() async {
    try {
      // Rôle effectif : un vendeur en « mode client » reste côté client.
      final role = await ModeService.instance.getEffectiveRole()
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      switch (role) {
        case 'vendeur':
          Navigator.pushNamed(context, AppRoutes.sellerDashboard);
        case 'livreur':
          Navigator.pushNamed(context, AppRoutes.delivererDashboard);
        default:
          Navigator.pushNamed(context, AppRoutes.buyerDashboard);
      }
    } catch (e) {
      debugPrint('[Nav] Dashboard nav error: $e');
      if (mounted) Navigator.pushNamed(context, AppRoutes.buyerDashboard);
    }
  }

  Future<void> _navigateToMessages() async {
    try {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn()
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      if (!isLoggedIn) {
        Navigator.pushNamed(context, AppRoutes.signUpLogin);
        return;
      }
      Navigator.pushNamed(context, AppRoutes.conversationsInbox);
    } catch (e) {
      debugPrint('[Nav] Messages nav error: $e');
      if (mounted) Navigator.pushNamed(context, AppRoutes.signUpLogin);
    }
  }

  Future<void> _navigateToProfile() async {
    debugPrint('[Nav] Navigating to profile...');
    try {
      // Rôle effectif : un vendeur en « mode client » ouvre le profil client
      // (où se trouve le bouton « Passer en mode vendeur »).
      final role = await ModeService.instance.getEffectiveRole()
          .timeout(const Duration(seconds: 3));
      debugPrint('[Nav] Role obtained: $role');
      if (!mounted) return;
      switch (role) {
        case 'vendeur':
          Navigator.pushNamed(context, AppRoutes.sellerProfile);
        case 'livreur':
          Navigator.pushNamed(context, AppRoutes.delivererProfile);
        case 'admin':
          Navigator.pushNamed(context, AppRoutes.adminDashboard);
        default:
          Navigator.pushNamed(context, AppRoutes.buyerProfile);
      }
    } catch (e) {
      debugPrint('[Nav] Profile nav error: $e');
      if (mounted) Navigator.pushNamed(context, AppRoutes.buyerProfile);
    }
  }

  void _navigateToProduct(Map<String, dynamic> product) {
    Navigator.pushNamed(context, AppRoutes.productDetail, arguments: product);
  }

  // Page « Tous les produits » (liste complète, par pages).
  void _openAllProducts() {
    Navigator.pushNamed(context, AppRoutes.allProducts)
        .then((_) => _loadCartCount());
  }

  // Contenu de l'accueil. De la bannière aux catégories : inchangé. Puis les
  // rayons de la Vitrine, « Meilleures boutiques » (liste paresseuse) et
  // « Tous les produits » (SliverGrid paresseuse, défilement infini).
  List<Widget> _buildHomeSlivers() {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final showProductsSection =
        _allProducts.isNotEmpty || _productsLoading || _productsError;

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // L'espacement autour des bannières est porté par le widget
            // lui-même : aucune marge quand il n'y a aucune bannière.
            HomeBannerWidget(refreshToken: _bannerRefresh),
            _buildDeliveryRequestBanner(),
            const SizedBox(height: 20),
            const HomeCategoriesWidget(),
            const SizedBox(height: 20),
            if (_featuredProducts.isNotEmpty) ...[
              HomeFlashDealsWidget(
                onProductTap: _navigateToProduct,
                products: _featuredProducts,
                onCartUpdated: _loadCartCount,
                rayon: _flashRayon,
              ),
              const SizedBox(height: 20),
            ],
            HomeTrendingWidget(
              onProductTap: _navigateToProduct,
              products: _trendingProducts,
              onCartUpdated: _loadCartCount,
              rayon: _trendingRayon,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      if (_bestShops.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: HomeSectionTitle(
            icon: Icons.storefront_rounded,
            title: 'Meilleures boutiques',
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final shop = _bestShops[index];
              return HomeBestShopRow(
                key: ValueKey('best-shop-${shop['id']}'),
                shop: shop,
                onProductTap: _navigateToProduct,
                onCartUpdated: _loadCartCount,
              );
            },
            childCount: _bestShops.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
      ],
      if (showProductsSection) ...[
        SliverToBoxAdapter(
          child: HomeSectionTitle(
            icon: Icons.grid_view_rounded,
            title: 'Tous les produits',
            onSeeAll: _openAllProducts,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isTablet ? 3 : 2,
              childAspectRatio: kProductGridRatio,
              crossAxisSpacing: kProductGridSpacing,
              mainAxisSpacing: kProductGridSpacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = _allProducts[index];
                return HomeProductCard(
                  key: ValueKey('all-${product['id']}'),
                  product: product,
                  onTap: _navigateToProduct,
                  onCartUpdated: _loadCartCount,
                );
              },
              childCount: _allProducts.length,
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: _buildProductsFooter()),
    ];
  }

  // Bas de la grille : chargement, « Réessayer » discret, ou fin de liste.
  Widget _buildProductsFooter() {
    if (_productsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
        ),
      );
    }
    if (_productsError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          children: [
            Text(
              'Impossible de charger les produits.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _loadMoreProducts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Réessayer',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }
    if (!_productsHasMore && _allProducts.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'Vous avez tout vu',
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }

  // « Meilleures boutiques » : un échec ou une liste vide => pas de section.
  Future<void> _loadBestShops() async {
    final gen = ++_shopsGen;
    final shops = await VitrineService.instance.getBestShops();
    if (!mounted || gen != _shopsGen) return;
    setState(() => _bestShops = shops);
  }

  // Charge la page suivante de « Tous les produits » (une seule requête à
  // la fois ; les doublons par id sont écartés).
  Future<void> _loadMoreProducts() async {
    if (_productsLoading || !_productsHasMore) return;
    final gen = _productsGen;
    final nextPage = _productsPage + 1;
    setState(() {
      _productsLoading = true;
      _productsError = false;
    });

    final result = await ProductService.instance.getProductsPage(
      page: nextPage,
      limit: _productsPageSize,
    );
    if (!mounted || gen != _productsGen) return;

    final data = result.data;
    if (!result.success || data == null) {
      setState(() {
        _productsLoading = false;
        _productsError = true;
      });
      return;
    }

    setState(() {
      for (final product in data.items) {
        final id = (product['id'] ?? '').toString();
        if (id.isEmpty || !_allProductIds.add(id)) continue;
        _allProducts.add(product);
      }
      _productsPage = nextPage;
      _productsHasMore = data.hasMore;
      _productsLoading = false;
    });

    // Si la page n'a pas rempli l'écran, on enchaine sans attendre un geste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMoreProducts();
    });
  }

  // Appelé à chaque défilement : charge la suite quand on approche du bas.
  void _maybeLoadMoreProducts() {
    if (_productsLoading || _productsError || !_productsHasMore) return;
    if (_allProducts.isEmpty) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 800) {
      _loadMoreProducts();
    }
  }

  Widget _buildDeliveryRequestBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.deliveryRequest),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6210).withAlpha(60),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.moped_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Envoyer un colis',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Demandez un livreur pour une course express',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withAlpha(210),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
