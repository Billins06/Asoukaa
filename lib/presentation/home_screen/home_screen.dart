import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../services/product_service.dart';
import '../../services/nest_auth_service.dart';
import './widgets/home_banner_widget.dart';
import './widgets/home_categories_widget.dart';
import './widgets/home_flash_deals_widget.dart';
import './widgets/home_search_bar_widget.dart';
import './widgets/home_trending_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
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

  List<Map<String, dynamic>> _featuredProducts = [];
  List<Map<String, dynamic>> _trendingProducts = [];

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
    });
    _loadData();
    _connectivityService.onConnectivityChanged.listen((results) {
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh cart count when returning to this screen
    _loadCartCount();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasConnectionError = false;
    });

    final offline = await _connectivityService.isOffline();
    if (offline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOfflineCached = true;
          _hasConnectionError = false;
        });
      }
      return;
    }

    try {
      final results = await Future.wait([
        ProductService.instance.getProducts(isFeatured: true, limit: 10),
        ProductService.instance.getProducts(limit: 20),
      ]);

      if (mounted) {
        setState(() {
          _featuredProducts = results[0].data ?? [];
          _trendingProducts = results[1].data ?? [];
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _featuredProducts = [];
          _trendingProducts = [];
        });
      }
    }
  }

  Future<void> _loadCartCount() async {
    // Cart count sera implémenté avec l'API panier NestJS
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
      bottomNavigationBar: isTablet
          ? null
          : AsoukaaBottomNav(
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
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const HomeBannerWidget(),
                          const SizedBox(height: 16),
                          _buildDeliveryRequestBanner(),
                          const SizedBox(height: 20),
                          const HomeCategoriesWidget(),
                          const SizedBox(height: 20),
                          HomeFlashDealsWidget(
                            onProductTap: _navigateToProduct,
                            products: _featuredProducts,
                            onCartUpdated: _loadCartCount,
                          ),
                          const SizedBox(height: 20),
                          HomeTrendingWidget(
                            onProductTap: _navigateToProduct,
                            products: _trendingProducts,
                            onCartUpdated: _loadCartCount,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return SafeArea(
      child: Row(
        children: [
          AsoukaaNavigationRail(
            currentIndex: _currentNavIndex,
            onTap: (i) => setState(() => _currentNavIndex = i),
          ),
          const VerticalDivider(width: 1),
          Expanded(
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
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                const HomeBannerWidget(),
                                const SizedBox(height: 16),
                                _buildDeliveryRequestBanner(),
                                const SizedBox(height: 20),
                                const HomeCategoriesWidget(),
                                const SizedBox(height: 20),
                                HomeFlashDealsWidget(
                                  onProductTap: _navigateToProduct,
                                  products: _featuredProducts,
                                  onCartUpdated: _loadCartCount,
                                ),
                                const SizedBox(height: 20),
                                HomeTrendingWidget(
                                  onProductTap: _navigateToProduct,
                                  products: _trendingProducts,
                                  onCartUpdated: _loadCartCount,
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
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
      final role = await NestAuthService.instance.getUserRole()
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
      final role = await NestAuthService.instance.getUserRole()
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
