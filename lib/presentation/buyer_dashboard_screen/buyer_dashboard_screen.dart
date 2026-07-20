import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/status_badge_widget.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import '../import_assiste_screen/import_assiste_screen.dart';
import '../notifications_screen/notifications_screen.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';

class BuyerDashboardScreen extends StatefulWidget {
  const BuyerDashboardScreen({super.key});

  @override
  State<BuyerDashboardScreen> createState() => _BuyerDashboardScreenState();
}

class _BuyerDashboardScreenState extends State<BuyerDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentNavIndex = 3;
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  // Real data
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _favorites = [];
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _loadData();
    _connectivityService.onConnectivityChanged.listen((results) {
      final isOnline =
          !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (isOnline && (_hasConnectionError || _isOfflineCached)) {
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasConnectionError = false;
    });
    final offline = await _connectivityService.isOffline();
    if (offline) {
      await Future.delayed(const Duration(milliseconds: 400));
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
      final isLoggedIn = await NestAuthService.instance.isLoggedIn()
          .timeout(const Duration(seconds: 5));
      if (!isLoggedIn) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await ApiService.instance.client.get('/api/v1/orders');
      final rawList = response.data is List
          ? response.data as List
          : (response.data is Map
              ? (response.data['data'] as List? ?? [])
              : <dynamic>[]);

      if (mounted) {
        setState(() {
          _orders = rawList
              .whereType<Map>()
              .map((e) => _normalizeOrder(Map<String, dynamic>.from(e)))
              .toList();
          _favorites = [];
          _unreadNotifications = 0;
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasConnectionError = true;
        });
      }
    }
  }

  static String _formatPrice(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static Map<String, dynamic> _normalizeOrder(Map<String, dynamic> o) {
    final items = o['orderItems'] as List<dynamic>? ?? [];
    final firstItem =
        items.isNotEmpty ? items[0] as Map<String, dynamic>? : null;
    final product =
        (firstItem?['product'] ?? firstItem?['productDetails']) as Map? ?? {};

    final statusStr = (o['status'] as String? ?? '').toLowerCase();
    OrderStatus status;
    switch (statusStr) {
      case 'processing':
        status = OrderStatus.processing;
      case 'shipped':
        status = OrderStatus.inDelivery;
      case 'delivered':
        status = OrderStatus.confirmed;
      case 'completed':
        status = OrderStatus.completed;
      case 'cancelled':
        status = OrderStatus.cancelled;
      case 'failed':
        status = OrderStatus.failed;
      default:
        status = OrderStatus.received;
    }

    final steps = [
      true,
      ['processing', 'shipped', 'delivered', 'completed']
          .contains(statusStr),
      ['shipped', 'delivered', 'completed'].contains(statusStr),
      ['delivered', 'completed'].contains(statusStr),
      statusStr == 'completed',
    ];

    final amount = (o['totalAmount'] as num? ?? 0).toInt();
    final dateStr = o['createdAt'] as String? ?? '';
    String shortDate = '';
    if (dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr);
        shortDate =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {
        shortDate = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
      }
    }

    final rawId = (o['id'] ?? '').toString();
    final shortId = rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
    final imageUrl = product['imageUrl'] as String? ??
        product['image_url'] as String? ??
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
    final sellerName = (firstItem?['vendor'] as Map?)?['shopName'] as String? ??
        'Boutique Asoukaa';

    return {
      'id': '#ASK-$shortId',
      'product': product['name'] as String? ?? 'Produit',
      'seller': sellerName,
      'price': '${_formatPrice(amount)} FCFA',
      'image': imageUrl,
      'status': status,
      'steps': steps,
      'date': shortDate,
      'canReorder': status == OrderStatus.completed,
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
      bottomNavigationBar: isTablet
          ? null
          : AsoukaaBottomNav(
              currentIndex: _currentNavIndex,
              onTap: (i) {
                setState(() => _currentNavIndex = i);
                switch (i) {
                  case 0:
                    Navigator.pushReplacementNamed(context, '/home-screen');
                    break;
                  case 1:
                    Navigator.pushNamed(context, '/categories-screen');
                    break;
                  case 2:
                    Navigator.pushNamed(context, '/chat-screen');
                    break;
                  case 3:
                    // Already on buyer dashboard
                    break;
                  case 4:
                    Navigator.pushNamed(context, '/buyer-profile-screen');
                    break;
                }
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(114),
      child: Container(
        color: AppTheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      'Mon Tableau de Bord',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Icon(
                                Icons.notifications_outlined,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Wishlist button with count badge
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/wishlist-screen'),
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Center(
                              child: Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFDC2626),
                                size: 20,
                              ),
                            ),
                            if (_favorites.isNotEmpty)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    '${_favorites.length}',
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
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/buyer-profile-screen'),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildTabBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.outlineVariant, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.muted,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 2.5,
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tabs: const [
          Tab(text: 'Commandes'),
          Tab(text: 'Favoris'),
          Tab(text: 'Historique'),
          Tab(text: 'Notifications'),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const DashboardOrderSkeleton(),
      );
    }
    if (_hasConnectionError) {
      return ConnectionErrorScreen(
        onRetry: _loadData,
        title: 'Impossible de charger le tableau de bord',
        message: 'Vérifiez votre connexion internet et réessayez.',
      );
    }
    return Column(
      children: [
        if (_isOfflineCached) OfflineCachedBanner(onRetry: _loadData),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OrdersTab(orders: _orders),
              _FavoritesTab(favorites: _favorites),
              _OrderHistoryTab(history: _orders),
              _NotificationsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        AsoukaaNavigationRail(
          currentIndex: _currentNavIndex,
          onTap: (i) => setState(() => _currentNavIndex = i),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildPhoneLayout()),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ORDERS TAB
// ─────────────────────────────────────────────

class _OrdersTab extends StatelessWidget {
  final List<Map<String, dynamic>> orders;

  const _OrdersTab({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.shopping_bag_outlined,
        title: 'Aucune commande en cours',
        description:
            'Vous n\'avez pas encore de commandes actives. Explorez notre catalogue et passez votre première commande !',
        ctaLabel: 'Explorer les produits',
        onCtaTap: () => Navigator.pushNamed(context, '/categories-screen'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ImportAssisteCard();
        }
        final order = orders[index - 1];
        return _OrderCard(order: order);
      },
    );
  }
}

class _ImportAssisteCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImportAssisteScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6210).withAlpha(50),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.flight_land_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import Assisté',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Importez n\'importe quel produit depuis l\'étranger',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white.withAlpha(200),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Demander',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as OrderStatus;
    final steps = order['steps'] as List<bool>;
    final isCancelled =
        status == OrderStatus.cancelled || status == OrderStatus.failed;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Text(
                  order['id'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const Spacer(),
                StatusBadgeWidget.fromOrderStatus(status),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.outlineVariant),
          // Product row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    order['image'] as String,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 64,
                      color: AppTheme.surfaceVariant,
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['product'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order['seller'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order['price'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tracking stepper (only for non-cancelled)
          if (!isCancelled) ...[
            const Divider(height: 1, color: AppTheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: _OrderTracker(steps: steps),
            ),
          ],
          if (isCancelled) ...[
            const Divider(height: 1, color: AppTheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppTheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status == OrderStatus.cancelled
                        ? 'Commande annulée le ${order['date']}'
                        : 'Livraison échouée — contactez le vendeur',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderTracker extends StatelessWidget {
  final List<bool> steps;

  const _OrderTracker({required this.steps});

  static const List<String> _labels = [
    'Reçue',
    'Traitement',
    'Livraison',
    'Confirmée',
    'Terminée',
  ];

  static const List<IconData> _icons = [
    Icons.inbox_rounded,
    Icons.settings_rounded,
    Icons.local_shipping_rounded,
    Icons.check_circle_rounded,
    Icons.done_all_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suivi de commande',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(steps.length, (i) {
            final isDone = steps[i];
            final isActive = i < steps.length - 1 && isDone && !steps[i + 1];
            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppTheme.primary
                                : isActive
                                ? AppTheme.primaryMuted
                                : AppTheme.outlineVariant,
                            shape: BoxShape.circle,
                            border: isActive
                                ? Border.all(color: AppTheme.primary, width: 2)
                                : null,
                          ),
                          child: Icon(
                            _icons[i],
                            size: 14,
                            color: isDone
                                ? Colors.white
                                : isActive
                                ? AppTheme.primary
                                : AppTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _labels[i],
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: isDone
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isDone ? AppTheme.primary : AppTheme.muted,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: steps[i] && steps[i + 1]
                              ? AppTheme.primary
                              : steps[i]
                              ? AppTheme.primaryMuted
                              : AppTheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// FAVORITES TAB
// ─────────────────────────────────────────────

class _FavoritesTab extends StatefulWidget {
  final List<Map<String, dynamic>> favorites;

  const _FavoritesTab({required this.favorites});

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  late List<Map<String, dynamic>> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = List.from(widget.favorites);
  }

  @override
  Widget build(BuildContext context) {
    if (_favorites.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        title: 'Aucun favori pour l\'instant',
        description:
            'Ajoutez des produits à vos favoris pour les retrouver facilement.',
        ctaLabel: 'Explorer les produits',
        onCtaTap: () => Navigator.pushNamed(context, '/categories-screen'),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final item = _favorites[index];
        return _FavoriteCard(
          item: item,
          onRemove: () => setState(() => _favorites.removeAt(index)),
        );
      },
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  const _FavoriteCard({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final inStock = item['inStock'] as bool;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Image.network(
                  item['image'] as String,
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 130,
                    color: AppTheme.surfaceVariant,
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(230),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              if (!inStock)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Rupture de stock',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  item['seller'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Color(0xFFFFB800),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${item['rating']}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item['price'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ORDER HISTORY TAB
// ─────────────────────────────────────────────

class _OrderHistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const _OrderHistoryTab({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'Aucun historique',
        description: 'Vos commandes passées apparaîtront ici.',
        ctaLabel: 'Explorer les produits',
        onCtaTap: () => Navigator.pushNamed(context, '/categories-screen'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = history[index];
        return _HistoryCard(item: item);
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as OrderStatus;
    final canReorder = item['canReorder'] as bool;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              item['image'] as String,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 60,
                height: 60,
                color: AppTheme.surfaceVariant,
                child: const Icon(Icons.image_outlined, color: AppTheme.muted),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['product'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusBadgeWidget.fromOrderStatus(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['id']}  ·  ${item['date']}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      item['price'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (canReorder)
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryMuted,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Recommander',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
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
    );
  }
}

// ─────────────────────────────────────────────
// NOTIFICATIONS TAB
// ─────────────────────────────────────────────

class _NotificationsTab extends StatefulWidget {
  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  // 🔧 FIX: Must NOT be const — items are mutated (isRead toggled at runtime).
  // A const List contains unmodifiable Maps; writing n['isRead'] = true throws
  // "Cannot modify an unmodifiable map" at runtime.
  final List<Map<String, dynamic>> _notifications = [
    {
      'icon': Icons.local_shipping_rounded,
      'iconColor': AppTheme.primary,
      'iconBg': AppTheme.primaryMuted,
      'title': 'Commande en livraison',
      'body':
          'Votre commande #ASK-2024-001 est en route. Livraison prévue aujourd\'hui.',
      'time': 'Il y a 2h',
      'isRead': false,
    },
    {
      'icon': Icons.check_circle_rounded,
      'iconColor': AppTheme.success,
      'iconBg': AppTheme.successContainer,
      'title': 'Paiement confirmé',
      'body':
          'Votre paiement de 28 500 FCFA pour la commande #ASK-2024-002 a été accepté.',
      'time': 'Il y a 5h',
      'isRead': false,
    },
    {
      'icon': Icons.local_offer_rounded,
      'iconColor': const Color(0xFFD97706),
      'iconBg': const Color(0xFFFEF3C7),
      'title': 'Promotion Flash !',
      'body':
          'Boutique Cotonou Mode offre -20% sur tous les boubous jusqu\'à minuit.',
      'time': 'Hier',
      'isRead': true,
    },
    {
      'icon': Icons.star_rounded,
      'iconColor': const Color(0xFFFFB800),
      'iconBg': const Color(0xFFFFFBEB),
      'title': 'Donnez votre avis',
      'body':
          'Votre commande #ASK-2023-089 est terminée. Partagez votre expérience !',
      'time': 'Il y a 3 jours',
      'isRead': true,
    },
    {
      'icon': Icons.cancel_rounded,
      'iconColor': AppTheme.error,
      'iconBg': AppTheme.errorContainer,
      'title': 'Commande annulée',
      'body':
          'La commande #ASK-2024-004 a été annulée. Le remboursement sera traité sous 48h.',
      'time': 'Il y a 5 jours',
      'isRead': true,
    },
    {
      'icon': Icons.inventory_2_rounded,
      'iconColor': const Color(0xFF7C3AED),
      'iconBg': const Color(0xFFEDE9FE),
      'title': 'Commande reçue',
      'body': 'Votre commande #ASK-2024-003 a bien été reçue par le vendeur.',
      'time': 'Il y a 1 semaine',
      'isRead': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((n) => !(n['isRead'] as bool))
        .length;

    return Column(
      children: [
        // "Voir tout" link to full notifications screen
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Centre de notifications',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (unreadCount > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$unreadCount nouvelle${unreadCount > 1 ? 's' : ''} notification${unreadCount > 1 ? 's' : ''}',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    for (final n in _notifications) {
                      n['isRead'] = true;
                    }
                  }),
                  child: Text(
                    'Tout lire',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final notif = _notifications[index];
              return _NotificationCard(
                notif: notif,
                onTap: () => setState(() => notif['isRead'] = true),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;

  const _NotificationCard({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRead = notif['isRead'] as bool;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppTheme.surface : AppTheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          border: isRead
              ? null
              : Border.all(color: AppTheme.primaryMuted, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: notif['iconBg'] as Color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                notif['icon'] as IconData,
                size: 20,
                color: notif['iconColor'] as Color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif['title'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: isRead
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif['body'] as String,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notif['time'] as String,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppTheme.muted,
                    ),
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
