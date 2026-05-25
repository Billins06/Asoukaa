import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
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
      final featuredResult = await DatabaseService.instance.getProducts(
        featuredOnly: true,
        limit: 10,
      );
      final trendingResult = await DatabaseService.instance.getProducts(
        limit: 20,
      );
      await _loadCartCount();

      if (mounted) {
        if (featuredResult.isFailure || trendingResult.isFailure) {
          final errorMsg =
              featuredResult.errorMessage ??
              trendingResult.errorMessage ??
              'Impossible de charger les produits.';
          ErrorHandler.showErrorDialog(
            context,
            message: errorMsg,
            onRetry: _loadData,
          );
        }
        setState(() {
          _featuredProducts = featuredResult.data ?? [];
          _trendingProducts = trendingResult.data ?? [];
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasConnectionError = true;
        });
        ErrorHandler.showExceptionDialog(context, e, onRetry: _loadData);
      }
    }
  }

  Future<void> _loadCartCount() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final result = await DatabaseService.instance.getUnreadNotificationCount(
        user.id,
      );
      if (mounted) setState(() => _cartCount = result);
    } catch (_) {}
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
    switch (index) {
      case 0:
        setState(() => _currentNavIndex = 0);
        break;
      case 1:
        // Marché — navigate to products list (search results)
        Navigator.pushNamed(context, AppRoutes.searchResults, arguments: '');
        break;
      case 2:
        // Messages tab
        _navigateToMessages();
        break;
      case 3:
        // Dashboard — navigate to appropriate dashboard by role
        final role = AuthService.instance.getUserRole();
        switch (role) {
          case 'vendeur':
            Navigator.pushNamed(context, AppRoutes.sellerDashboard);
            break;
          case 'livreur':
            Navigator.pushNamed(context, AppRoutes.delivererDashboard);
            break;
          default:
            Navigator.pushNamed(context, AppRoutes.buyerDashboard);
        }
        break;
      case 4:
        // Compte — navigate to profile based on role
        _navigateToProfile();
        break;
    }
  }

  void _navigateToMessages() {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
      return;
    }
    Navigator.pushNamed(context, AppRoutes.conversationsInbox);
  }

  void _navigateToProfile() {
    final role = AuthService.instance.getUserRole();
    switch (role) {
      case 'vendeur':
        Navigator.pushNamed(context, AppRoutes.sellerProfile);
        break;
      case 'livreur':
        Navigator.pushNamed(context, AppRoutes.delivererProfile);
        break;
      case 'admin':
        Navigator.pushNamed(context, AppRoutes.adminDashboard);
        break;
      default:
        Navigator.pushNamed(context, AppRoutes.buyerProfile);
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
