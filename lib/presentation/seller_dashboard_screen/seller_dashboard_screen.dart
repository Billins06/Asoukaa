import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../../services/upload_service.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/status_badge_widget.dart';
import '../../routes/app_routes.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/nest_auth_service.dart';
import '../../services/mode_service.dart';
import '../../services/api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/delivery_selector_widget.dart';
import '../../services/delivery_zone_service.dart';
import '../../utils/telephone.dart';

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
    // Ouvrir l'espace vendeur = être en mode vendeur (mémorisé pour la prochaine ouverture).
    ModeService.instance.setLastMode(ModeService.vendeur);
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

  static String _formatPrice(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatShortDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  // Le backend renvoie le statut en français ('en attente', 'en cours',
  // 'expedié', 'livré', 'annulé') — même mapping que buyer_dashboard_screen.
  static OrderStatus _mapOrderStatus(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'en cours':
        return OrderStatus.processing;
      case 'livreur affecté':
      case 'expedié':
      case 'en transit':
        return OrderStatus.inDelivery;
      case 'livré':
        return OrderStatus.completed;
      case 'annulé':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.received;
    }
  }

  // Traduit un Product du backend (prod_name, basePrice, images[], variants[]...)
  // vers les clés attendues par _ProductCard (name, price, image, stock, views, sales, status, is_active).
  static Map<String, dynamic> _normalizeSellerProduct(Map<String, dynamic> p) {
    final images = (p['images'] as List?)?.whereType<Map>().toList() ?? [];
    final imageUrl = images.isNotEmpty ? (images.first['url'] as String? ?? '') : '';
    final variants = (p['variants'] as List?)?.whereType<Map>().toList() ?? [];
    final stock = variants.fold<int>(
      0,
      (sum, v) => sum + ((v['stockQuantity'] as num?)?.toInt() ?? 0),
    );
    final rawStatus = (p['status'] as String? ?? '');
    final isActive = rawStatus == 'active';
    // On garde les 4 statuts backend distincts (avant, tout ce qui
    // n'etait pas 'active' devenait 'draft'), donc un produit desactive
    // ('inactive') apparaissait a tort dans l'onglet "Brouillons".
    final normalizedStatus = switch (rawStatus) {
      'active' => 'published',
      'inactive' => 'unpublished',
      'out_of_stock' => 'out_of_stock',
      _ => 'draft',
    };
    final rawPrice = p['basePrice'];
    final amount = rawPrice is num
        ? rawPrice.round()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 0).round();
    // Paliers degressifs bruts {minQuantity, price} (int), meme logique que
    // product_detail_screen.dart (variable parsedTiers) -- utilises par
    // unitPriceForProduct() dans _showInitiateOrderDialog pour calculer le
    // prix unitaire reel selon la quantite choisie par le vendeur.
    final rawTiers = p['tierPrices'];
    final List<Map<String, int>> tierPrices = [];
    if (rawTiers is List) {
      for (final t in rawTiers) {
        if (t is! Map) continue;
        final minQty = int.tryParse('${t['minQuantity'] ?? ''}');
        final tierPrice = double.tryParse('${t['price'] ?? ''}');
        if (minQty == null || minQty < 1) continue;
        if (tierPrice == null || tierPrice <= 0) continue;
        tierPrices.add({'minQuantity': minQty, 'price': tierPrice.round()});
      }
    }
    tierPrices.sort((a, b) => a['minQuantity']!.compareTo(b['minQuantity']!));
    return {
      'id': (p['id'] ?? '').toString(),
      'name': p['prod_name'] as String? ?? 'Produit',
      'price': '${_formatPrice(amount)} FCFA',
      // Prix de base numérique (avant paliers dégressifs), utilisé par le
      // formulaire "Initier une commande" pour calculer le total en direct
      // (voir _unitPriceForQty dans _showInitiateOrderDialog).
      'rawPrice': amount,
      'tierPrices': tierPrices,
      'image': imageUrl,
      'stock': stock,
      // Compteur de vues réel : colonne products."nombreVues", incrémentée
      // à chaque ouverture d'une fiche produit (GET /products/:id).
      'views': (p['nombreVues'] as num?)?.toInt() ?? 0,
      // Quantité réellement vendue, incrémentée au passage d'une commande
      // au statut "livré" (avant, cette valeur restait figée à zéro).
      'sales': (p['totalVentes'] as num?)?.toInt() ?? 0,
      'status': normalizedStatus,
      'is_active': isActive,
      // Variante par défaut utilisée pour "Initier une commande pour un
      // client" (POST /orders/vendor-initiated attend un variantId, pas un
      // productId — c'est la variante qui porte le stock et le prix réel).
      'variantId': variants.isNotEmpty ? (variants.first['id'] ?? '').toString() : '',
    };
  }

  // Traduit un Order du backend (items[]->variant->product, address, total...)
  // vers les clés attendues par _SellerOrderCard (id, status, image, product, buyer, qty, date, price).
  static Map<String, dynamic> _normalizeSellerOrder(Map<String, dynamic> o) {
    final items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final first = items.isNotEmpty ? items.first : null;
    final variant = first?['variant'] as Map<String, dynamic>?;
    final product = variant?['product'] as Map<String, dynamic>?;
    final images = (product?['images'] as List?)?.whereType<Map>().toList() ?? [];
    final imageUrl = images.isNotEmpty ? (images.first['url'] as String? ?? '') : '';
    final address = o['address'] as Map<String, dynamic>?;
    final qty = items.fold<int>(
      0,
      (s, it) => s + ((it['quantity'] as num?)?.toInt() ?? 0),
    );
    final rawTotal = o['total'];
    final amount = rawTotal is num
        ? rawTotal.round()
        : (double.tryParse(rawTotal?.toString() ?? '') ?? 0).round();
    // Pastille d'une commande « en attente » : depuis le nouveau flux, une
    // commande payée reste « en attente » jusqu'au « Confirmer » du vendeur.
    // « À confirmer » = c'est au vendeur d'agir (paiement réussi, ou paiement
    // à la livraison) ; « Paiement en attente » = le client n'a pas encore
    // payé. Même règle que le serveur (computeConfirmBy).
    String? badgeAttente;
    if ((o['status'] ?? '').toString().toLowerCase() == 'en attente') {
      final paiement = o['payment'] as Map?;
      final payStatus = paiement?['status'];
      final payMethod = paiement?['method'];
      final aConfirmer = payStatus == 'success' ||
          (payMethod == 'cash_on_delivery' && payStatus == 'en attente');
      badgeAttente = aConfirmer ? 'À confirmer' : 'Paiement en attente';
    }
    return {
      // Prefixe '#' pour rester identique a l'affichage cote client
      // (buyer_dashboard_screen.dart / order_tracking_screen.dart) : avant
      // ce correctif, le tableau de bord vendeur affichait le code SANS le
      // '#', par ex. "ASK-2026-00007" au lieu de "#ASK-2026-00007" — le
      // numero etait deja correct, seul le format d'affichage differait.
      'id': (() {
        final raw = (o['orderNumber'] ?? o['id'] ?? '').toString();
        return raw.isEmpty ? raw : '#$raw';
      })(),
      'rawId': (o['id'] ?? '').toString(),
      'status': _mapOrderStatus(o['status'] as String?),
      'image': imageUrl,
      'product': product?['prod_name'] as String? ?? 'Produit',
      // Le backend ne renvoie pas encore le nom de l'acheteur sur cette route
      // (pas de jointure sur order.user) : on affiche le destinataire de la
      // livraison, déjà disponible via l'adresse jointe.
      'buyer': address?['nom_destinataire'] as String? ?? 'Client',
      'qty': qty,
      'date': _formatShortDate(o['createdAt'] as String?),
      'price': '${_formatPrice(amount)} FCFA',
      // ⚠️ Le vendeur ne peut plus marquer une commande "payée en
      // espèces" lui-même (voir suppression de _confirmCodPayment /
      // PATCH /payments/:id/confirm-cod) : c'est désormais au CLIENT de
      // payer via le bouton "Payer la commande" côté app (Mobile Money),
      // comme pour une commande normale.
      // Commande payée par mobile money dont le paiement n'a PAS abouti
      // (annulé/échoué côté client, jamais confirmé) : le serveur refuse
      // désormais de la laisser "Confirmer" (voir orders.service.ts,
      // updateStatus). On l'affiche ici pour que le vendeur comprenne
      // pourquoi, au lieu d'un simple échec silencieux au clic.
      'mobileMoneyUnpaid': (o['payment'] as Map?)?['method'] == 'mobile_money'
          && (o['payment'] as Map?)?['status'] != 'success',
      'paymentId': ((o['payment'] as Map?)?['id'] ?? '').toString(),
      // Nécessaires pour savoir quelle action de preuve proposer au
      // vendeur (Cas A = livreur, Cas B = retrait, Cas C = bus/taxi).
      'deliveryMode':  (o['deliveryMode'] ?? 'livraison').toString(),
      'transportMode': o['transportMode'] as String?,
      'rawStatus':     (o['status'] ?? '').toString(),
      // Date limite théorique de confirmation (commande en attente), ou null.
      'confirmBy':     o['confirmBy'],
      // Libellé de la pastille d'une commande en attente (null sinon).
      'badgeAttente':  badgeAttente,
    };
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
        // Session perdue : ne pas afficher un faux « 0 » (voir
        // NestAuthService.gererSessionPerdue).
        final etat = await NestAuthService.instance.gererSessionPerdue();
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (etat == EtatSessionPerdue.temporaire) {
              _hasConnectionError = true;
            }
          });
        }
        return;
      }

      Map<String, dynamic>? shop;
      List<Map<String, dynamic>> products = [];
      List<Map<String, dynamic>> orders = [];
      // Un échec sur les produits ou les commandes ne doit pas s'afficher
      // comme « 0 produit / 0 commande » : erreur + « Réessayer ».
      var echecProduits = false;
      var echecCommandes = false;

      try {
        final r = await ApiService.instance.client.get('/api/v1/vendors/me');
        shop = Map<String, dynamic>.from(r.data as Map);
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/products/vendor/me');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        products = list
            .whereType<Map>()
            .map((e) => _normalizeSellerProduct(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        echecProduits = true;
      }

      try {
        final r = await ApiService.instance.client.get('/api/v1/orders/vendor/me');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        orders = list
            .whereType<Map>()
            .map((e) => _normalizeSellerOrder(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        echecCommandes = true;
      }

      if (echecProduits || echecCommandes) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasConnectionError = true;
          });
        }
        return;
      }

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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: _buildPhoneLayout(),
      bottomNavigationBar: AsoukaaBottomNav(
              currentIndex: _currentNavIndex,
              onTap: (i) async {
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
                    // Boite de reception (toutes les conversations), comme
                    // le tableau de bord client ; au retour on remet
                    // l'onglet "Tableau de bord" actif.
                    await Navigator.pushNamed(context, AppRoutes.conversationsInbox);
                    if (mounted) setState(() => _currentNavIndex = 3);
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

  // Bascule vers l'espace d'achat du client (accueil) et mémorise le choix.
  Future<void> _switchToClientMode() async {
    await ModeService.instance.setLastMode(ModeService.client);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.home,
      (route) => false,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // Hauteur de base 128 + surplus quand la police systeme est agrandie
    // (sinon "BOTTOM OVERFLOWED" dans l'en-tete des ~150 %).
    final scaler = MediaQuery.textScalerOf(context);
    final extraForText =
        ((scaler.scale(20) + scaler.scale(12) - 32) * 1.3).clamp(0.0, 120.0);
    return PreferredSize(
      preferredSize: Size.fromHeight(128 + extraForText),
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
                    Expanded(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Espace Vendeur',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _shop?['shopName'] as String? ?? 'Ma boutique',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Boutique masquée par son vendeur (GET /vendors/me
                            // -> shopVisible == false) : pastille grise.
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _shop?['shopVisible'] == false
                                    ? AppTheme.muted
                                    : AppTheme.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _shop?['shopVisible'] == false
                                  ? 'Masquée'
                                  : 'Actif',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _shop?['shopVisible'] == false
                                    ? AppTheme.muted
                                    : AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(width: 10),
                    // Passage en mode client : l'espace d'achat (accueil).
                    Tooltip(
                      message: 'Passer en mode client',
                      child: Material(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _switchToClientMode,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              height: 38,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  // Libelle court ; icone seule sur petit ecran
                                  // pour ne pas tronquer "Espace Vendeur" ni
                                  // le nom de la boutique (le tooltip reste).
                                  if (MediaQuery.of(context).size.width >= 380) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      'Client',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Acces a "Mes gains" : solde retirable + demande de
                    // retrait Mobile Money (commandes livrees uniquement).
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Mes gains',
                        icon: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppRoutes.vendorWithdrawals,
                        ),
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
                _ProduitsTab(products: _products, onChanged: _loadData),
                _CommandesTab(orders: _orders, onChanged: _loadData),
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
        _ProduitsTab(products: _products, onChanged: _loadData),
        _CommandesTab(orders: _orders, onChanged: _loadData),
        const _DevisTab(),
        const _StockTab(),
        const _RevenusTab(),
        const _RetraitTab(),
        _SellerStatsTab(shop: _shop, products: _products),
      ],
    );
  }

}

// ─────────────────────────────────────────────
// PRODUITS TAB
// ─────────────────────────────────────────────

class _ProduitsTab extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final VoidCallback onChanged;
  const _ProduitsTab({this.products = const [], required this.onChanged});

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
      return _products.where((p) => p['status'] == 'published').toList();
    }
    if (_filter == 'Brouillons') {
      return _products.where((p) => p['status'] == 'draft').toList();
    }
    if (_filter == 'Dépubliés') {
      return _products.where((p) => p['status'] == 'unpublished').toList();
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
              ? _ScrollableEmpty(child: EmptyStateWidget(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucun produit trouvé',
                  description: _filter == 'Tous'
                      ? 'Vous n\'avez pas encore ajouté de produits. Commencez à vendre dès maintenant !'
                      : 'Aucun produit dans la catégorie "$_filter".',
                  ctaLabel: _filter == 'Tous' ? 'Ajouter un produit' : null,
                  onCtaTap: _filter == 'Tous'
                      ? () async {
                          final created = await Navigator.pushNamed(
                            context,
                            AppRoutes.publierProduit,
                          );
                          if (created == true) widget.onChanged();
                        }
                      : null,
                ))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _ProductCard(
                    product: _filtered[index],
                    onTogglePublish: () =>
                        _handleTogglePublish(context, _filtered[index]),
                    onEdit: () => _handleEditProduct(context, _filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleTogglePublish(
    BuildContext context,
    Map<String, dynamic> product,
  ) async {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty) return;
    final wasPublished = product['status'] == 'published';
    final newBackendStatus = wasPublished ? 'inactive' : 'active';
    // On garde le VRAI statut d'origine pour pouvoir le restaurer tel
    // quel en cas d'echec (un produit "unpublished" qu'on republie et
    // qui echoue doit redevenir "unpublished", pas "draft").
    final originalStatus = product['status'];

    setState(() {
      final idx = _products.indexWhere((p) => p['id'] == id);
      if (idx != -1) {
        _products[idx]['status'] = wasPublished ? 'unpublished' : 'published';
      }
    });

    try {
      await ApiService.instance.client.put(
        '/api/v1/products/$id',
        data: {'status': newBackendStatus},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          final idx = _products.indexWhere((p) => p['id'] == id);
          if (idx != -1) {
            _products[idx]['status'] = originalStatus;
          }
        });
        AppToast.show(
          context,
          message: 'Impossible de mettre à jour le statut du produit.',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _handleEditProduct(
    BuildContext context,
    Map<String, dynamic> product,
  ) async {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty) return;

    Map<String, dynamic> fullProduct;
    try {
      // Route réservée au vendeur propriétaire : renvoie aussi les
      // brouillons et produits désactivés (la route publique les cache).
      final r = await ApiService.instance
          .client
          .get('/api/v1/products/vendor/me/$id');
      fullProduct = Map<String, dynamic>.from(r.data as Map);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible de charger le produit.',
          type: ToastType.error,
        );
      }
      return;
    }

    if (!mounted) return;
    final updated = await Navigator.pushNamed(
      context,
      AppRoutes.publierProduit,
      arguments: fullProduct,
    );
    if (updated == true) widget.onChanged();
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
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
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final created = await Navigator.pushNamed(
                context,
                AppRoutes.publierProduit,
              );
              if (created == true) widget.onChanged();
            },
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        children: ['Tous', 'Publiés', 'Brouillons', 'Dépubliés'].map((f) {
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
  final VoidCallback onEdit;

  const _ProductCard({
    required this.product,
    required this.onTogglePublish,
    required this.onEdit,
  });

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
                      _StatusChip(status: product['status'] as String? ?? 'draft'),
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _MiniStat(
                        icon: Icons.inventory_2_outlined,
                        value: '${product['stock']} en stock',
                        color: isOutOfStock
                            ? AppTheme.error
                            : AppTheme.textSecondary,
                      ),
                      _MiniStat(
                        icon: Icons.visibility_outlined,
                        value: '${product['views']}',
                        color: AppTheme.textSecondary,
                      ),
                      _MiniStat(
                        icon: Icons.shopping_bag_outlined,
                        value: '${product['sales']} ventes',
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _ActionBtn(
                        icon: Icons.edit_outlined,
                        label: 'Modifier',
                        onTap: onEdit,
                      ),
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
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'published' => ('Publié', AppTheme.successContainer, AppTheme.success),
      'unpublished' => ('Dépublié', AppTheme.warningContainer, AppTheme.warning),
      'out_of_stock' => ('Rupture de stock', AppTheme.errorContainer, AppTheme.error),
      _ => ('Brouillon', AppTheme.surfaceVariant, AppTheme.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
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
  final VoidCallback onChanged;
  const _CommandesTab({this.orders = const [], required this.onChanged});

  @override
  State<_CommandesTab> createState() => _CommandesTabState();
}

class _CommandesTabState extends State<_CommandesTab> {
  String _filter = 'Toutes';
  late List<Map<String, dynamic>> _orders;
  List<Map<String, dynamic>> _sellerProducts = [];
  bool _loadingSellerProducts = false;

  @override
  void initState() {
    super.initState();
    _orders = List.from(widget.orders);
  }

  // Utilisé par le formulaire "Initier une commande" pour proposer un vrai
  // combo des produits du vendeur (avant : un simple champ texte libre).
  Future<void> _loadSellerProducts() async {
    if (_sellerProducts.isNotEmpty || _loadingSellerProducts) return;
    setState(() => _loadingSellerProducts = true);
    try {
      final r = await ApiService.instance.client.get('/api/v1/products/vendor/me');
      final raw = r.data;
      final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
      final products = list
          .whereType<Map>()
          .map((e) => _SellerDashboardScreenState._normalizeSellerProduct(Map<String, dynamic>.from(e)))
          .where((p) => p['status'] == 'published')
          .toList();
      if (mounted) setState(() => _sellerProducts = products);
    } catch (_) {
      // silencieux : le champ retombe sur une saisie libre si l'appel échoue
    } finally {
      if (mounted) setState(() => _loadingSellerProducts = false);
    }
  }

  @override
  void didUpdateWidget(_CommandesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orders != widget.orders) {
      setState(() => _orders = List.from(widget.orders));
    }
  }

  // NB: o['status'] est un OrderStatus (enum), pas une chaine — l'ancien code
  // comparait a des mots ('confirme', 'en_preparation'...) qui ne
  // correspondaient a rien de reel, ce qui rendait les filtres inoperants.
  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'En cours':
        return _orders.where((o) {
          final s = o['status'];
          return s == OrderStatus.received ||
              s == OrderStatus.processing ||
              s == OrderStatus.inDelivery;
        }).toList();
      case 'Terminées':
        return _orders
            .where((o) => o['status'] == OrderStatus.completed)
            .toList();
      case 'Annulées':
        return _orders.where((o) {
          final s = o['status'];
          return s == OrderStatus.cancelled || s == OrderStatus.failed;
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
              onPressed: () {
                _loadSellerProducts();
                _showInitiateOrderDialog(context);
              },
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
              ? _ScrollableEmpty(child: EmptyStateWidget(
                  icon: Icons.inbox_outlined,
                  title: 'Aucune commande',
                  description: 'Aucune commande dans cette catégorie',
                ))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _SellerOrderCard(
                    order: _filtered[i],
                    onConfirm: () => _handleConfirm(context, _filtered[i]),
                    onDetails: () => _showOrderDetails(context, _filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  static String? _nextBackendStatus(dynamic status) {
    if (status == OrderStatus.received) return 'en cours';
    // ⚠️ Il n'y a plus de transition directe "en cours" → "expedié" ici
    // : ce changement exige désormais une preuve concrète (ramassage
    // livreur, scan de retrait en boutique, ou remise au transporteur
    // bus/taxi selon le cas) et passe par des actions dédiées — voir
    // le bouton "Démarrer" dans _showAssignAgentSheet (Cas A) et
    // l'action à ajouter pour les Cas B/C.
    return null;
  }

  Future<void> _handleConfirm(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    final nextStatus = _nextBackendStatus(order['status']);
    final orderId = order['rawId']?.toString();
    if (nextStatus == null || orderId == null || orderId.isEmpty) {
      // Rien à confirmer directement à ce stade : la suite exige une
      // preuve (voir "Détails" → l'action correspondant au mode de
      // livraison de cette commande).
      if (order['status'] == OrderStatus.processing && mounted) {
        AppToast.show(
          context,
          message: 'Ouvrez "Détails" pour l\'action suivante '
              '(livraison, retrait ou remise au transporteur).',
          type: ToastType.info,
        );
      }
      return;
    }

    try {
      await ApiService.instance.client.patch(
        '/api/v1/orders/$orderId/status',
        data: {'status': nextStatus},
      );
      if (mounted) widget.onChanged();
    } on DioException catch (e) {
      // Cas fréquent : paiement mobile money annulé/échoué (voir
      // 'mobileMoneyUnpaid' ci-dessus) — le serveur renvoie alors un
      // message explicite qu'on affiche tel quel plutôt qu'un message
      // générique qui masquerait la vraie raison.
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ??
                'Impossible de confirmer cette commande.')
            : 'Impossible de confirmer cette commande.';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible de confirmer cette commande.',
          type: ToastType.error,
        );
      }
    }
  }

  // Libellé + icône du bouton Cas A dans "Détails", selon l'avancement
  // réel de la livraison — pour ne plus jamais réafficher "Affecter un
  // livreur" une fois que c'est déjà fait.
  (String, IconData) _casALabelFor(String? rawStatus) {
    switch (rawStatus) {
      case 'en cours':
        return ('Livraison / Affecter un livreur', Icons.local_shipping_outlined);
      case 'livreur affecté':
        return ('Livraison — en attente du livreur', Icons.hourglass_top_rounded);
      case 'expedié':
        return ('Démarrer la livraison', Icons.play_arrow_rounded);
      case 'en transit':
        return ('Livraison en cours', Icons.route_rounded);
      default:
        return ('Livraison / Affecter un livreur', Icons.local_shipping_outlined);
    }
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commande ${order['id']}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Produit', order['product']?.toString() ?? ''),
              _buildDetailRow('Acheteur', order['buyer']?.toString() ?? ''),
              _buildDetailRow('Quantité', order['qty']?.toString() ?? ''),
              _buildDetailRow('Date', order['date']?.toString() ?? ''),
              _buildDetailRow('Montant', order['price']?.toString() ?? ''),
              const SizedBox(height: 16),
              // ⚠️ Bouton "Marquer payé (espèces reçues)" retiré : le
              // vendeur ne peut plus marquer unilatéralement une commande
              // comme payée. C'est désormais au client de payer via
              // Mobile Money (bouton "Payer la commande" côté app), comme
              // pour une commande normale.
              // Paiement mobile money annulé/échoué : rien à faire ici
              // (pas de bouton — c'est au client de retenter le paiement),
              // juste expliquer pourquoi "Confirmer" ne fonctionne pas.
              if (order['mobileMoneyUnpaid'] == true) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paiement mobile money non confirmé (annulé ou échoué) — '
                          'le client doit retenter le paiement avant que vous '
                          'puissiez confirmer cette commande.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Cas A — livraison avec un livreur interne. Ce bouton sert
              // à la fois à affecter le livreur (statut "en cours") ET à
              // suivre/faire avancer la livraison ensuite (livreur affecté,
              // expédié, en transit) — voir _showAssignAgentSheet, qui
              // affiche le bon contenu selon l'état actuel. On ne le
              // cache que quand il n'y a plus rien à y faire : avant
              // confirmation de la commande, ou une fois livrée/annulée.
              //
              // Le LIBELLÉ change avec le statut (voir _casALabelFor) :
              // avant, il affichait toujours "Livraison / Affecter un
              // livreur", même une fois le livreur déjà affecté et le
              // colis déjà récupéré — le vendeur devait cliquer "pour
              // rien" avant de voir apparaître le vrai bouton "Démarrer"
              // à l'intérieur. Le bouton reflète maintenant directement
              // l'action à faire.
              if (order['deliveryMode'] == 'livraison' &&
                  order['transportMode'] == null &&
                  order['rawStatus'] != 'en attente' &&
                  order['rawStatus'] != 'livré' &&
                  order['rawStatus'] != 'annulé') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(_casALabelFor(order['rawStatus'] as String?).$2, size: 18),
                    label: Text(_casALabelFor(order['rawStatus'] as String?).$1),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAssignAgentSheet(context, order);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Cas B — retrait en boutique : on scanne le QR du client
              // venu récupérer sa commande.
              if (order['deliveryMode'] == 'retrait' &&
                  order['rawStatus'] == 'en cours') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scanner le retrait du client'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _scanStorePickupProof(context, order);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Cas C — bus/taxi (zone Nord) : preuve de remise au
              // transporteur (photo + état), démarre le délai de 3 jours.
              if (order['deliveryMode'] == 'livraison' &&
                  order['transportMode'] != null &&
                  order['rawStatus'] == 'en cours') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Remise au transporteur (bus/taxi)'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _submitDispatchProof(context, order);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fermer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // AFFECTATION D'UN LIVREUR À UNE COMMANDE
  // ─────────────────────────────────────────────────────

  Future<void> _showAssignAgentSheet(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    final orderId = order['rawId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    Map<String, dynamic>? delivery;
    try {
      final res = await ApiService.instance.client.get(
        '/api/v1/delivery/order/$orderId',
      );
      delivery = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : null;
    } on DioException catch (e) {
      if (!context.mounted) return;
      final msg = e.response?.statusCode == 404
          ? 'Pas de fiche de livraison pour cette commande '
            '(retrait en boutique, ou commande créée avant la mise à jour du serveur).'
          : 'Impossible de récupérer la livraison de cette commande.';
      AppToast.show(context, message: msg, type: ToastType.error);
      return;
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(context, message: 'Erreur réseau.', type: ToastType.error);
      return;
    }

    if (delivery == null || !context.mounted) return;

    final deliveryId = delivery['id']?.toString();
    final status = delivery['status']?.toString();
    final existingAgent = delivery['agent'] as Map<String, dynamic>?;

    // Déjà affectée : afficher qui, pas de re-sélection ici
    if (status != 'en attente' || existingAgent != null) {
      final agentUser = existingAgent?['user'] as Map<String, dynamic>?;
      final name = agentUser != null
          ? '${agentUser['prenom'] ?? ''} ${agentUser['name'] ?? ''}'.trim()
          : null;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Livraison',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('Statut', status ?? '-'),
                if (name != null && name.isNotEmpty)
                  _buildDetailRow('Livreur', name),
                const SizedBox(height: 16),
                // Actif uniquement une fois que le livreur a fourni sa
                // preuve de ramassage (photo + état) — c'est cette
                // preuve, pas ce bouton, qui fait passer la livraison à
                // "récupéré". Le vendeur n'a la main que pour démarrer
                // le trajet ensuite.
                if (status == 'récupéré') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                      label: const Text('Démarrer la livraison'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startTransit(context, deliveryId);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    List<Map<String, dynamic>> agents = [];
    try {
      final res = await ApiService.instance.client.get(
        '/api/v1/delivery-agents/available',
      );
      final data = res.data;
      agents = data is List ? List<Map<String, dynamic>>.from(data) : [];
    } catch (_) {
      agents = [];
    }

    if (!context.mounted) return;

    if (agents.isEmpty) {
      AppToast.show(
        context,
        message: 'Aucun livreur disponible pour le moment.',
        type: ToastType.error,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choisir un livreur',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: agents.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = agents[i];
                    final u = a['user'] as Map<String, dynamic>?;
                    final name = u != null
                        ? '${u['prenom'] ?? ''} ${u['name'] ?? ''}'.trim()
                        : 'Livreur';
                    final phone = u?['phone']?.toString() ?? '';
                    final vehicle = a['vehicleType']?.toString() ?? '';
                    return ListTile(
                      title: Text(
                        name.isEmpty ? 'Livreur' : name,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('$vehicle · $phone'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(ctx);
                        _assignAgent(context, deliveryId, a['id']?.toString());
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignAgent(
    BuildContext context,
    String? deliveryId,
    String? agentId,
  ) async {
    if (deliveryId == null || agentId == null) return;
    try {
      await ApiService.instance.client.patch(
        '/api/v1/delivery/$deliveryId/assign',
        data: {'agentId': agentId},
      );
      if (mounted) {
        AppToast.show(
          context,
          message: 'Livreur affecté avec succès.',
          type: ToastType.success,
        );
        widget.onChanged();
      }
    } on DioException catch (e) {
      // On affiche le vrai message du backend (ex: "la commande doit être
      // en préparation avant d'affecter un livreur", "ce livreur n'est
      // plus disponible"...) plutôt qu'un message générique qui masque la
      // vraie raison et empêche de comprendre ce qui s'est passé.
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ??
                'Impossible d\'affecter ce livreur.')
            : 'Impossible d\'affecter ce livreur.';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible d\'affecter ce livreur '
              '(peut-être déjà pris entre-temps).',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _startTransit(BuildContext context, String? deliveryId) async {
    if (deliveryId == null || deliveryId.isEmpty) return;
    try {
      await ApiService.instance.client.post(
        '/api/v1/delivery/$deliveryId/start-transit',
      );
      if (mounted) {
        AppToast.show(
          context,
          message: 'Livraison démarrée.',
          type: ToastType.success,
        );
        widget.onChanged();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ?? 'Impossible de démarrer cette livraison.')
            : 'Impossible de démarrer cette livraison.';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible de démarrer cette livraison.',
          type: ToastType.error,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────
  // CAS B — RETRAIT EN BOUTIQUE : scan du QR du client
  // ─────────────────────────────────────────────────────
  Future<void> _scanStorePickupProof(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    final orderId = order['rawId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    MobileScannerController? controller;
    String? scanned;

    if (!kIsWeb) {
      controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      scanned = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scanner le QR code du client',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 320,
                    child: MobileScanner(
                      controller: controller,
                      onDetect: (capture) {
                        if (capture.barcodes.isEmpty) return;
                        final code = capture.barcodes.first.rawValue;
                        if (code != null && code.isNotEmpty) {
                          Navigator.pop(ctx, code);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
              ],
            ),
          ),
        ),
      );
      await controller.dispose();
    } else {
      // Pas de caméra fiable sur web dans ce contexte : saisie manuelle.
      final textController = TextEditingController();
      scanned = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Code de remise du client'),
          content: TextField(controller: textController, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, textController.text.trim()),
              child: const Text('Valider'),
            ),
          ],
        ),
      );
    }

    if (scanned == null || scanned.isEmpty || !context.mounted) return;

    try {
      await ApiService.instance.client.post(
        '/api/v1/orders/$orderId/store-pickup-proof',
        data: {'qrScanValue': scanned},
      );
      if (mounted) {
        AppToast.show(context, message: 'Retrait confirmé.', type: ToastType.success);
        widget.onChanged();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ?? 'Le QR code ne correspond pas à cette commande.')
            : 'Le QR code ne correspond pas à cette commande.';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Impossible de confirmer le retrait.', type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────
  // CAS C — BUS/TAXI : preuve de remise au transporteur
  // ─────────────────────────────────────────────────────
  Future<void> _submitDispatchProof(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    final orderId = order['rawId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    const conditions = ['Bon état', 'Légèrement endommagé', 'Endommagé'];
    String selectedCondition = conditions.first;
    String? photoUrl;
    bool uploading = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remise au transporteur',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: Icon(photoUrl != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined),
                  label: Text(uploading
                      ? 'Envoi de la photo...'
                      : photoUrl != null
                          ? 'Photo ajoutée'
                          : 'Photo du colis / transporteur'),
                  onPressed: uploading
                      ? null
                      : () async {
                          final picked = await ImagePicker()
                              .pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 80);
                          if (picked == null) return;
                          setModalState(() => uploading = true);
                          try {
                            final url = await UploadService.instance.uploadFile(picked, 'proofs');
                            setModalState(() {
                              photoUrl = url;
                              uploading = false;
                            });
                          } catch (_) {
                            setModalState(() => uploading = false);
                            if (ctx.mounted) {
                              AppToast.show(ctx, message: 'Échec de l\'upload.', type: ToastType.error);
                            }
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCondition,
                  decoration: const InputDecoration(labelText: 'État du colis'),
                  items: conditions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedCondition = v ?? selectedCondition),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (photoUrl != null && !uploading)
                        ? () => Navigator.pop(ctx, true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirmer la remise'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || photoUrl == null || !context.mounted) return;

    try {
      await ApiService.instance.client.post(
        '/api/v1/orders/$orderId/dispatch-proof',
        data: {'photoUrl': photoUrl, 'etatColis': selectedCondition},
      );
      if (mounted) {
        AppToast.show(
          context,
          message: 'Remise au transporteur enregistrée. Le client a 3 jours pour confirmer.',
          type: ToastType.success,
        );
        widget.onChanged();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ?? 'Impossible d\'enregistrer la remise.')
            : 'Impossible d\'enregistrer la remise.';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Impossible d\'enregistrer la remise.', type: ToastType.error);
      }
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
      ),
    );
  }

  // Extrait un message d'erreur lisible renvoyé par le backend
  // (class-validator renvoie parfois un tableau de messages).
  String _extractVendorOrderError(Object e) {
    try {
      final response = (e as dynamic).response;
      final data = response?.data;
      if (data is Map && data['message'] != null) {
        final msg = data['message'];
        if (msg is String) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    } catch (_) {}
    return 'La demande a échoué. Réessayez.';
  }

  // ⚠️ _confirmCodPayment() (le vendeur marquait lui-même une commande
  // "payée en espèces" via PATCH /payments/:id/confirm-cod) a été
  // retirée : cette route n'existe plus côté backend. Le client paie
  // désormais via le bouton "Payer la commande" (Mobile Money normal).

  void _showInitiateOrderDialog(BuildContext context) {
    final phoneCtrl = TextEditingController();
    final newQuartierCtrl = TextEditingController();
    final newVilleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final List<Map<String, dynamic>> selectedProducts = [];
    Map<String, dynamic>? foundClient;
    List<Map<String, dynamic>> clientAddresses = [];
    List<Map<String, dynamic>> searchResults = [];
    String? selectedAddressId;
    bool searchingClient = false;
    // Message du serveur affiche en entier sous le champ de recherche (ex :
    // « Aucun client trouvé parmi vos clients. Pour un nouveau client,
    // saisissez son numéro complet… ») : un toast tronquerait ce texte long.
    String? searchMessage;
    bool submittingOrder = false;
    // Meme logique commune/transport que le panier client (voir
    // DeliverySelectorWidget) : mode livraison/retrait + bus/taxi pour les
    // communes du Nord. 'newDeliverySelectionComplete' reprend
    // DeliverySelection.isComplete pour bloquer la soumission tant que le
    // vendeur n'a pas choisi le mode de transport sur une commune du Nord.
    String deliveryMode = 'livraison';
    String? transportMode;
    bool newDeliverySelectionComplete = true;
    // Incremente pour forcer DeliverySelectorWidget a se reconstruire avec
    // un nouvel `initialCity` (changement de client, d'adresse selectionnee,
    // ou retour vers "Nouvelle adresse") -- meme technique que
    // cart_screen.dart (_deliverySelectorSeed), car `initialCity` n'est lu
    // qu'une seule fois par le widget (dans son initState).
    int deliverySelectorSeed = 0;

    // Frais de livraison renvoye par DeliverySelectorWidget (0 si mode
    // "retrait" ou commune pas encore choisie) -- utilise pour le recap
    // "Total a payer" affiche juste avant le bouton "Creer la commande".
    double deliveryFeePreview = 0;

    // Extrait le montant numerique d'un prix deja formate ("5 000 FCFA").
    int parsePrice(dynamic p) {
      final digits = (p as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits) ?? 0;
    }

    // Prix unitaire reel pour [qty] unites d'un produit, paliers degressifs
    // inclus -- meme algorithme que _unitPriceForQty() dans
    // product_detail_screen.dart : le palier avec la plus haute minQuantity
    // <= qty, jamais plus cher que le prix de base.
    int unitPriceForProduct(Map<String, dynamic> p, int qty) {
      final base = (p['rawPrice'] as int?) ?? parsePrice(p['price']);
      final tiers = p['tierPrices'];
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void recomputeAmount() {
            final total = selectedProducts.fold<int>(
              0,
              (sum, p) {
                final qty = (p['quantity'] as int?) ?? 1;
                return sum + unitPriceForProduct(p, qty) * qty;
              },
            );
            amountCtrl.text = total.toString();
          }

          // Determine si la commune de l'adresse existante selectionnee fait
          // partie des communes du Nord (bus/taxi requis) — meme regle que
          // OrdersService.getFraisLivraisonForCommune cote serveur.
          Future<void> checkNordForAddress(String? addressId) async {
            if (addressId == null) {
              setSheetState(() {
                transportMode = null;
                newVilleCtrl.clear();
                deliverySelectorSeed++;
              });
              return;
            }
            final addr = clientAddresses.firstWhere(
              (a) => a['id']?.toString() == addressId,
              orElse: () => <String, dynamic>{},
            );
            final ville = (addr['ville'] as String?) ?? '';
            setSheetState(() {
              transportMode = null;
              // Prerempli DeliverySelectorWidget avec la commune reelle de
              // l'adresse choisie (au lieu de la retaper) ; le vendeur reste
              // libre de la changer, comme sur le panier client. Le widget
              // determine lui-meme (via son propre initState) si c'est une
              // commune du Nord et affiche alors le choix bus/taxi.
              newVilleCtrl.text = ville;
              deliverySelectorSeed++;
            });
          }

          // Choisit un client (parmi les resultats de recherche, ou le
          // resultat unique auto-selectionne) et recupere ses adresses.
          Future<void> selectClient(Map<String, dynamic> client) async {
            setSheetState(() => searchingClient = true);
            try {
              final res = await ApiService.instance.client.get(
                '/api/v1/orders/vendor/client/${client['id']}/addresses',
              );
              final data = res.data is Map<String, dynamic>
                  ? res.data as Map<String, dynamic>
                  : <String, dynamic>{};
              final addresses = (data['addresses'] as List?)
                      ?.whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList() ??
                  [];
              setSheetState(() {
                foundClient = data;
                clientAddresses = addresses;
                searchResults = [];
                selectedAddressId =
                    addresses.isNotEmpty ? addresses.first['id']?.toString() : null;
              });
              await checkNordForAddress(selectedAddressId);
            } catch (e) {
              if (!ctx.mounted) return;
              AppToast.show(ctx, message: _extractVendorOrderError(e), type: ToastType.error);
            } finally {
              if (ctx.mounted) setSheetState(() => searchingClient = false);
            }
          }

          // Recherche large : telephone, prenom, nom ou email. Un seul
          // resultat -> selectionne directement (comme avant, quand la
          // recherche se faisait uniquement par telephone exact). Plusieurs
          // resultats -> affiche une liste pour que le vendeur choisisse
          // le bon client (ex: plusieurs "Marie").
          Future<void> searchClient() async {
            final query = phoneCtrl.text.trim();
            if (query.length < 3) {
              AppToast.show(
                ctx,
                message: 'Saisissez au moins 3 caractères (téléphone, nom ou email du client).',
                type: ToastType.error,
              );
              return;
            }
            setSheetState(() {
              searchingClient = true;
              searchMessage = null;
              foundClient = null;
              clientAddresses = [];
              selectedAddressId = null;
              searchResults = [];
            });
            try {
              final res = await ApiService.instance.client.get(
                '/api/v1/orders/vendor/find-client',
                queryParameters: {'query': query},
              );
              final list = (res.data is List ? res.data as List : [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              if (list.length == 1) {
                await selectClient(list.first);
                return;
              }
              setSheetState(() => searchResults = list);
            } catch (e) {
              if (!ctx.mounted) return;
              // Message du serveur affiché tel quel (lisible en entier).
              setSheetState(() => searchMessage = _extractVendorOrderError(e));
            } finally {
              if (ctx.mounted) setSheetState(() => searchingClient = false);
            }
          }

          Future<void> pickProducts() async {
            final chosen = Set<String>.from(
              selectedProducts.map((p) => p['id'] as String),
            );
            await showModalBottomSheet(
              context: ctx,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (pickerCtx) => StatefulBuilder(
                builder: (pickerCtx, setPickerState) => Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(pickerCtx).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choisir des produits',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingSellerProducts)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_sellerProducts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Aucun produit publié pour le moment.',
                            style: GoogleFonts.outfit(color: AppTheme.muted),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView(
                            shrinkWrap: true,
                            children: _sellerProducts.map((p) {
                              final id = p['id'] as String;
                              final isChecked = chosen.contains(id);
                              return CheckboxListTile(
                                value: isChecked,
                                onChanged: (v) {
                                  setPickerState(() {
                                    if (v == true) {
                                      chosen.add(id);
                                    } else {
                                      chosen.remove(id);
                                    }
                                  });
                                },
                                title: Text(p['name'] as String? ?? 'Produit'),
                                subtitle: Text(p['price'] as String? ?? ''),
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final prevQty = <String, int>{
                              for (final p in selectedProducts)
                                p['id'] as String: (p['quantity'] as int?) ?? 1,
                            };
                            selectedProducts
                              ..clear()
                              ..addAll(
                                _sellerProducts
                                    .where((p) => chosen.contains(p['id']))
                                    .map((p) => {
                                          ...p,
                                          'quantity': prevQty[p['id'] as String] ?? 1,
                                        }),
                              );
                            recomputeAmount();
                            setSheetState(() {});
                            Navigator.pop(pickerCtx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Valider (${chosen.length})',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return SingleChildScrollView(
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
            Text(
              'Vos clients : cherchez par nom, téléphone ou e-mail. Nouveau client : '
              'saisissez son numéro complet (ou son e-mail complet) — il doit déjà '
              'avoir un compte sur l\'application.',
              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: phoneCtrl,
                    enabled: foundClient == null,
                    decoration: InputDecoration(
                      labelText: 'Téléphone, nom ou email du client',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: searchingClient
                        ? null
                        : (foundClient == null
                            ? searchClient
                            : () => setSheetState(() {
                                  foundClient = null;
                                  clientAddresses = [];
                                  searchResults = [];
                                  searchMessage = null;
                                  selectedAddressId = null;
                                  phoneCtrl.clear();
                                })),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          foundClient == null ? AppTheme.primary : AppTheme.surfaceVariant,
                      foregroundColor:
                          foundClient == null ? Colors.white : AppTheme.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: searchingClient
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(foundClient == null ? 'Rechercher' : 'Changer'),
                  ),
                ),
              ],
            ),
            if (searchMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                searchMessage!,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.error),
              ),
            ],
            if (searchResults.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                '${searchResults.length} clients trouvés — choisissez :',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = searchResults[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${r['prenom'] ?? ''} ${r['name'] ?? ''}',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      // `linked` == false : client trouvé seulement par numéro
                      // ou e-mail complet, coordonnées masquées par le serveur
                      // (affichées telles quelles). Absent (ancien serveur) :
                      // comportement inchangé.
                      isThreeLine: r['linked'] == false,
                      subtitle: Text(
                        [r['phone'], r['email']].whereType<String>().join(' · ') +
                            (r['linked'] == false
                                ? '\nCoordonnées masquées par sécurité'
                                : ''),
                        style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
                      ),
                      onTap: () => selectClient(r),
                    );
                  },
                ),
              ),
            ],
            if (foundClient != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Client : ${foundClient!['prenom'] ?? ''} ${foundClient!['name'] ?? ''}',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          // Client non lié à la boutique : le serveur masque
                          // téléphone et nom de famille (on les affiche tels
                          // quels, jamais renvoyés dans la commande).
                          if (foundClient!['linked'] == false) ...[
                            if ('${foundClient!['phone'] ?? ''}'.isNotEmpty)
                              Text(
                                '${foundClient!['phone']}',
                                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
                              ),
                            Text(
                              'Client trouvé — coordonnées masquées par sécurité',
                              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Adresse de livraison',
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.muted),
              ),
              if (foundClient!['linked'] == false && clientAddresses.isEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Les adresses de ce client ne sont pas visibles : saisissez la '
                  'nouvelle adresse de livraison ci-dessous.',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
                ),
              ],
              const SizedBox(height: 6),
              ...clientAddresses.map((a) {
                final id = a['id']?.toString();
                return RadioListTile<String?>(
                  value: id,
                  groupValue: selectedAddressId,
                  onChanged: (v) {
                    setSheetState(() => selectedAddressId = v);
                    checkNordForAddress(v);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${a['label'] ?? 'Adresse'} — ${a['quartier'] ?? ''}, ${a['ville'] ?? ''}',
                    style: GoogleFonts.outfit(fontSize: 13),
                  ),
                );
              }),
              RadioListTile<String?>(
                value: null,
                groupValue: selectedAddressId,
                onChanged: (v) => setSheetState(() {
                  selectedAddressId = null;
                  // Sinon un mode bus/taxi choisi pour une adresse existante
                  // du Nord pouvait survivre au passage vers "Nouvelle
                  // adresse" : si la nouvelle commune tapee est aussi une
                  // commune du Nord, DeliverySelectorWidget ne reinitialise
                  // ce champ que quand la ville n'est PAS une commune du
                  // Nord, donc la valeur perimee restait acceptee sans que
                  // le vendeur ne confirme explicitement le transport pour
                  // cette nouvelle adresse.
                  transportMode = null;
                  // Repart d'une commune vide (comme au premier affichage du
                  // formulaire) au lieu de garder celle de l'adresse
                  // existante precedemment selectionnee.
                  newVilleCtrl.clear();
                  deliverySelectorSeed++;
                }),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Nouvelle adresse', style: GoogleFonts.outfit(fontSize: 13)),
              ),
              const SizedBox(height: 8),
              // Commune et mode livraison/retrait TOUJOURS visibles -- que
              // l'adresse soit deja enregistree (preremplie avec sa commune
              // reelle par checkNordForAddress ci-dessus) ou nouvelle (champ
              // vide au depart) -- meme comportement que cart_screen.dart
              // (_buildDeliverySection). DeliverySelectorWidget gere lui-meme
              // l'affichage bus/taxi pour les communes du Nord, donc on ne
              // duplique plus ce choix ici avec des RadioListTile a part.
              DeliverySelectorWidget(
                key: ValueKey(deliverySelectorSeed),
                initialMode: deliveryMode,
                initialCity: newVilleCtrl.text,
                initialTransportMode: transportMode,
                onChanged: (sel) {
                  setSheetState(() {
                    newVilleCtrl.text = sel.city;
                    deliveryMode = sel.mode;
                    transportMode = sel.transportMode;
                    newDeliverySelectionComplete = sel.isComplete;
                    deliveryFeePreview = sel.fee;
                  });
                },
              ),
              if (selectedAddressId == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: newQuartierCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quartier',
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              'Produit(s) commandé(s)',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.muted),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: pickProducts,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.outline),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: selectedProducts.isEmpty
                    ? Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 18, color: AppTheme.muted),
                          const SizedBox(width: 10),
                          Text(
                            'Choisir parmi mes produits publiés',
                            style: GoogleFonts.outfit(color: AppTheme.muted),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: selectedProducts.map((p) {
                          final qty = (p['quantity'] as int?) ?? 1;
                          final unitPrice = unitPriceForProduct(p, qty);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['name'] as String? ?? 'Produit',
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '$unitPrice FCFA / unité',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11.5,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: qty > 1
                                      ? () => setSheetState(() {
                                            p['quantity'] = qty - 1;
                                            recomputeAmount();
                                          })
                                      : null,
                                ),
                                Text(
                                  '$qty',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: () => setSheetState(() {
                                    p['quantity'] = qty + 1;
                                    recomputeAmount();
                                  }),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18, color: AppTheme.error),
                                  onPressed: () => setSheetState(() {
                                    selectedProducts.removeWhere((e) => e['id'] == p['id']);
                                    recomputeAmount();
                                  }),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            // Recap en lecture seule avant validation : sous-total produits
            // (prix degressifs deja appliques par recomputeAmount via
            // unitPriceForProduct) + frais de livraison (ou "Retrait en
            // boutique" si deliveryMode == 'retrait') + total. Avant ce
            // correctif, seul un TextField "Montant total" MODIFIABLE etait
            // affiche -- or ce montant n'est meme pas envoye au serveur
            // (payload['items'] seul determine le prix reel cote backend) :
            // le vendeur pouvait croire a tort qu'il fixait le prix en le
            // modifiant. Desormais purement informatif et fidele au calcul
            // reellement applique.
            Builder(builder: (_) {
              final subtotal = int.tryParse(amountCtrl.text) ?? 0;
              final isRetrait = deliveryMode == 'retrait';
              final feeInt = isRetrait ? 0 : deliveryFeePreview.round();
              final total = subtotal + feeInt;
              Widget row(String label, String value, {bool bold = false}) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: bold ? 14 : 13,
                          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                          color: bold ? AppTheme.textPrimary : AppTheme.muted,
                        ),
                      ),
                      Text(
                        value,
                        style: GoogleFonts.outfit(
                          fontSize: bold ? 15 : 13,
                          fontWeight: FontWeight.w700,
                          color: bold ? AppTheme.primary : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    row('Sous-total produits', '${_SellerDashboardScreenState._formatPrice(subtotal)} FCFA'),
                    row(
                      isRetrait ? 'Retrait en boutique' : 'Frais de livraison',
                      isRetrait ? 'Gratuit' : '${_SellerDashboardScreenState._formatPrice(feeInt)} FCFA',
                    ),
                    const Divider(height: 16),
                    row('Total à payer par le client', '${_SellerDashboardScreenState._formatPrice(total)} FCFA', bold: true),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: submittingOrder
                    ? null
                    : () async {
                        if (foundClient == null) {
                          AppToast.show(
                            ctx,
                            message: 'Recherchez d\'abord le client par téléphone.',
                            type: ToastType.error,
                          );
                          return;
                        }
                        if (selectedProducts.isEmpty) {
                          AppToast.show(
                            ctx,
                            message: 'Choisissez au moins un produit.',
                            type: ToastType.error,
                          );
                          return;
                        }
                        if (selectedAddressId == null &&
                            (newQuartierCtrl.text.trim().isEmpty ||
                                newVilleCtrl.text.trim().isEmpty)) {
                          AppToast.show(
                            ctx,
                            message: 'Renseignez le quartier et la ville de livraison.',
                            type: ToastType.error,
                          );
                          return;
                        }
                        if (!newDeliverySelectionComplete) {
                          AppToast.show(
                            ctx,
                            message:
                                'Choisissez le mode de transport (bus ou taxi) pour cette commune.',
                            type: ToastType.error,
                          );
                          return;
                        }

                        setSheetState(() => submittingOrder = true);
                        try {
                          // Nouveau serveur (champ `linked` présent) : le client
                          // est désigné par son id ; on n'envoie JAMAIS le
                          // téléphone (masqué pour un client non lié -> 400
                          // « Format de téléphone invalide »). Ancien serveur
                          // (`linked` absent) : comportement d'avant, par
                          // téléphone.
                          final bool serveurAvecClientId =
                              foundClient!['linked'] is bool &&
                                  '${foundClient!['id'] ?? ''}'.isNotEmpty;
                          final payload = <String, dynamic>{
                            if (serveurAvecClientId)
                              'clientId': '${foundClient!['id']}'
                            else
                              'clientPhone':
                                  normaliserTelephone('${foundClient!['phone'] ?? ''}'),
                            'items': selectedProducts
                                .map((p) => {
                                      'variantId': p['variantId'],
                                      'quantity': (p['quantity'] as int?) ?? 1,
                                    })
                                .toList(),
                          };
                          if (selectedAddressId != null) {
                            payload['addressId'] = selectedAddressId;
                          } else {
                            payload['newAddressQuartier'] = newQuartierCtrl.text.trim();
                            payload['newAddressVille'] = newVilleCtrl.text.trim();
                          }
                          // Envoye desormais dans tous les cas (avant :
                          // seulement pour une nouvelle adresse) -- sinon
                          // "Retrait en boutique" choisi sur une adresse DEJA
                          // enregistree du client n'etait jamais transmis au
                          // serveur, qui retombait silencieusement sur
                          // OrderDeliveryMode.LIVRAISON par defaut (voir
                          // OrdersService.createVendorInitiated).
                          payload['deliveryMode'] = deliveryMode;
                          if (transportMode != null) {
                            payload['transportMode'] = transportMode;
                          }

                          final res = await ApiService.instance.client.post(
                            '/api/v1/orders/vendor-initiated',
                            data: payload,
                          );
                          final orderNumber = (res.data is Map)
                              ? ((res.data['order'] as Map?)?['orderNumber'] ?? '').toString()
                              : '';

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          widget.onChanged();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                orderNumber.isNotEmpty
                                    ? 'Commande $orderNumber créée — le client va recevoir la demande de paiement'
                                    : 'Commande créée — le client va recevoir la demande de paiement',
                                style: GoogleFonts.outfit(color: Colors.white),
                              ),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!ctx.mounted) return;
                          AppToast.show(
                            ctx,
                            message: _extractVendorOrderError(e),
                            type: ToastType.error,
                          );
                        } finally {
                          if (ctx.mounted) setSheetState(() => submittingOrder = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: submittingOrder
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
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
          );
        },
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
  final VoidCallback onConfirm;
  final VoidCallback onDetails;
  const _SellerOrderCard({
    required this.order,
    required this.onConfirm,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as OrderStatus;

    // « À confirmer avant JJ/MM HH:mm » : informatif seulement (rouge si la
    // date est dépassée). Le vendeur garde le bouton Confirmer ; aucune
    // annulation n'est possible côté vendeur.
    final confirmByRaw = order['confirmBy'];
    final confirmByDate =
        (order['rawStatus'] == 'en attente' && confirmByRaw is String)
            ? DateTime.tryParse(confirmByRaw)?.toLocal()
            : null;
    final confirmOverdue =
        confirmByDate != null && confirmByDate.isBefore(DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');

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
                Expanded(
                  child: Text(
                  order['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ),
                const SizedBox(width: 8),
                if (order['badgeAttente'] is String)
                  StatusBadgeWidget.custom(
                    label: order['badgeAttente'] as String,
                    backgroundColor: order['badgeAttente'] == 'À confirmer'
                        ? const Color(0xFFE3F2FD)
                        : const Color(0xFFFEF3C7),
                    textColor: order['badgeAttente'] == 'À confirmer'
                        ? const Color(0xFF1565C0)
                        : const Color(0xFFD97706),
                  )
                else
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
                      if (confirmByDate != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: confirmOverdue
                                ? AppTheme.errorContainer
                                : AppTheme.primaryMuted,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'À confirmer avant ${two(confirmByDate.day)}/${two(confirmByDate.month)} ${two(confirmByDate.hour)}:${two(confirmByDate.minute)}',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: confirmOverdue
                                  ? AppTheme.error
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
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
            // On garde ce bloc visible tant que la commande est active
            // (pas seulement en attente/en cours) : une fois le livreur
            // affecté ou la livraison en transit ("En livraison"), le
            // vendeur doit toujours pouvoir rouvrir "Détails" pour accéder
            // au bouton "Démarrer" / à la suite du suivi. Avant ce correctif,
            // toute la ligne de boutons — y compris "Détails" — disparaissait
            // dès que le statut quittait "en cours", rendant la commande
            // totalement inaccessible depuis la carte.
            if (status == OrderStatus.received ||
                status == OrderStatus.processing ||
                status == OrderStatus.inDelivery) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              if (status == OrderStatus.inDelivery)
                // Plus de "Confirmer" direct possible à ce stade (la suite
                // exige une preuve concrète) : seul "Détails" a un sens ici.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onDetails,
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
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDetails,
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
                        onPressed: onConfirm,
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
              ? _ScrollableEmpty(child: EmptyStateWidget(
                  icon: Icons.description_outlined,
                  title: 'Aucun devis',
                  description: _filter == 'Tous'
                      ? 'Aucune demande de sourcing reçue pour l\'instant.'
                      : 'Aucun devis dans la catégorie "$_filter".',
                ))
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
        child: SingleChildScrollView(
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
                      Expanded(
                        child: Text(
                        'Dépôt ${depositAmount.toStringAsFixed(0)} FCFA: ${depositPaid ? 'Payé ✓' : 'En attente'}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: depositPaid
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
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
                        // Wrap : "Reste" reste a droite si ca tient, sinon
                        // passe a la ligne (montants a 6-7 chiffres).
                        Expanded(
                          child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                        Text(
                          'Devis envoyé: ${devisAmount.toStringAsFixed(0)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          'Reste: ${(devisAmount - depositAmount).toStringAsFixed(0)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                          ],
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
  bool _isLoading = true;
  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  // Le stock vit par variante cote serveur (pas par produit), et il n'y a
  // pas d'ecran dedie pour ca : on aplati chaque variante de chaque produit
  // du vendeur en une ligne editable.
  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    try {
      final r = await ApiService.instance.client.get('/api/v1/products/vendor/me');
      final raw = r.data;
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
      final items = <Map<String, dynamic>>[];
      for (final p in list.whereType<Map>()) {
        final product = Map<String, dynamic>.from(p);
        final images = (product['images'] as List?)?.whereType<Map>().toList() ?? [];
        final imageUrl = images.isNotEmpty ? (images.first['url'] as String? ?? '') : '';
        final variants = (product['variants'] as List?)?.whereType<Map>().toList() ?? [];
        for (final v in variants) {
          final variant = Map<String, dynamic>.from(v);
          final descriptor = [variant['size'], variant['color']]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' / ');
          items.add({
            'productId': (product['id'] ?? '').toString(),
            'variantId': (variant['id'] ?? '').toString(),
            'name': descriptor.isNotEmpty
                ? '${product['prod_name'] ?? 'Produit'} ($descriptor)'
                : (product['prod_name']?.toString() ?? 'Produit'),
            'sku': (variant['sku'] ?? '—').toString(),
            'stock': (variant['stockQuantity'] as num?)?.toInt() ?? 0,
            'minStock': (variant['lowStockAlert'] as num?)?.toInt() ?? 5,
            'image': imageUrl,
          });
        }
      }
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(items);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStock(int index, int newQty) async {
    final item = _items[index];
    final previous = item['stock'] as int;
    setState(() => _items[index]['stock'] = newQty);

    try {
      await ApiService.instance.client.put(
        '/api/v1/products/${item['productId']}/variants/${item['variantId']}',
        data: {'stockQuantity': newQty},
      );
    } catch (_) {
      if (mounted) {
        setState(() => _items[index]['stock'] = previous);
        AppToast.show(
          context,
          message: 'Impossible de mettre à jour le stock.',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_items.isEmpty) {
      return const _ScrollableEmpty(
        child: EmptyStateWidget(
        icon: Icons.inventory_2_outlined,
        title: 'Aucun stock à afficher',
        description: 'Ajoute des produits pour suivre leur stock ici.',
      ),
      );
    }

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
              onUpdate: (newQty) => _updateStock(i, newQty),
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
          Expanded(
            child: Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
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
    // Le calcul reel des revenus vendeur (ventes, commissions, net) n'existe
    // pas encore cote serveur. On affiche un etat honnete plutot que des
    // chiffres inventes, en attendant que cette fonctionnalite soit construite.
    return const Center(
      child: EmptyStateWidget(
        icon: Icons.bar_chart_rounded,
        title: 'Bientôt disponible',
        description:
            'Le suivi de tes revenus arrive bientot. On y travaille.',
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
  bool _isLoading = true;
  bool _hasError = false;
  num _soldeDisponible = 0;
  num _totalRetire = 0;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/vendors/me/earnings');
      final data = res.data as Map<String, dynamic>;
      final historique = (data['historique'] as List?)
              ?.whereType<Map>()
              .map((h) => h.cast<String, dynamic>())
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _soldeDisponible =
              (double.tryParse(data['soldeDisponible']?.toString() ?? '') ?? 0);
          _totalRetire =
              (double.tryParse(data['totalRetire']?.toString() ?? '') ?? 0);
          _history = historique;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  static String _formatAmount(num amount) {
    final s = amount.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} FCFA';
  }

  static String _formatHistoryDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr.toString());
      const mois = [
        'jan', 'fév', 'mars', 'avr', 'mai', 'juin',
        'juil', 'août', 'sept', 'oct', 'nov', 'déc',
      ];
      return '${dt.day} ${mois[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return ConnectionErrorScreen(
        onRetry: _loadEarnings,
        title: 'Impossible de charger vos gains',
        message: 'Vérifiez votre connexion internet et réessayez.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEarnings,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceCard(),
            const SizedBox(height: 16),
            _buildWithdrawInfoCard(),
            const SizedBox(height: 20),
            Text(
              'Historique des reversements',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Aucun reversement pour le moment.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              ..._history.map((h) => _WithdrawalHistoryItem(item: {
                    'amount': _formatAmount(
                      (double.tryParse(h['montant']?.toString() ?? '') ?? 0),
                    ),
                    'method': h['orderNumber'] ?? '—',
                    'date': _formatHistoryDate(h['date']),
                    'status':
                        h['statut'] == 'payé' ? 'completed' : 'pending',
                  })),
          ],
        ),
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
            'Montant dû par Asoukaa (en attente de reversement)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white.withAlpha(160),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatAmount(_soldeDisponible),
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BalanceStat(
                label: 'Total déjà reversé',
                value: _formatAmount(_totalRetire),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Le bouton "Retrait via FeeXPay" a été retiré : il ouvrait en réalité
  // l'écran de PAIEMENT FeeXPay (le même composant que pour encaisser une
  // commande), ce qui aurait DÉBITÉ le vendeur au lieu de le payer. Tant
  // qu'un vrai circuit de reversement (paiement sortant) n'est pas mis en
  // place, le reversement reste géré manuellement par l'équipe Asoukaa.
  Widget _buildWithdrawInfoCard() {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.warning.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: AppTheme.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reversement géré par Asoukaa',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Le retrait automatique n\'est pas encore disponible dans '
                  'l\'application. L\'équipe Asoukaa vous reverse votre solde '
                  'directement (virement / mobile money) selon vos '
                  'coordonnées de paiement enregistrées.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.4,
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

  // Auparavant "Mars 2026" figé en dur, quel que soit le mois réel.
  static String _currentMonthLabel() {
    const mois = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    final now = DateTime.now();
    return '${mois[now.month - 1]} ${now.year}';
  }

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
    // Vrai compteur de visites boutique (GET /vendors/me → visitCount),
    // incrémenté à chaque ouverture de la page boutique par un acheteur.
    // Avant : "visitor_count" (snake_case, une clé qui n'existe pas côté
    // serveur) faisait toujours échouer la lecture, d'où le repli sur une
    // estimation inventée (totalViews * 3 / 2).
    final shopVisitors = (shop?['visitCount'] as num?)?.toInt() ?? 0;

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
                    Expanded(
                      child: Text(
                      'Statistiques Boutique',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: Colors.white.withAlpha(200),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    ),
                    const SizedBox(width: 8),
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
                        _currentMonthLabel(),
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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

/// Etat vide qui devient defilable quand la hauteur disponible est trop
/// petite (petits ecrans 360x640, police agrandie) au lieu d'afficher
/// "BOTTOM OVERFLOWED". Reste centre verticalement sinon.
class _ScrollableEmpty extends StatelessWidget {
  final Widget child;
  const _ScrollableEmpty({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}
