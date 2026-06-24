import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:feexpay_flutter/feexpay_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/status_badge_widget.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentNavIndex = 3; // Dashboard tab active for seller
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  // Real data
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _shop;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
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
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic>? shop;
      List<Map<String, dynamic>> products = [];
      List<Map<String, dynamic>> orders = [];

      try {
        final r = await ApiService.instance.client.get('/api/v1/shops/mine');
        shop = Map<String, dynamic>.from(r.data as Map);
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/products/mine');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        products = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/orders/mine');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        orders = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _shop = shop;
          _products = products;
          _orders = orders;
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
      }
    }
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
                    Navigator.pushNamed(
                      context,
                      AppRoutes.searchResults,
                      arguments: '',
                    );
                    break;
                  case 2:
                    Navigator.pushNamed(context, '/chat-screen');
                    break;
                  case 3:
                    // Already on seller dashboard
                    break;
                  case 4:
                    Navigator.pushNamed(context, AppRoutes.sellerProfile);
                    break;
                }
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(104),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Espace Vendeur',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Boutique Cotonou Mode',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Actif',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.storefront_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppRoutes.sellerProfile,
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
          Tab(text: 'Produits'),
          Tab(text: 'Commandes'),
          Tab(text: 'Devis'),
          Tab(text: 'Stock'),
          Tab(text: 'Revenus'),
          Tab(text: 'Retrait'),
          Tab(text: 'Statistiques'),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const DashboardProductSkeleton(),
      );
    }
    if (_hasConnectionError) {
      return ConnectionErrorScreen(
        onRetry: _loadData,
        title: 'Impossible de charger l\'espace vendeur',
        message: 'Vérifiez votre connexion internet et réessayez.',
      );
    }
    if (_isOfflineCached) {
      return Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ProduitsTab(products: _products),
                _CommandesTab(orders: _orders),
                const _DevisTab(),
                const _StockTab(),
                const _RevenusTab(),
                const _RetraitTab(),
                _SellerStatsTab(shop: _shop, products: _products),
              ],
            ),
          ),
        ],
      );
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _ProduitsTab(products: _products),
        _CommandesTab(orders: _orders),
        const _DevisTab(),
        const _StockTab(),
        const _RevenusTab(),
        const _RetraitTab(),
        _SellerStatsTab(shop: _shop, products: _products),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        AsoukaaNavigationRail(
          currentIndex: _currentNavIndex,
          onTap: (i) {
            setState(() => _currentNavIndex = i);
            if (i == 0) Navigator.pushReplacementNamed(context, '/home-screen');
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildPhoneLayout()),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// PRODUITS TAB
// ─────────────────────────────────────────────

class _ProduitsTab extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  const _ProduitsTab({this.products = const []});

  @override
  State<_ProduitsTab> createState() => _ProduitsTabState();
}

class _ProduitsTabState extends State<_ProduitsTab> {
  String _filter = 'Tous';
  late List<Map<String, dynamic>> _products;

  @override
  void initState() {
    super.initState();
    _products = List.from(widget.products);
  }

