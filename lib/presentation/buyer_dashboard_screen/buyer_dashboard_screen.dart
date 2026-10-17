import 'dart:async';

import 'package:dio/dio.dart';
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
import '../../services/wishlist_service.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../utils/telephone.dart';
import '../../utils/paiement_annulation.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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

  Future<void> _fetchUnreadNotifications() async {
    try {
      final res = await ApiService.instance.client
          .get('/api/v1/notifications/unread-count');
      final count = res.data is Map ? res.data['unreadCount'] as int? : null;
      if (mounted) setState(() => _unreadNotifications = count ?? 0);
    } catch (_) {}
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

      final response = await ApiService.instance.client.get('/api/v1/orders/me');
      final rawList = response.data is List
          ? response.data as List
          : (response.data is Map
              ? (response.data['data'] as List? ?? [])
              : <dynamic>[]);

      List<Map<String, dynamic>> favorites = [];
      try {
        final wishlistRes =
            await ApiService.instance.client.get('/api/v1/wishlist');
        final wishlistRaw = wishlistRes.data is Map
            ? (wishlistRes.data['data'] as List? ?? [])
            : (wishlistRes.data is List ? wishlistRes.data as List : <dynamic>[]);
        favorites = wishlistRaw
            .whereType<Map>()
            .map((e) => _normalizeFavorite(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _orders = rawList
              .whereType<Map>()
              .map((e) => _normalizeOrder(Map<String, dynamic>.from(e)))
              .toList();
          _favorites = favorites;
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
      unawaited(_fetchUnreadNotifications());
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

  static Map<String, dynamic> _normalizeFavorite(Map<String, dynamic> w) {
    final product = w['product'] as Map<String, dynamic>? ?? {};

    final images =
        (product['images'] as List?)?.whereType<Map>().toList() ?? [];
    final imageUrl = images.isNotEmpty
        ? (images.first['url'] as String? ?? '')
        : 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';

    final vendor = product['vendor'] as Map<String, dynamic>?;
    final sellerName = vendor?['shopName'] as String? ?? 'Boutique Asoukaa';

    final rawPrice = product['basePrice'];
    final amount = rawPrice is num
        ? rawPrice.round()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 0).round();

    return {
      'id': (product['id'] ?? w['productId'] ?? '').toString(),
      'name': product['prod_name'] as String? ?? 'Produit',
      'seller': sellerName,
      'price': '${_formatPrice(amount)} FCFA',
      'image': imageUrl,
      'rating': product['noteMoyenne'] ?? 0,
      'inStock': true,
    };
  }

  static Map<String, dynamic> _normalizeOrder(Map<String, dynamic> o) {
    // ⚠️ Le backend renvoie la relation OneToMany sous le nom "items"
    // (pas "orderItems"), et chaque item pointe vers "variant.product"
    // (pas directement "product").
    final items = o['items'] as List<dynamic>? ?? [];
    final firstItem =
        items.isNotEmpty ? items[0] as Map<String, dynamic>? : null;
    final variant = firstItem?['variant'] as Map<String, dynamic>?;
    final product = (variant?['product']) as Map<String, dynamic>? ?? {};

    // Le backend renvoie le statut en français ('en attente', 'en cours',
    // 'expedié', 'livré', 'annulé') — il n'y a ni 'processing'/'shipped'
    // en anglais, ni de statut 'completed'/'failed' distinct côté serveur.
    final statusStr = (o['status'] as String? ?? '').toLowerCase();
    OrderStatus status;
    switch (statusStr) {
      case 'en cours':
        status = OrderStatus.processing;
      // "Livreur affecté" et "En transit" manquaient ici : la commande
      // retombait sur le cas par défaut ("Reçue"), ce qui faisait
      // reculer le statut affiché à l'acheteur en pleine livraison
      // (Cas A) — incohérent avec le tableau de bord vendeur, qui lui
      // gère déjà correctement ces deux valeurs.
      case 'livreur affecté':
      case 'expedié':
      case 'en transit':
        status = OrderStatus.inDelivery;
      case 'livré':
        status = OrderStatus.completed;
      case 'annulé':
        status = OrderStatus.cancelled;
      default:
        status = OrderStatus.received; // 'en attente' et cas par défaut
    }

    final steps = [
      true,
      ['en cours', 'livreur affecté', 'expedié', 'en transit', 'livré']
          .contains(statusStr),
      ['livreur affecté', 'expedié', 'en transit', 'livré']
          .contains(statusStr),
      statusStr == 'livré',
      statusStr == 'livré',
    ];

    // Le champ s'appelle "total" côté backend (pas "totalAmount"), et
    // TypeORM sérialise les colonnes "decimal" en chaîne de caractères
    // (ex: "15000.00"), pas en nombre JSON — un cast direct "as num"
    // plante ici (c'est ce qui causait l'écran "Impossible de charger
    // le tableau de bord" alors que l'appel API réussissait bien).
    final amount = (double.tryParse(o['total']?.toString() ?? '') ?? 0).toInt();
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
    // Numéro de commande officiel (même généré par le backend que sur
    // l'écran de suivi et le tableau de bord vendeur — voir orders.service.ts
    // generateOrderNumber). Avant : on reconstruisait toujours un faux code
    // à partir de l'UUID de la commande (ex "#ASK-BBD66C9F"), différent du
    // vrai numéro affiché ailleurs ("#ASK-2026-00007") pour la même commande.
    final realOrderNumber = (o['orderNumber'] as String?) ?? '';

    // Les images sont une liste (relation "images"), avec un booléen
    // "isPrimary" — pas un champ "imageUrl"/"image_url" direct.
    final images =
        (product['images'] as List?)?.whereType<Map>().toList() ?? [];
    Map? primaryImage;
    for (final img in images) {
      if (img['isPrimary'] == true) {
        primaryImage = img;
        break;
      }
    }
    primaryImage ??= images.isNotEmpty ? images.first : null;
    final imageUrl = primaryImage?['url'] as String? ??
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';

    // Le vendeur est une relation directe sur la commande (o['vendor']),
    // pas sur chaque item.
    final vendor = o['vendor'] as Map<String, dynamic>?;
    final sellerName = vendor?['shopName'] as String? ?? 'Boutique Asoukaa';

    // Adresse de livraison réelle (relation "address"), utilisée pour
    // pré-remplir l'écran de suivi détaillé quand on y navigue depuis ici.
    final address = o['address'] as Map<String, dynamic>?;
    final recipientName = (address?['nom_destinataire'] as String? ?? '').trim();
    final nameParts = recipientName.isNotEmpty ? recipientName.split(' ') : <String>[];
    final recipientFirstName = nameParts.isNotEmpty ? nameParts.first : '';
    final recipientLastName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    // Tous les articles de la commande (pas seulement le premier affiché),
    // avec leur variantId réel — nécessaire pour "Recommander".
    final cartItems = items
        .whereType<Map>()
        .map((it) {
          final v = it['variant'] as Map<String, dynamic>?;
          return {
            'variantId': v?['id'] as String? ?? '',
            'quantity': it['quantity'] as int? ?? 1,
          };
        })
        .where((e) => (e['variantId'] as String).isNotEmpty)
        .toList();

    // Paiement rattaché manuellement par le backend (getMyOrders) —
    // pas de relation directe Order -> Payment. Permet de savoir si
    // cette commande (notamment une commande initiée par le vendeur,
    // sans paiement créé à la création) attend encore d'être payée par
    // le client, pour afficher le bouton "Payer la commande".
    final payment = o['payment'] as Map<String, dynamic>?;
    final paymentStatus = payment?['status'] as String?;
    final paymentPending = statusStr == 'en attente'
        && (payment == null || paymentStatus == 'échoué');

    // Libellé d'une commande « en attente ». Depuis le nouveau flux, une
    // commande payée par Mobile Money RESTE « en attente » jusqu'au bouton
    // « Confirmer » du vendeur : l'ancien libellé « Reçue » ne disait pas si
    // c'est le client ou le vendeur qui doit agir. Même règle que le serveur
    // (computeConfirmBy) : paiement réussi, ou paiement à la livraison en
    // attente = c'est au vendeur de confirmer. Si la réponse ne contient pas
    // du tout l'information de paiement, on reste neutre (« En attente »).
    String? pendingLabel;
    if (statusStr == 'en attente') {
      if (!o.containsKey('payment')) {
        pendingLabel = 'En attente';
      } else {
        final payMethod = payment?['method'] as String?;
        final auVendeur = paymentStatus == 'success' ||
            (payMethod == 'cash_on_delivery' && paymentStatus == 'en attente');
        pendingLabel = auVendeur
            ? 'En attente de confirmation du vendeur'
            : 'En attente de paiement';
      }
    }

    return {
      'id': realOrderNumber.isNotEmpty ? '#$realOrderNumber' : '#ASK-$shortId',
      // UUID réel de la commande — nécessaire pour le suivi en direct
      // (GET /orders/{id}) et pour la navigation vers l'écran de suivi.
      'orderId': rawId,
      'orderNumber': o['orderNumber'] as String? ?? '',
      // Le champ s'appelle "prod_name" côté backend (pas "name")
      'product': product['prod_name'] as String? ?? 'Produit',
      'productId': (product['id'] ?? '').toString(),
      'seller': sellerName,
      'price': '${_formatPrice(amount)} FCFA',
      'image': imageUrl,
      'status': status,
      // Statut brut ('en attente', 'en cours', 'expedié', 'livré', 'annulé')
      // tel que renvoyé par le backend, pour l'écran de suivi.
      'rawStatus': statusStr,
      // Commande en attente sans paiement réussi ni tentative en cours :
      // affiche le bouton "Payer la commande" (voir _OrderCard).
      'paymentPending': paymentPending,
      // Libellé de la pastille pour une commande « en attente » (null sinon).
      'pendingLabel': pendingLabel,
      'steps': steps,
      'date': shortDate,
      'canReorder': status == OrderStatus.completed,
      'cartItems': cartItems,
      'address': address?['quartier'] as String? ?? '',
      'city': address?['ville'] as String? ?? '',
      'country': address?['country'] as String? ?? 'Bénin',
      'phone': address?['phone_destinataire'] as String? ?? '',
      'firstName': recipientFirstName,
      'lastName': recipientLastName,
    };
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
                // Cet écran EST l'onglet "Commandes" (index 3) : les autres
                // onglets poussent un nouvel écran par-dessus (pushNamed) et
                // laissent ce tableau de bord vivant en dessous. Sans le
                // remettre à 3 au retour, l'indicateur restait bloqué sur le
                // dernier onglet tapé (ex: "Profil") même une fois revenu ici.
                switch (i) {
                  case 0:
                    Navigator.pushReplacementNamed(context, '/home-screen');
                    break;
                  case 1:
                    setState(() => _currentNavIndex = i);
                    await Navigator.pushNamed(context, '/categories-screen');
                    if (mounted) setState(() => _currentNavIndex = 3);
                    break;
                  case 2:
                    setState(() => _currentNavIndex = i);
                    await Navigator.pushNamed(context, AppRoutes.conversationsInbox);
                    if (mounted) setState(() => _currentNavIndex = 3);
                    break;
                  case 3:
                    setState(() => _currentNavIndex = i);
                    break;
                  case 4:
                    setState(() => _currentNavIndex = i);
                    await Navigator.pushNamed(context, '/buyer-profile-screen');
                    if (mounted) setState(() => _currentNavIndex = 3);
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
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                        _fetchUnreadNotifications();
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Center(
                              child: Icon(
                                Icons.notifications_outlined,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ),
                            if (_unreadNotifications > 0)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(
                                    minWidth: 15,
                                    minHeight: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _unreadNotifications > 9
                                          ? '9+'
                                          : '$_unreadNotifications',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                    ),
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
              _OrdersTab(orders: _orders, onRefresh: _loadData),
              _FavoritesTab(favorites: _favorites),
              _OrderHistoryTab(history: _orders),
            ],
          ),
        ),
      ],
    );
  }

}

// ─────────────────────────────────────────────
// ORDERS TAB
// ─────────────────────────────────────────────

class _OrdersTab extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final VoidCallback onRefresh;

  const _OrdersTab({required this.orders, required this.onRefresh});

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
        return _OrderCard(order: order, onRefresh: onRefresh);
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

/// Pastille de statut d'une commande côté client : le libellé précis d'une
/// commande « en attente » (voir `pendingLabel`) remplace « Reçue » ; tous
/// les autres statuts gardent la pastille habituelle.
Widget _pastilleStatutCommande(Map<String, dynamic> order, OrderStatus status) {
  final libelle = order['pendingLabel'] as String?;
  if (libelle != null && libelle.isNotEmpty) {
    return StatusBadgeWidget.custom(
      label: libelle,
      backgroundColor: const Color(0xFFE3F2FD),
      textColor: const Color(0xFF1565C0),
    );
  }
  return StatusBadgeWidget.fromOrderStatus(status);
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  final VoidCallback onRefresh;

  const _OrderCard({required this.order, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as OrderStatus;
    final steps = order['steps'] as List<bool>;
    final isCancelled =
        status == OrderStatus.cancelled || status == OrderStatus.failed;

    return GestureDetector(
      onTap: () {
        final orderId = order['orderId'] as String?;
        if (orderId == null || orderId.isEmpty) return;
        // On rafraîchit la liste au retour de l'écran de suivi : sans ça,
        // la carte gardait le statut chargé AVANT l'ouverture du suivi
        // (ex: encore "En livraison" alors que la livraison venait
        // d'être confirmée sur l'écran de suivi lui-même).
        Navigator.pushNamed(
          context,
          AppRoutes.orderTracking,
          arguments: {
            'orderId': orderId,
            'productId': order['productId'],
            'status': order['rawStatus'],
            // On transmet le libellé déjà calculé par la liste. Le détail d'une
            // commande (GET /orders/me/:id) renvoie aussi `payment`, et l'écran
            // de suivi s'en sert pour déduire ce libellé s'il n'est pas transmis.
            'pendingLabel': order['pendingLabel'],
            'orderNumber': order['orderNumber'],
            'firstName': order['firstName'],
            'lastName': order['lastName'],
            'address': order['address'],
            'city': order['city'],
            'country': order['country'],
            'phone': order['phone'],
          },
        ).then((_) => onRefresh());
      },
      child: Container(
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
                const SizedBox(width: 8),
                // Expanded + Align : le libellé « En attente de confirmation
                // du vendeur » est long et peut passer sur deux lignes.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _pastilleStatutCommande(order, status),
                  ),
                ),
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
          // Commande en attente de paiement (notamment une commande
          // initiée par le vendeur pour ce client : voir
          // OrdersService.createVendorInitiated côté backend, qui ne crée
          // plus de paiement à la création) : c'est au client de payer,
          // via le même flux Mobile Money qu'une commande normale.
          if (order['paymentPending'] == true) ...[
            const Divider(height: 1, color: AppTheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 18, color: Colors.white),
                  label: Text(
                    'Payer la commande',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _payOrder(context, order, onRefresh),
                ),
              ),
            ),
          ],
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// CLIENT — PAYER UNE COMMANDE EN ATTENTE (Mobile Money)
// Meme flux que le paiement normal au checkout (checkout_screen.dart) :
// POST /api/v1/payments/initiate avec method 'mobile_money' + operator +
// phoneNumber, puis polling GET /api/v1/payments/{id}/status. Le montant
// (frais de livraison inclus, deja calcules selon la commune a la
// creation de la commande) est determine cote serveur a partir de
// order.total -- le client n'a rien a ressaisir.
// ─────────────────────────────────────────────────────
Future<void> _payOrder(
  BuildContext context,
  Map<String, dynamic> order,
  VoidCallback onRefresh,
) async {
  final orderId = order['orderId'] as String?;
  if (orderId == null || orderId.isEmpty) return;

  // Un paiement de cette commande est « en cours de verification » : on
  // n'ouvre pas la feuille de paiement (pas de second paiement immediat).
  if (PaiementsEnVerification.estEnVerification(<String>[orderId])) {
    await _afficherVerificationEnCours(
      context,
      messagePaiementEnVerification,
    );
    return;
  }

  String selectedOperator = 'MTN';
  final phoneCtrl =
      TextEditingController(text: (order['phone'] as String?) ?? '');
  bool submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
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
              Text(
                'Payer la commande ${order['id'] ?? ''}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Montant : ${order['price'] ?? ''}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedOperator,
                isExpanded: true,
                onChanged: (v) =>
                    setSheetState(() => selectedOperator = v ?? 'MTN'),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Operateur Mobile Money',
                  prefixIcon: const Icon(
                    Icons.sim_card_outlined,
                    size: 18,
                    color: AppTheme.muted,
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const ['MTN', 'Moov']
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Numero Mobile Money',
                  prefixIcon: const Icon(
                    Icons.phone_outlined,
                    size: 18,
                    color: AppTheme.muted,
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (phoneCtrl.text.trim().isEmpty) {
                            AppToast.show(
                              ctx,
                              message:
                                  'Renseignez le numero Mobile Money.',
                              type: ToastType.error,
                            );
                            return;
                          }
                          setSheetState(() => submitting = true);
                          try {
                            final payResp =
                                await ApiService.instance.client.post(
                              '/api/v1/payments/initiate',
                              data: {
                                'orderId': orderId,
                                'method': 'mobile_money',
                                'operator': selectedOperator,
                                'phoneNumber': normaliserTelephone(phoneCtrl.text),
                              },
                            );
                            final payData = payResp.data;
                            final paymentId = payData is Map
                                ? payData['paymentId'] as String?
                                : null;
                            final payMessage = payData is Map
                                ? payData['message'] as String?
                                : null;
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!context.mounted) return;
                            AppToast.show(
                              context,
                              message: payMessage ??
                                  'Demande de paiement envoyee.',
                              type: ToastType.success,
                            );
                            if (paymentId != null) {
                              _pollOrderPaymentStatus(
                                context,
                                paymentId,
                                onRefresh,
                                orderId: orderId,
                              );
                            }
                          } on DioException catch (e) {
                            final errData = e.response?.data;
                            final backendMessage =
                                errData is Map ? errData['message'] : null;
                            final texteServeur = backendMessage is String
                                ? backendMessage
                                : (backendMessage is List &&
                                        backendMessage.isNotEmpty
                                    ? backendMessage.first.toString()
                                    : '');
                            if (estMessageVerificationEnCours(texteServeur)) {
                              // Le serveur refuse un second paiement : le
                              // premier est encore en cours de verification.
                              // Message du serveur affiche tel quel.
                              PaiementsEnVerification.marquer(
                                <String>[orderId],
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (!context.mounted) return;
                              await _afficherVerificationEnCours(
                                context,
                                texteServeur,
                              );
                              if (context.mounted) onRefresh();
                              return;
                            }
                            if (!ctx.mounted) return;
                            AppToast.show(
                              ctx,
                              message: backendMessage is String
                                  ? backendMessage
                                  : (backendMessage is List &&
                                          backendMessage.isNotEmpty
                                      ? backendMessage.first.toString()
                                      : 'Le paiement a echoue. Reessayez.'),
                              type: ToastType.error,
                            );
                            setSheetState(() => submitting = false);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            AppToast.show(
                              ctx,
                              message:
                                  'Une erreur est survenue. Reessayez.',
                              type: ToastType.error,
                            );
                            setSheetState(() => submitting = false);
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
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Valider le paiement',
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

// Boite d'information : le paiement est « en cours de verification »
// (non confirme mais NON annule). On ne parle pas d'echec et on ne propose
// pas de repayer.
Future<void> _afficherVerificationEnCours(
  BuildContext context,
  String message,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Vérification en cours',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          content: Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Compris',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// Interroge GET /payments/{id}/status jusqu'a confirmation, echec ou
// delai depasse -- meme logique que _pollPaymentStatus dans
// checkout_screen.dart, reutilisee ici pour le paiement d'une commande
// deja creee (notamment une commande initiee par le vendeur).
// A l'abandon de l'attente, PATCH /payments/{id}/cancel peut repondre :
// 'success' (le paiement etait confirme), 'en attente' + verificationEnCours
// (non confirme mais non annule : on previent le client, pas de nouveau
// paiement immediat) ou 'echoue' / ancien serveur (comportement d'avant).
Future<void> _pollOrderPaymentStatus(
  BuildContext context,
  String paymentId,
  VoidCallback onRefresh, {
  String? orderId,
}) async {
  const maxAttempts = 40;
  const pollInterval = Duration(seconds: 3);
  var dialogOpen = true;
  // Vrai des que l'issue est connue (confirme, ou en verification) : evite
  // un double message quand le polling et le bouton « Annuler l'attente » se
  // croisent.
  var resolu = false;
  // Passe a true apres ~90 s : le texte de la boite d'attente change.
  final attenteLongue = ValueNotifier<bool>(false);
  final idsCommande = <String>[if (orderId != null) orderId];

  if (!context.mounted) return;

  Future<void> paiementConfirme() async {
    if (resolu) return;
    resolu = true;
    PaiementsEnVerification.oublier(idsCommande);
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: 'Paiement confirmé. Votre commande a été transmise au vendeur pour confirmation.',
      type: ToastType.success,
    );
    onRefresh();
  }

  Future<void> annuler({required bool apresDelai}) async {
    ReponseAnnulationPaiement? reponseBrute;
    try {
      final resp = await ApiService.instance.client
          .patch('/api/v1/payments/$paymentId/cancel');
      reponseBrute = lireReponseAnnulation(resp.data);
    } catch (_) {
      // best-effort : si ca echoue (reseau coupe...), on ne sait pas ce
      // qu'a fait le serveur ; on garde le comportement d'avant.
      reponseBrute = null;
    }
    final reponse = reponseBrute;

    if (reponse != null && reponse.issue == IssueAnnulation.reussi) {
      await paiementConfirme();
      return;
    }

    if (reponse != null &&
        reponse.issue == IssueAnnulation.verificationEnCours) {
      if (resolu) return;
      resolu = true;
      PaiementsEnVerification.marquer(idsCommande);
      await _afficherVerificationEnCours(
        context,
        reponse.messageVerification,
      );
      if (context.mounted) onRefresh();
      return;
    }

    // Echec confirme / ancien serveur / appel impossible : comportement d'avant.
    if (reponse != null) PaiementsEnVerification.oublier(idsCommande);
    if (!context.mounted) return;
    if (apresDelai) {
      AppToast.show(
        context,
        message: (reponse != null && reponse.echecConfirme)
            ? reponse.messageEchec
            : 'Delai depasse. Verifiez le statut de votre commande plus tard.',
        type: ToastType.error,
      );
    }
    onRefresh();
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Confirmez le paiement sur votre telephone',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: attenteLongue,
                builder: (builderContext, longue, _) {
                  return Text(
                    longue
                        ? 'Toujours en attente de votre validation sur le '
                            'téléphone… Ne fermez pas l\'application et ne '
                            'payez pas une seconde fois.'
                        : 'Validez la demande de paiement mobile money recue '
                            'sur votre telephone. Ne fermez pas '
                            'l\'application.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await annuler(apresDelai: false);
              },
              child: Text(
                'Annuler l\'attente',
                style: GoogleFonts.outfit(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    },
  ).then((_) => dialogOpen = false);

  void closeDialog() {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    dialogOpen = false;
  }

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await Future.delayed(pollInterval);
    if (!dialogOpen || !context.mounted) return;

    // ~90 s ecoulees (30 interrogations x 3 s) : message plus rassurant.
    if (attempt == 29) attenteLongue.value = true;

    try {
      final statusResp = await ApiService.instance.client
          .get('/api/v1/payments/$paymentId/status');
      final statusData = statusResp.data;
      final status =
          statusData is Map ? statusData['status']?.toString() : null;

      if (status == 'success') {
        closeDialog();
        await paiementConfirme();
        return;
      }

      if (status == 'echoue' || status == 'échoué') {
        closeDialog();
        PaiementsEnVerification.oublier(idsCommande);
        if (!context.mounted) return;
        AppToast.show(
          context,
          message:
              'Le paiement a echoue ou a ete annule. Vous pouvez reessayer.',
          type: ToastType.error,
        );
        return;
      }
      // Sinon toujours "en attente" -- on continue le polling.
    } catch (_) {
      // Erreur reseau ponctuelle pendant le polling -- on retente au
      // prochain cycle plutot que d'abandonner tout de suite.
    }
  }

  // Delai depasse sans confirmation ni echec explicite : on demande au
  // serveur d'annuler, mais il peut repondre « deja confirme » ou
  // « en cours de verification » (voir annuler ci-dessus).
  final etaitOuverte = dialogOpen;
  closeDialog();
  if (!etaitOuverte) return;
  await annuler(apresDelai: true);
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

  Future<void> _removeFavorite(int index) async {
    final productId = (_favorites[index]['id'] ?? '').toString();
    if (productId.isEmpty) return;
    try {
      await ApiService.instance.client.delete('/api/v1/wishlist/$productId');
      WishlistService.instance.refreshCount();
      if (mounted) {
        setState(() => _favorites.removeAt(index));
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
          onRemove: () => _removeFavorite(index),
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

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.productDetail,
        arguments: item,
      ),
      child: Container(
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

  Future<void> _reorder(BuildContext context) async {
    final cartItems = (item['cartItems'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .toList();
    if (cartItems.isEmpty) {
      AppToast.show(
        context,
        message: 'Impossible de recommander cet article.',
        type: ToastType.error,
      );
      return;
    }
    var addedCount = 0;
    for (final ci in cartItems) {
      final variantId = ci['variantId'] as String? ?? '';
      final quantity = ci['quantity'] as int? ?? 1;
      if (variantId.isEmpty) continue;
      try {
        await ApiService.instance.client.post(
          '/api/v1/cart/items',
          data: {'variantId': variantId, 'quantity': quantity},
        );
        addedCount++;
      } catch (_) {
        // On continue avec les autres articles même si l'un échoue
        // (ex: stock épuisé entre-temps) plutôt que d'abandonner.
      }
    }
    if (!context.mounted) return;
    if (addedCount > 0) {
      AppToast.show(
        context,
        message: addedCount == cartItems.length
            ? 'Article(s) ajouté(s) au panier.'
            : 'Certains articles ont été ajoutés au panier (stock '
                'insuffisant pour les autres).',
        type: ToastType.success,
      );
      Navigator.pushNamed(context, AppRoutes.cart);
    } else {
      AppToast.show(
        context,
        message: 'Impossible d\'ajouter ces articles au panier (stock épuisé ?).',
        type: ToastType.error,
      );
    }
  }

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
                    const SizedBox(width: 6),
                    Flexible(child: _pastilleStatutCommande(item, status)),
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
                        onTap: () => _reorder(context),
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
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final response =
          await ApiService.instance.client.get('/api/v1/notifications?limit=10');
      final rawData = response.data;
      final rawList = rawData is List
          ? rawData
          : (rawData is Map
              ? (rawData['data'] ?? rawData['items'] ?? []) as List
              : <dynamic>[]);
      if (mounted) {
        setState(() {
          _notifications = rawList
              .whereType<Map>()
              .map((e) => _normalizeNotif(Map<String, dynamic>.from(e)))
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'commande':
        return Icons.inventory_2_rounded;
      case 'livraison':
        return Icons.local_shipping_rounded;
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  static Color _colorForType(String type) {
    switch (type) {
      case 'commande':
        return const Color(0xFF7C3AED);
      case 'livraison':
        return AppTheme.primary;
      case 'chat':
        return AppTheme.primary;
      case 'promo':
        return const Color(0xFFD97706);
      default:
        return AppTheme.muted;
    }
  }

  static String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
      if (diff.inDays == 1) return 'Hier';
      return 'Il y a ${diff.inDays} jours';
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic> _normalizeNotif(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? 'systeme';
    final color = _colorForType(type);
    return {
      'id': (n['id'] ?? '').toString(),
      'icon': _iconForType(type),
      'iconColor': color,
      'iconBg': color.withAlpha(30),
      'title': n['title'] as String? ?? '',
      'body': n['body'] as String? ?? '',
      'time': _formatDate(n['createdAt'] as String?),
      'isRead': n['isRead'] == true,
    };
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.instance.client
          .patch('/api/v1/notifications/mark-all-read');
    } catch (_) {}
    if (mounted) {
      setState(() {
        for (final n in _notifications) {
          n['isRead'] = true;
        }
      });
    }
  }

  Future<void> _markRead(Map<String, dynamic> notif) async {
    final id = notif['id'] as String? ?? '';
    if (id.isEmpty || notif['isRead'] == true) return;
    setState(() => notif['isRead'] = true);
    try {
      await ApiService.instance.client.patch(
        '/api/v1/notifications/mark-read',
        data: {'ids': [id]},
      );
    } catch (_) {}
  }

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
                  onTap: _markAllRead,
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _notifications.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.notifications_none_rounded,
                  title: 'Aucune notification',
                  description: 'Vous serez prévenu ici de toute activité sur votre compte.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    return _NotificationCard(
                      notif: notif,
                      onTap: () => _markRead(notif),
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