  @override
  void didUpdateWidget(_ProduitsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) {
      setState(() => _products = List.from(widget.products));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Publiés') {
      return _products.where((p) => p['is_active'] == true).toList();
    }
    if (_filter == 'Brouillons') {
      return _products.where((p) => p['is_active'] == false).toList();
    }
    return _products;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildFilterChips(),
        Expanded(
          child: _filtered.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucun produit trouvé',
                  description: _filter == 'Tous'
                      ? 'Vous n\'avez pas encore ajouté de produits. Commencez à vendre dès maintenant !'
                      : 'Aucun produit dans la catégorie "$_filter".',
                  ctaLabel: _filter == 'Tous' ? 'Ajouter un produit' : null,
                  onCtaTap: _filter == 'Tous'
                      ? () => Navigator.pushNamed(
                          context,
                          AppRoutes.publierProduit,
                        )
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _ProductCard(
                    product: _filtered[index],
                    onTogglePublish: () {
                      setState(() {
                        final idx = _products.indexWhere(
                          (p) => p['id'] == _filtered[index]['id'],
                        );
                        if (idx != -1) {
                          _products[idx]['status'] =
                              _products[idx]['status'] == 'published'
                              ? 'draft'
                              : 'published';
                        }
                      });
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_products.length} produits',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '${_products.where((p) => p['status'] == 'published').length} publiés · ${_products.where((p) => p['status'] == 'draft').length} brouillons',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.publierProduit),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Ajouter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: ['Tous', 'Publiés', 'Brouillons'].map((f) {
          final isSelected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryMuted
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showAddProductSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddProductSheet(),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTogglePublish;

  const _ProductCard({required this.product, required this.onTogglePublish});

  @override
  Widget build(BuildContext context) {
    final isPublished = product['status'] == 'published';
    final isOutOfStock = product['stock'] == 0;

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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                product['image'],
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 72,
                  height: 72,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product['name'],
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(isPublished: isPublished),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product['price'],
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniStat(
                        icon: Icons.inventory_2_outlined,
                        value: '${product['stock']} en stock',
                        color: isOutOfStock
                            ? AppTheme.error
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      _MiniStat(
                        icon: Icons.visibility_outlined,
                        value: '${product['views']}',
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      _MiniStat(
                        icon: Icons.shopping_bag_outlined,
                        value: '${product['sales']} ventes',
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.edit_outlined,
                        label: 'Modifier',
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _ActionBtn(
                        icon: isPublished
                            ? Icons.visibility_off_outlined
                            : Icons.publish_rounded,
                        label: isPublished ? 'Dépublier' : 'Publier',
                        onTap: onTogglePublish,
                        isPrimary: !isPublished,
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

class _StatusChip extends StatelessWidget {
  final bool isPublished;
  const _StatusChip({required this.isPublished});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isPublished
            ? AppTheme.successContainer
            : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPublished ? 'Publié' : 'Brouillon',
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPublished ? AppTheme.success : AppTheme.muted,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(value, style: GoogleFonts.outfit(fontSize: 11, color: color)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primaryMuted : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isPrimary ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isPrimary ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProductSheet extends StatefulWidget {
  const _AddProductSheet();

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nouveau Produit',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nom du produit'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stock initial'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Enregistrer le produit'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// COMMANDES TAB
// ─────────────────────────────────────────────

class _CommandesTab extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  const _CommandesTab({this.orders = const []});

  @override
  State<_CommandesTab> createState() => _CommandesTabState();
}

class _CommandesTabState extends State<_CommandesTab> {
  String _filter = 'Toutes';
  late List<Map<String, dynamic>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = List.from(widget.orders);
  }

  @override
  void didUpdateWidget(_CommandesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orders != widget.orders) {
      setState(() => _orders = List.from(widget.orders));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'En cours':
        return _orders.where((o) {
          final s = o['status'] as String? ?? '';
          return s == 'confirme' ||
              s == 'en_preparation' ||
              s == 'en_livraison' ||
              s == 'expedie';
        }).toList();
      case 'Terminées':
        return _orders
            .where((o) => (o['status'] as String? ?? '') == 'livre')
            .toList();
      case 'Annulées':
        return _orders.where((o) {
          final s = o['status'] as String? ?? '';
          return s == 'annule' || s == 'rembourse';
        }).toList();
      default:
        return _orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSummaryRow(),
        _buildFilterRow(),
        // Add "Initier une commande" button for sellers
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showInitiateOrderDialog(context),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
              label: Text(
                'Initier une commande pour un client',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.inbox_outlined,
                  title: 'Aucune commande',
                  description: 'Aucune commande dans cette catégorie',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _SellerOrderCard(order: _filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow() {
    final pending = _orders
        .where(
          (o) =>
              o['status'] == OrderStatus.received ||
              o['status'] == OrderStatus.processing,
        )
        .length;
    final inDelivery = _orders
        .where((o) => o['status'] == OrderStatus.inDelivery)
        .length;
    final completed = _orders
        .where((o) => o['status'] == OrderStatus.completed)
        .length;

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          _SummaryPill(
            label: 'En attente',
            count: pending,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          _SummaryPill(
            label: 'En livraison',
            count: inDelivery,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          _SummaryPill(
            label: 'Terminées',
            count: completed,
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: ['Toutes', 'En cours', 'Terminées', 'Annulées'].map((f) {
          final isSelected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryMuted
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showInitiateOrderDialog(BuildContext context) {
    final clientNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final productCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Initier une commande',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Créez une commande pour un client',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: clientNameCtrl,
              decoration: InputDecoration(
                labelText: 'Nom du client',
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: InputDecoration(
                labelText: 'Adresse de livraison',
                prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: productCtrl,
              decoration: InputDecoration(
                labelText: 'Produit(s) commandé(s)',
                prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Montant total (FCFA)',
                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Commande créée pour ${clientNameCtrl.text}',
                        style: GoogleFonts.outfit(color: Colors.white),
                      ),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Créer la commande',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryPill({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(fontSize: 11, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _SellerOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as OrderStatus;

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
        border:
            status == OrderStatus.received || status == OrderStatus.processing
            ? Border.all(color: AppTheme.warning.withAlpha(60))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                StatusBadgeWidget.fromOrderStatus(status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    order['image'],
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: AppTheme.surfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['product'],
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Acheteur: ${order['buyer']}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qté: ${order['qty']} · ${order['date']}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  order['price'],
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            if (status == OrderStatus.received ||
                status == OrderStatus.processing) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: const BorderSide(color: AppTheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Détails',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Confirmer',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DEVIS TAB
// ─────────────────────────────────────────────

class _DevisTab extends StatefulWidget {
  const _DevisTab();

  @override
  State<_DevisTab> createState() => _DevisTabState();
}

class _DevisTabState extends State<_DevisTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];
  String _filter = 'Tous';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final r = await ApiService.instance.client.get('/api/v1/import-requests');
      final raw = r.data;
      final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
      if (mounted) {
        setState(() {
          _requests = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'En attente':
        return _requests.where((r) => r['status'] == 'pending').toList();
      case 'Approuvés':
        return _requests.where((r) => r['status'] == 'approved').toList();
      case 'Rejetés':
        return _requests.where((r) => r['status'] == 'rejected').toList();
      default:
        return _requests;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        _buildFilterChips(),
        Expanded(
          child: _filtered.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.description_outlined,
                  title: 'Aucun devis',
                  description: _filter == 'Tous'
                      ? 'Aucune demande de sourcing reçue pour l\'instant.'
                      : 'Aucun devis dans la catégorie "$_filter".',
                )
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _loadRequests,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _DevisCard(
                      request: _filtered[i],
                      onStatusChanged: _loadRequests,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final pending = _requests.where((r) => r['status'] == 'pending').length;
    final approved = _requests.where((r) => r['status'] == 'approved').length;
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          _SummaryPill(
            label: 'En attente',
            count: pending,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          _SummaryPill(
            label: 'Approuvés',
            count: approved,
            color: AppTheme.success,
          ),
          const SizedBox(width: 8),
          _SummaryPill(
            label: 'Total',
            count: _requests.length,
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: ['Tous', 'En attente', 'Approuvés', 'Rejetés'].map((f) {
          final isSelected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryMuted
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DevisCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onStatusChanged;

  const _DevisCard({required this.request, required this.onStatusChanged});

  @override
  State<_DevisCard> createState() => _DevisCardState();
}

class _DevisCardState extends State<_DevisCard> {
  bool _isUpdating = false;
  final _devisAmountCtrl = TextEditingController();
  final _devisNoteCtrl = TextEditingController();

  @override
  void dispose() {
    _devisAmountCtrl.dispose();
    _devisNoteCtrl.dispose();
    super.dispose();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.success;
      case 'rejected':
        return AppTheme.error;
      case 'completed':
        return const Color(0xFF7C3AED);
      default:
        return AppTheme.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approuvé';
      case 'rejected':
        return 'Rejeté';
      case 'completed':
        return 'Terminé';
      default:
        return 'En attente';
    }
  }

  Future<void> _sendDevis() async {
    if (_devisAmountCtrl.text.trim().isEmpty) return;
    setState(() => _isUpdating = true);
    try {
      final amount = double.tryParse(_devisAmountCtrl.text.trim()) ?? 0;
      await ApiService.instance.client.patch(
        '/api/v1/import-requests/${widget.request['id']}',
        data: {
          'status': 'approved',
          'devisAmount': amount,
          'devisNote': _devisNoteCtrl.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onStatusChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Devis envoyé avec succès',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de l\'envoi du devis',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showDevisDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Envoyer un devis',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Le client recevra le devis dans son compte et par email.',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _devisAmountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Montant total du devis (FCFA)',
                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                helperText:
                    'Le dépôt de 10 000 FCFA sera déduit du montant final',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _devisNoteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Note / Détails du devis',
                hintText:
                    'Décrivez le produit trouvé, délai de livraison, conditions...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isUpdating ? null : _sendDevis,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  'Envoyer le devis',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final status = r['status'] as String? ?? 'pending';
    final depositPaid = r['deposit_paid'] as bool? ?? false;
    final devisAmount = (r['devis_amount'] as num?)?.toDouble();
    final depositAmount = (r['deposit_amount'] as num?)?.toDouble() ?? 10000;

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
        border: status == 'pending'
            ? Border.all(color: AppTheme.warning.withAlpha(60))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    r['description'] as String? ?? 'Demande de sourcing',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Details
            if (r['product_url'] != null &&
                (r['product_url'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      size: 14,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r['product_url'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Quantité: ${r['quantity'] ?? 1}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDate(r['created_at'] as String?),
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            if (r['specs'] != null && (r['specs'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: AppTheme.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r['specs'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // Payment status
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        depositPaid
                            ? Icons.check_circle_rounded
                            : Icons.pending_rounded,
                        size: 16,
                        color: depositPaid
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Dépôt ${depositAmount.toStringAsFixed(0)} FCFA: ${depositPaid ? 'Payé ✓' : 'En attente'}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: depositPaid
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                  if (devisAmount != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Devis envoyé: ${devisAmount.toStringAsFixed(0)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Reste: ${(devisAmount - depositAmount).toStringAsFixed(0)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        setState(() => _isUpdating = true);
                        try {
                          await ApiService.instance.client.patch(
                            '/api/v1/import-requests/${r['id']}',
                            data: {'status': 'rejected'},
                          );
                          widget.onStatusChanged();
                        } catch (_) {}
                        if (mounted) setState(() => _isUpdating = false);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: const BorderSide(color: AppTheme.error),
                        foregroundColor: AppTheme.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Rejeter',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showDevisDialog,
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: Text(
                        'Envoyer devis',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (status == 'approved' && !depositPaid) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warning.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'En attente du paiement du dépôt par le client',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STOCK TAB
// ─────────────────────────────────────────────

class _StockTab extends StatefulWidget {
  const _StockTab();

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  final List<Map<String, dynamic>> _items = [];

  @override
  Widget build(BuildContext context) {
    final outOfStock = _items.where((i) => i['stock'] == 0).length;
    final lowStock = _items
        .where((i) => i['stock'] > 0 && i['stock'] <= i['minStock'])
        .length;

    return Column(
      children: [
        _buildStockAlerts(outOfStock, lowStock),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _StockItem(
              item: _items[i],
              onUpdate: (newQty) => setState(() => _items[i]['stock'] = newQty),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockAlerts(int outOfStock, int lowStock) {
    if (outOfStock == 0 && lowStock == 0) return const SizedBox.shrink();
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (outOfStock > 0)
            _AlertBanner(
              icon: Icons.warning_amber_rounded,
              message: '$outOfStock produit(s) en rupture de stock',
              color: AppTheme.error,
              bgColor: AppTheme.errorContainer,
            ),
          if (outOfStock > 0 && lowStock > 0) const SizedBox(height: 8),
          if (lowStock > 0)
            _AlertBanner(
              icon: Icons.info_outline_rounded,
              message: '$lowStock produit(s) avec stock faible',
              color: AppTheme.warning,
              bgColor: AppTheme.warningContainer,
            ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color bgColor;
  const _AlertBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final ValueChanged<int> onUpdate;
  const _StockItem({required this.item, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final stock = item['stock'] as int;
    final minStock = item['minStock'] as int;
    final isOutOfStock = stock == 0;
    final isLow = stock > 0 && stock <= minStock;

    Color stockColor = AppTheme.success;
    if (isOutOfStock) {
      stockColor = AppTheme.error;
    } else if (isLow)
      stockColor = AppTheme.warning;

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
        border: isOutOfStock
            ? Border.all(color: AppTheme.error.withAlpha(60))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item['image'],
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: AppTheme.surfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'],
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SKU: ${item['sku']}',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stockColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOutOfStock ? 'Rupture' : '$stock unités',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: stockColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Min: $minStock',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                GestureDetector(
                  onTap: () => onUpdate(stock + 1),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$stock',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    if (stock > 0) onUpdate(stock - 1);
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: stock > 0
                          ? AppTheme.surfaceVariant
                          : AppTheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 16,
                      color: stock > 0
                          ? AppTheme.textSecondary
                          : AppTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// REVENUS TAB
// ─────────────────────────────────────────────

class _RevenusTab extends StatelessWidget {
  const _RevenusTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EarningsSummaryCard(),
          const SizedBox(height: 16),
          _MonthlyBreakdown(),
          const SizedBox(height: 16),
          _RecentTransactions(),
        ],
      ),
    );
  }
}

class _EarningsSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Revenus du mois',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white.withAlpha(200),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Mars 2026',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '342 500 FCFA',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                '+18% vs mois dernier',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white.withAlpha(200),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _EarningsStat(
                label: 'Ventes',
                value: '45',
                icon: Icons.shopping_bag_outlined,
              ),
              _EarningsStat(
                label: 'Commissions',
                value: '-34 250 FCFA',
                icon: Icons.percent_rounded,
              ),
              _EarningsStat(
                label: 'Net',
                value: '308 250 FCFA',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _EarningsStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.white.withAlpha(180)),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: Colors.white.withAlpha(180),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MonthlyBreakdown extends StatelessWidget {
  final List<Map<String, dynamic>> _months = const [
    {'month': 'Jan', 'amount': 185000, 'max': 400000},
    {'month': 'Fév', 'amount': 290000, 'max': 400000},
    {'month': 'Mar', 'amount': 342500, 'max': 400000},
  ];

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évolution mensuelle',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _months.map((m) {
              final ratio = (m['amount'] as int) / (m['max'] as int);
              final isLatest = m['month'] == 'Mar';
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      Text(
                        '${((m['amount'] as int) / 1000).toStringAsFixed(0)}k',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isLatest
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 80 * ratio,
                        decoration: BoxDecoration(
                          color: isLatest
                              ? AppTheme.primary
                              : AppTheme.primaryMuted,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m['month'],
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  final List<Map<String, dynamic>> _transactions = const [
    {
      'id': '#ASK-2024-103',
      'product': 'Sac Raphia Tressé',
      'amount': '+12 000 FCFA',
      'date': '17 mars',
      'type': 'credit',
    },
    {
      'id': '#ASK-2024-102',
      'product': 'Tissu Wax x2',
      'amount': '+57 000 FCFA',
      'date': '18 mars',
      'type': 'credit',
    },
    {
      'id': 'COM-MAR-001',
      'product': 'Commission Asoukaa',
      'amount': '-8 550 FCFA',
      'date': '18 mars',
      'type': 'debit',
    },
    {
      'id': '#ASK-2024-101',
      'product': 'Boubou Brodé Premium',
      'amount': '+45 000 FCFA',
      'date': '19 mars',
      'type': 'credit',
    },
  ];

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions récentes',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._transactions.map((t) => _TransactionRow(transaction: t)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> transaction;
  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction['type'] == 'credit';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCredit
                  ? AppTheme.successContainer
                  : AppTheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 16,
              color: isCredit ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction['product'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  transaction['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                transaction['amount'],
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isCredit ? AppTheme.success : AppTheme.error,
                ),
              ),
              Text(
                transaction['date'],
                style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// RETRAIT TAB
// ─────────────────────────────────────────────

class _RetraitTab extends StatefulWidget {
  const _RetraitTab();

  @override
  State<_RetraitTab> createState() => _RetraitTabState();
}

class _RetraitTabState extends State<_RetraitTab> {
  final _amountController = TextEditingController();
  final bool _isLoading = false;

  static const String _feexpayToken = String.fromEnvironment('FEEXPAY_API_KEY');
  static const String _feexpayShopId = String.fromEnvironment(
    'FEEXPAY_SHOP_ID',
  );

  final List<Map<String, dynamic>> _history = [
    {
      'amount': '150 000 FCFA',
      'method': 'FeeXPay',
      'date': '10 mars 2026',
      'status': 'completed',
    },
    {
      'amount': '80 000 FCFA',
      'method': 'FeeXPay',
      'date': '25 fév 2026',
      'status': 'completed',
    },
    {
      'amount': '200 000 FCFA',
      'method': 'FeeXPay',
      'date': '5 fév 2026',
      'status': 'completed',
    },
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 16),
          _buildWithdrawForm(),
          const SizedBox(height: 20),
          Text(
            'Historique des retraits',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._history.map((h) => _WithdrawalHistoryItem(item: h)),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.secondary,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde disponible',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white.withAlpha(160),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '308 250 FCFA',
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BalanceStat(label: 'En attente', value: '45 000 FCFA'),
              const SizedBox(width: 24),
              _BalanceStat(label: 'Total retiré', value: '430 000 FCFA'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawForm() {
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nouveau retrait',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // FeeXPay provider banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF112C56).withAlpha(12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF112C56).withAlpha(40)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF112C56).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.payment_rounded,
                    color: Color(0xFF112C56),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FeeXPay',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF112C56),
                        ),
                      ),
                      Text(
                        'Orange Money · Wave · Moov · Carte',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        size: 12,
                        color: AppTheme.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Actif',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Montant à retirer (FCFA)',
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              labelStyle: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: const Color(0xFF112C56),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Montant minimum: 5 000 FCFA · Délai: 24-48h',
            style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleWithdraw,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF112C56),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_rounded, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Retrait via FeeXPay',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _generateTransKey() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'RET${ts.substring(ts.length - 12)}';
  }

  void _handleWithdraw() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return;
    final amount = int.tryParse(text.replaceAll(' ', ''));
    if (amount == null || amount < 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Montant minimum: 5 000 FCFA',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final token = _feexpayToken.isNotEmpty
        ? _feexpayToken
        : 'fp_8Q22dR4r5omd6bBonmqjicDDzkuE3Vgg49bkWVuRvFKZbM4iG5BlcIa45lYocd2Y';
    final shopId = _feexpayShopId.isNotEmpty
        ? _feexpayShopId
        : '6787b9c315c7bc2e9dbb906a';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChoicePage(
          token: token,
          id: shopId,
          amount: amount.toString(),
          redirecturl: AppRoutes.feexpaySuccess,
          errorredirecturl: AppRoutes.feexpayError,
          trans_key: _generateTransKey(),
        ),
      ),
    );
    _amountController.clear();
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  const _BalanceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: Colors.white.withAlpha(140),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _WithdrawalHistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _WithdrawalHistoryItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.successContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['method'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  item['date'],
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item['amount'],
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                'Effectué',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATISTIQUES TAB
// ─────────────────────────────────────────────

class _SellerStatsTab extends StatelessWidget {
  final Map<String, dynamic>? shop;
  final List<Map<String, dynamic>> products;
  const _SellerStatsTab({this.shop, required this.products});

  @override
  Widget build(BuildContext context) {
    final totalViews = products.fold<int>(
      0,
      (sum, p) => sum + ((p['views'] as num?)?.toInt() ?? 0),
    );
    final totalSales = products.fold<int>(
      0,
      (sum, p) =>
          sum +
          ((p['sales'] as num?)?.toInt() ??
              (p['sold_count'] as num?)?.toInt() ??
              0),
    );
    // Simulated shop visitor count (would come from analytics in production)
    final shopVisitors =
        (shop?['visitor_count'] as num?)?.toInt() ?? (totalViews * 3 ~/ 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shop stats header
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF112C56), Color(0xFF1E3A6E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Statistiques Boutique',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Mars 2026',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatPill(
                      label: 'Visiteurs boutique',
                      value: '$shopVisitors',
                      icon: Icons.store_rounded,
                      color: const Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 12),
                    _StatPill(
                      label: 'Vues produits',
                      value: '$totalViews',
                      icon: Icons.visibility_rounded,
                      color: const Color(0xFF34D399),
                    ),
                    const SizedBox(width: 12),
                    _StatPill(
                      label: 'Ventes',
                      value: '$totalSales',
                      icon: Icons.shopping_bag_rounded,
                      color: const Color(0xFFFBBF24),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Vues par produit',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Aucun produit publié',
                  style: GoogleFonts.outfit(color: AppTheme.muted),
                ),
              ),
            )
          else
            ...products.take(10).map((p) {
              final views = (p['views'] as num?)?.toInt() ?? 0;
              final sales =
                  (p['sales'] as num?)?.toInt() ??
                  (p['sold_count'] as num?)?.toInt() ??
                  0;
              final maxViews = products.fold<int>(
                1,
                (m, prod) => (((prod['views'] as num?)?.toInt() ?? 0) > m)
                    ? ((prod['views'] as num?)?.toInt() ?? 0)
                    : m,
              );
              final ratio = maxViews > 0 ? views / maxViews : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(6),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p['name'] as String? ?? 'Produit',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.visibility_outlined,
                              size: 13,
                              color: AppTheme.muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$views vues',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppTheme.muted,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.shopping_bag_outlined,
                              size: 13,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$sales vendus',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio.toDouble(),
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF6210),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white.withAlpha(180),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
