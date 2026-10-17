import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../routes/app_routes.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../services/deliverer_availability.dart';

class DelivererDashboardScreen extends StatefulWidget {
  const DelivererDashboardScreen({super.key});

  @override
  State<DelivererDashboardScreen> createState() =>
      _DelivererDashboardScreenState();
}

class _DelivererDashboardScreenState extends State<DelivererDashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  // Sur ce dashboard, l'onglet "Commandes" (index 3) EST l'écran courant :
  // les missions du livreur sont son équivalent de "mes commandes". Avant,
  // cette valeur était à 4 ("Profil"), qui se retrouvait donc surligné à
  // tort comme onglet actif alors qu'on n'est pas sur le profil.
  int _currentNavIndex = 3;
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  // Vraies donnees — issues de GET /api/v1/delivery/me, reparties
  // selon le statut de la livraison (chaine backend :
  // assigné → récupéré → en cours de livraison → livré / échouée)
  List<Map<String, dynamic>> _assignedMissions = [];   // a recuperer
  List<Map<String, dynamic>> _pickedUpMissions = [];   // colis recuperes
  List<Map<String, dynamic>> _inTransitMissions = [];  // en cours de livraison
  List<Map<String, dynamic>> _finishedMissions = [];   // livrees / echouees
  int _pendingDeliveryRequestsCount = 0;

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
    // Le badge de notifications doit être à jour dès l'ouverture de
    // l'écran, et re-synchronisé quand l'app revient au premier plan
    // (d'où l'observer de cycle de vie, voir didChangeAppLifecycleState).
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.refreshUnreadCount();
    _loadData();
    _connectivityService.onConnectivityChanged.listen((results) {
      final isOnline =
          !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (isOnline && (_hasConnectionError || _isOfflineCached)) {
        _loadData();
      }
    });
  }

  // Convertit une livraison du backend vers la forme attendue par les
  // cartes de cet ecran. Les champs que le backend ne fournit pas
  // (distance, ETA, poids) restent volontairement vides : mieux vaut
  // un tiret honnete qu'une valeur inventee.
  static Map<String, dynamic> _normalizeDelivery(Map<String, dynamic> d) {
    final order   = d['order']   as Map<String, dynamic>?;
    final address = order?['address'] as Map<String, dynamic>?;
    final vendor  = order?['vendor']  as Map<String, dynamic>?;
    final items   = (order?['items'] as List?) ?? const [];

    final produits = items
        .whereType<Map>()
        .map((it) {
          final variant = it['variant'] as Map?;
          final product = variant?['product'] as Map?;
          return product?['prod_name']?.toString();
        })
        .whereType<String>()
        .toList();

    final rawStatus = d['status']?.toString() ?? '';
    final fee = double.tryParse(order?['fraisLivraison']?.toString() ?? '') ?? 0;

    String statusColor;
    switch (rawStatus) {
      case 'assigné':
        statusColor = 'warning';
        break;
      case 'récupéré':
      case 'en cours de livraison':
        statusColor = 'primary';
        break;
      default:
        statusColor = 'success';
    }

    final destination = [
      address?['quartier']?.toString(),
      address?['ville']?.toString(),
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return {
      'rawId':       d['id']?.toString() ?? '',
      'rawStatus':   rawStatus,
      'id':          order?['orderNumber']?.toString() ?? '—',
      'pickup':      d['pickupAddress']?.toString() ?? '—',
      'delivery':    d['adresseLivraison']?.toString() ??
                     (destination.isEmpty ? '—' : destination),
      'address':     d['adresseLivraison']?.toString() ??
                     (destination.isEmpty ? '—' : destination),
      'buyer':       address?['nom_destinataire']?.toString() ?? '—',
      'seller':      vendor?['shopName']?.toString() ?? '—',
      'description': produits.isEmpty ? '—' : produits.join(', '),
      'category':    produits.isEmpty ? '—' : produits.first,
      'reward':      '${fee.round()} FCFA',
      'rewardValue': fee,
      'distance':    '—',
      'eta':         '—',
      'weight':      '—',
      'deadline':    '—',
      'status':      rawStatus.isEmpty ? '—' : rawStatus,
      'statusColor': statusColor,
      'instructions': d['instructions']?.toString() ?? '',
      'latitude':    (d['latitude'] as num?)?.toDouble(),
      'longitude':   (d['longitude'] as num?)?.toDouble(),
    };
  }

  // Fait avancer une livraison dans la chaine de statuts backend.
  Future<void> _updateDeliveryStatus(String deliveryId, String status) async {
    try {
      await ApiService.instance.client.patch(
        '/api/v1/delivery/$deliveryId/status',
        data: {'status': status},
      );
      await _loadData();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de mettre à jour cette livraison.'),
          ),
        );
      }
    }
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

      // Badge « En ligne / Hors ligne » : état réel de disponibilité
      // (silencieux en cas d'échec, sans attendre le reste du chargement).
      DelivererAvailability.instance.refresh();

      final List<Map<String, dynamic>> assigned = [];
      final List<Map<String, dynamic>> pickedUp = [];
      final List<Map<String, dynamic>> inTransit = [];
      final List<Map<String, dynamic>> finished = [];
      int pendingCount = 0;
      // true si le chargement de « mes livraisons » a échoué : on affiche
      // alors une erreur + « Réessayer » au lieu d'un faux « 0 mission ».
      var echecLivraisons = false;

      // Mes livraisons (commandes marketplace affectées par les vendeurs)
      try {
        final r = await ApiService.instance.client.get(
          '/api/v1/delivery/me',
          queryParameters: {'limit': 100},
        );
        final raw = r.data;
        final list = raw is List
            ? raw
            : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        for (final e in list.whereType<Map>()) {
          final d = _normalizeDelivery(Map<String, dynamic>.from(e));
          switch (d['rawStatus']) {
            case 'assigné':
              assigned.add(d);
              break;
            case 'récupéré':
              pickedUp.add(d);
              break;
            case 'en cours de livraison':
              inTransit.add(d);
              break;
            case 'livré':
            case 'livraison echouée':
              finished.add(d);
              break;
          }
        }
      } catch (_) {
        echecLivraisons = true;
      }
      if (echecLivraisons) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasConnectionError = true;
          });
        }
        return;
      }

      // Courses express disponibles (livraisons indépendantes)
      try {
        final r = await ApiService.instance.client
            .get('/api/v1/delivery/independent/available');
        final raw = r.data;
        final list = raw is List
            ? raw
            : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        pendingCount = list.length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _assignedMissions = assigned;
          _pickedUpMissions = pickedUp;
          _inTransitMissions = inTransit;
          _finishedMissions = finished;
          _pendingDeliveryRequestsCount = pendingCount;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Retour au premier plan : des notifications ont pu arriver pendant
    // que l'app était en arrière-plan.
    if (state == AppLifecycleState.resumed) {
      NotificationService.instance.refreshUnreadCount();
    }
  }

  // Ouvre l'écran de notifications existant, puis rafraîchit le compteur au
  // retour : les notifications consultées ont été marquées lues côté
  // serveur, le badge doit donc redescendre.
  Future<void> _openNotifications() async {
    await Navigator.pushNamed(context, AppRoutes.notifications);
    if (!mounted) return;
    await NotificationService.instance.refreshUnreadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  // Cloche de notifications + badge compteur, même style visuel que le badge
  // des messages non lus de AsoukaaBottomNav (pastille orange, liseré blanc,
  // "9+" au-delà de 9) pour rester cohérent partout dans l'app.
  //
  // Le compteur vient de NotificationService.unreadCountNotifier : pas de
  // state local ici, le badge se met à jour tout seul dès que n'importe
  // quel écran rafraîchit le compteur.
  Widget _buildNotificationsButton() {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unreadCountNotifier,
      builder: (context, unreadCount, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.primary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Notifications',
                onPressed: _openNotifications,
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                top: -3,
                right: -3,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
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
                    // "Commandes" == ce dashboard pour un livreur (ses
                    // missions sont son équivalent de "mes commandes") :
                    // rien à faire, on y est déjà.
                    break;
                  case 4:
                    Navigator.pushNamed(context, AppRoutes.delivererProfile);
                    break;
                }
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      // 104 ne suffisait pas : titre + sous-titre + badge "En ligne" + barre
      // d'onglets dépassaient de 16px (RenderFlex overflow visible en debug).
      preferredSize: const Size.fromHeight(120),
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
                    // Expanded + ellipsis à la place de l'ancien Spacer : la
                    // barre du haut porte maintenant un bouton de plus (la
                    // cloche), et sur un petit écran le titre doit se
                    // tronquer au lieu de faire déborder la Row.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Espace Livreur',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Cotonou & Environs',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Vrai état de disponibilité du livreur (isAvailableNow),
                    // partagé avec l'interrupteur du profil. Tant qu'il n'est
                    // pas connu, rien n'est affiché (pas de faux « En ligne »).
                    ValueListenableBuilder<bool?>(
                      valueListenable:
                          DelivererAvailability.instance.isAvailable,
                      builder: (context, available, _) {
                        if (available == null) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: available
                                ? AppTheme.successContainer
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: available
                                      ? AppTheme.success
                                      : AppTheme.muted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                available ? 'En ligne' : 'Hors ligne',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: available
                                      ? AppTheme.success
                                      : AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildNotificationsButton(),
                    const SizedBox(width: 10),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.delivery_dining_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.delivererProfile,
                          );
                        },
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
        tabs: [
          const Tab(text: 'Disponibles'),
          const Tab(text: 'En Cours'),
          const Tab(text: 'Récupérés'),
          const Tab(text: 'Livrés'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Courses'),
                if (_pendingDeliveryRequestsCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_pendingDeliveryRequestsCount',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'Revenus'),
          const Tab(text: 'Retrait'),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const DashboardMissionSkeleton(),
      );
    }
    if (_hasConnectionError) {
      return ConnectionErrorScreen(
        onRetry: _loadData,
        title: 'Impossible de charger l\'espace livreur',
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
              _MissionsDisponiblesTab(
                missions: _assignedMissions,
                onAction: _updateDeliveryStatus,
                onRefresh: _loadData,
              ),
              _MissionsEnCoursTab(
                missions: _inTransitMissions,
                onAction: _updateDeliveryStatus,
                onRefresh: _loadData,
              ),
              _ColisRecuperesTab(
                colis: _pickedUpMissions,
                onAction: _updateDeliveryStatus,
              ),
              _ColisLivresTab(colis: _finishedMissions),
              const _CoursesExpressTab(),
              const _RevenusTab(),
              const _RetraitTab(),
            ],
          ),
        ),
      ],
    );
  }

}

// ─────────────────────────────────────────────────────────────
// TAB 1 — Missions Disponibles
// ─────────────────────────────────────────────────────────────
class _MissionsDisponiblesTab extends StatelessWidget {
  final List<Map<String, dynamic>> missions;
  final Future<void> Function(String deliveryId, String status) onAction;
  final Future<void> Function() onRefresh;
  const _MissionsDisponiblesTab({
    required this.missions,
    required this.onAction,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (missions.isEmpty) {
      return const Center(
        child: _EmptyMissions(
          icon: Icons.local_shipping_outlined,
          message: 'Aucune mission à récupérer',
          subtitle: 'Les vendeurs vous affectent leurs livraisons ici',
        ),
      );
    }
    final total = missions.fold<double>(
      0,
      (s, m) => s + ((m['rewardValue'] as num?)?.toDouble() ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'À récupérer',
              value: '${missions.length}',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.primary,
            ),
            _SummaryItem(
              label: 'Frais livraison',
              value: '${total.round()} F',
              icon: Icons.payments_outlined,
              color: AppTheme.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...missions.map(
          (m) => _MissionCard(
            mission: m,
            primaryLabel: 'Récupérer',
            onPrimaryAction: () async {
              // Le ramassage exige une preuve (photo + état du colis) —
              // elle déclenche elle-même le passage à "récupéré" côté
              // serveur, on ne bascule plus le statut directement ici.
              final result = await Navigator.pushNamed(
                context,
                '/delivery-proof-screen',
                arguments: {
                  'deliveryId': m['rawId']?.toString() ?? '',
                  'mode': 'pickup',
                  'id': m['id'],
                  'client': m['buyer'] ?? m['client'],
                  'address': m['address'],
                  'items': m['description'],
                  'weight': m['weight'],
                  'amount': m['reward'],
                  'phone': m['phone'] ?? '',
                },
              );
              if (result == true) await onRefresh();
            },
          ),
        ),
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final String primaryLabel;
  final VoidCallback? onPrimaryAction;
  const _MissionCard({
    required this.mission,
    this.primaryLabel = 'Accepter',
    this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        mission['id'],
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.outlineVariant),
                      ),
                      child: Text(
                        mission['category'],
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      mission['reward'],
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RouteRow(
                  pickup: mission['pickup'],
                  delivery: mission['delivery'],
                  latitude: mission['latitude'] as double?,
                  longitude: mission['longitude'] as double?,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _InfoChip(
                      icon: Icons.straighten_rounded,
                      label: mission['distance'],
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.scale_rounded,
                      label: mission['weight'],
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.schedule_rounded,
                      label: 'Avant ${mission['deadline']}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      'Détails',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 36, color: AppTheme.outlineVariant),
                Expanded(
                  child: TextButton(
                    onPressed: onPrimaryAction,
                    child: Text(
                      primaryLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
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
}

// ─────────────────────────────────────────────────────────────
// TAB 2 — Missions En Cours
// ─────────────────────────────────────────────────────────────
class _MissionsEnCoursTab extends StatelessWidget {
  final List<Map<String, dynamic>> missions;
  final Future<void> Function(String deliveryId, String status) onAction;
  final Future<void> Function() onRefresh;
  const _MissionsEnCoursTab({
    required this.missions,
    required this.onAction,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (missions.isEmpty) {
      return const Center(
        child: _EmptyMissions(
          icon: Icons.directions_bike_rounded,
          message: 'Aucune livraison en cours',
          subtitle: 'Démarrez une livraison depuis Colis récupérés',
        ),
      );
    }
    final total = missions.fold<double>(
      0,
      (s, m) => s + ((m['rewardValue'] as num?)?.toDouble() ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'En cours',
              value: '${missions.length}',
              icon: Icons.directions_bike_rounded,
              color: AppTheme.warning,
            ),
            _SummaryItem(
              label: 'Frais livraison',
              value: '${total.round()} F',
              icon: Icons.payments_outlined,
              color: AppTheme.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...missions.map(
          (m) => _EnCoursCard(
            mission: m,
            primaryLabel: 'Marquer livré',
            onPrimaryAction: () async {
              // La remise finale exige une preuve (scan du QR du
              // client + GPS + signature) — c'est elle qui déclenche
              // "Livrée", jamais un simple clic.
              final result = await Navigator.pushNamed(
                context,
                '/delivery-proof-screen',
                arguments: {
                  'deliveryId': m['rawId']?.toString() ?? '',
                  'mode': 'handoff',
                  'id': m['id'],
                  'client': m['buyer'] ?? m['client'],
                  'address': m['address'],
                  'items': m['description'],
                  'weight': m['weight'],
                  'amount': m['reward'],
                  'phone': m['phone'] ?? '',
                },
              );
              if (result == true) await onRefresh();
            },
            secondaryLabel: 'Échec',
            onSecondaryAction: () =>
                onAction(m['rawId']?.toString() ?? '', 'livraison echouée'),
          ),
        ),
      ],
    );
  }
}

class _EnCoursCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final String primaryLabel;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onSecondaryAction;
  final String secondaryLabel;
  const _EnCoursCard({
    required this.mission,
    this.primaryLabel = 'Confirmer',
    this.onPrimaryAction,
    this.secondaryLabel = 'Appeler',
    this.onSecondaryAction,
  });

  Color _statusColor() {
    switch (mission['statusColor']) {
      case 'warning':
        return AppTheme.warning;
      case 'primary':
        return AppTheme.primary;
      default:
        return AppTheme.success;
    }
  }

  Color _statusBg() {
    switch (mission['statusColor']) {
      case 'warning':
        return AppTheme.warningContainer;
      case 'primary':
        return AppTheme.primaryMuted;
      default:
        return AppTheme.successContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  mission['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusBg(),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    mission['status'],
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _RouteRow(
              pickup: mission['pickup'],
              delivery: mission['delivery'],
              latitude: mission['latitude'] as double?,
              longitude: mission['longitude'] as double?,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  mission['buyer'],
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  'ETA: ${mission['eta']}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSecondaryAction,
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    label: Text(secondaryLabel, style: GoogleFonts.outfit()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onPrimaryAction,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text(primaryLabel, style: GoogleFonts.outfit()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
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

// ─────────────────────────────────────────────────────────────
// TAB 3 — Colis Récupérés
// ─────────────────────────────────────────────────────────────
class _ColisRecuperesTab extends StatelessWidget {
  final List<Map<String, dynamic>> colis;
  final Future<void> Function(String deliveryId, String status) onAction;
  const _ColisRecuperesTab({required this.colis, required this.onAction});

  @override
  Widget build(BuildContext context) {
    if (colis.isEmpty) {
      return const Center(
        child: _EmptyMissions(
          icon: Icons.inventory_2_outlined,
          message: 'Aucun colis récupéré',
          subtitle: 'Récupérez un colis depuis Missions disponibles',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'Récupérés',
              value: '${colis.length}',
              icon: Icons.inventory_2_outlined,
              color: AppTheme.primary,
            ),
            _SummaryItem(
              label: 'À livrer',
              value: '${colis.length}',
              icon: Icons.pending_actions_rounded,
              color: AppTheme.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warning.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 16, color: AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'En attente que le vendeur démarre la livraison',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        // Le livreur n'a plus d'action ici : la preuve de ramassage a
        // déjà été fournie (voir Missions disponibles), et c'est
        // désormais le vendeur qui démarre la livraison depuis son
        // propre tableau de bord.
        ...colis.map(
          (c) => _ColisCard(
            colis: c,
            showDeliverButton: false,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB 4 — Colis Livrés
// ─────────────────────────────────────────────────────────────
class _ColisLivresTab extends StatelessWidget {
  final List<Map<String, dynamic>> colis;
  const _ColisLivresTab({required this.colis});

  @override
  Widget build(BuildContext context) {
    if (colis.isEmpty) {
      return const Center(
        child: _EmptyMissions(
          icon: Icons.check_circle_outline_rounded,
          message: 'Aucune livraison terminée',
          subtitle: 'Vos livraisons terminées apparaîtront ici',
        ),
      );
    }
    final total = colis.fold<double>(
      0,
      (s, m) => s + ((m['rewardValue'] as num?)?.toDouble() ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'Terminées',
              value: '${colis.length}',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.success,
            ),
            _SummaryItem(
              label: 'Frais livraison',
              value: '${total.round()} F',
              icon: Icons.payments_outlined,
              color: AppTheme.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...colis.map((c) => _ColisCard(colis: c, showDeliverButton: false)),
      ],
    );
  }
}

// Shared Colis Card
class _ColisCard extends StatelessWidget {
  final Map<String, dynamic> colis;
  final bool showDeliverButton;
  final String actionLabel;
  final VoidCallback? onAction;
  const _ColisCard({
    required this.colis,
    required this.showDeliverButton,
    this.actionLabel = 'Livré',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: showDeliverButton
                      ? AppTheme.primaryMuted
                      : AppTheme.successContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  colis['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: showDeliverButton
                        ? AppTheme.primary
                        : AppTheme.success,
                  ),
                ),
              ),
              const Spacer(),
              if (!showDeliverButton && colis.containsKey('reward'))
                Text(
                  colis['reward'],
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                  ),
                ),
              if (showDeliverButton)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warningContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'À livrer',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            colis['description'],
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.store_outlined, size: 13, color: AppTheme.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  colis['seller'],
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: AppTheme.muted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  colis['buyer'],
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 13,
                color: AppTheme.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  colis['address'],
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.scale_rounded, size: 13, color: AppTheme.muted),
              const SizedBox(width: 4),
              Text(
                colis['weight'],
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (showDeliverButton) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/delivery-proof-screen',
                        arguments: {
                          'id': colis['id'],
                          'client': colis['buyer'],
                          'phone': '',
                          'address': colis['address'],
                          'items': colis['description'],
                          'weight': colis['weight'],
                          'amount': '',
                          'qrCode': 'ASK-${colis['id']}-2026',
                        },
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                    label: Text(
                      'Preuve',
                      style: GoogleFonts.outfit(fontSize: 13),
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
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      actionLabel,
                      style: GoogleFonts.outfit(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB 5 — Revenus
// ─────────────────────────────────────────────────────────────
class _RevenusTab extends StatelessWidget {
  const _RevenusTab();

  @override
  Widget build(BuildContext context) {
    // Les chiffres affichés ici étaient inventés (graphique et
    // transactions en dur). Tant que le calcul réel des gains livreur
    // n'existe pas côté backend, on affiche un état honnête.
    return const Center(
      child: _EmptyMissions(
        icon: Icons.bar_chart_rounded,
        message: 'Bientôt disponible',
        subtitle: 'Le suivi de tes gains arrive bientôt.',
      ),
    );
  }
}

class _RetraitTab extends StatefulWidget {
  const _RetraitTab();

  @override
  State<_RetraitTab> createState() => _RetraitTabState();
}

// Le calcul réel des gains livreur existe maintenant côté serveur (voir
// DeliveryService.createDeliveryEarning, déclenché à chaque remise au
// client confirmée) — même principe que _RetraitTab côté vendeur
// (seller_dashboard_screen.dart) : un pourcentage des frais de livraison
// de chaque course, individualisable par livreur (80% par défaut pour lui,
// 20% pour la plateforme, tant que l'admin n'a pas fixé un taux différent
// pour ce livreur précis). Le vrai virement reste manuel pour l'instant —
// pas de bouton de retrait qui déclenche un paiement automatique.
class _RetraitTabState extends State<_RetraitTab> {
  bool _isLoading = true;
  bool _hasError = false;
  num _soldeDisponible = 0;
  num _totalRecu = 0;
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
      final res = await ApiService.instance.client
          .get('/api/v1/delivery-agents/me/earnings');
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
          _totalRecu =
              (double.tryParse(data['totalRecu']?.toString() ?? '') ?? 0);
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
              'Historique des livraisons payées',
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
                  'Aucune livraison réglée pour le moment.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              ..._history.map((h) => _EarningHistoryItem(
                    amount: _formatAmount(
                      (double.tryParse(h['montant']?.toString() ?? '') ?? 0),
                    ),
                    orderNumber: (h['orderNumber'] ?? '—').toString(),
                    date: _formatHistoryDate(h['date']),
                    isPaid: h['statut'] == 'payé',
                  )),
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
            'Montant dû par Asoukaa (en attente de versement)',
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
          Text(
            'Total déjà reçu : ${_formatAmount(_totalRecu)}',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }

  // Pas de bouton de retrait ici : le vrai virement reste, pour l'instant,
  // un processus manuel piloté par l'équipe Asoukaa (même limite que côté
  // vendeur — voir seller_dashboard_screen.dart, _buildWithdrawInfoCard).
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
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Versement manuel pour l\'instant',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'L\'équipe Asoukaa te verse ce montant directement. Un versement automatique arrivera plus tard.',
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

class _EarningHistoryItem extends StatelessWidget {
  final String amount;
  final String orderNumber;
  final String date;
  final bool isPaid;

  const _EarningHistoryItem({
    required this.amount,
    required this.orderNumber,
    required this.date,
    required this.isPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commande #$orderNumber',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isPaid ? 'Reçu' : 'En attente',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPaid ? AppTheme.success : AppTheme.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
class _SummaryRow extends StatelessWidget {
  final List<_SummaryItem> items;
  const _SummaryRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: item == items.last ? 0 : 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, size: 18, color: item.color),
                    const SizedBox(height: 6),
                    Text(
                      item.value,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      item.label,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _RouteRow extends StatelessWidget {
  final String pickup;
  final String delivery;
  final double? latitude;
  final double? longitude;
  const _RouteRow({
    required this.pickup,
    required this.delivery,
    this.latitude,
    this.longitude,
  });

  Future<void> _openMaps(BuildContext context) async {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir Maps'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir Maps'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            Container(width: 1, height: 20, color: AppTheme.outlineVariant),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickup,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Text(
                delivery,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (latitude != null && longitude != null)
          IconButton(
            onPressed: () => _openMaps(context),
            icon: const Icon(Icons.map_rounded, color: AppTheme.primary),
            tooltip: 'Ouvrir dans Maps',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyMissions extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;
  const _EmptyMissions({
    required this.icon,
    required this.message,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: AppTheme.muted),
        const SizedBox(height: 12),
        Text(
          message,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB 5 — Courses Express (Delivery Requests)
// ─────────────────────────────────────────────────────────────
class _CoursesExpressTab extends StatefulWidget {
  const _CoursesExpressTab();

  @override
  State<_CoursesExpressTab> createState() => _CoursesExpressTabState();
}

class _CoursesExpressTabState extends State<_CoursesExpressTab> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _filter = 'pending';

  static const Map<String, Map<String, dynamic>> _urgencyConfig = {
    'normal': {
      'label': 'Normal',
      'color': Color(0xFF16A34A),
      'icon': Icons.schedule_rounded,
    },
    'urgent': {
      'label': 'Urgent',
      'color': Color(0xFFD97706),
      'icon': Icons.bolt_rounded,
    },
    'express': {
      'label': 'Express',
      'color': Color(0xFFDC2626),
      'icon': Icons.rocket_launch_rounded,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final String path;
      final Map<String, dynamic> params;
      // Routes réelles du backend (module delivery, préfixe au singulier) :
      // les courses express = les "livraisons indépendantes".
      if (_filter == 'pending') {
        path = '/api/v1/delivery/independent/available';
        params = {};
      } else {
        path = '/api/v1/delivery/independent/mine';
        params = {};
      }

      final r = await ApiService.instance.client.get(path, queryParameters: params.isNotEmpty ? params : null);
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

  Future<void> _acceptRequest(String requestId) async {
    try {
      await ApiService.instance.client.patch(
        '/api/v1/delivery/independent/$requestId/accept',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Course acceptée ! Contactez le client.',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur: impossible d\'accepter la course.',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _requests.isEmpty
              ? Center(
                  child: _EmptyMissions(
                    icon: Icons.moped_rounded,
                    message: _filter == 'pending'
                        ? 'Aucune course disponible'
                        : 'Aucune course acceptée',
                    subtitle: _filter == 'pending'
                        ? 'Les nouvelles demandes apparaîtront ici'
                        : 'Acceptez une course dans l\'onglet Disponibles',
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _loadRequests,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _DeliveryRequestCard(
                      request: _requests[i],
                      urgencyConfig: _urgencyConfig,
                      showAcceptButton: _filter == 'pending',
                      onAccept: () => _acceptRequest(_requests[i]['id']),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surface,
      child: Row(
        children: [
          _FilterChip(
            label: 'Disponibles',
            isSelected: _filter == 'pending',
            onTap: () {
              setState(() => _filter = 'pending');
              _loadRequests();
            },
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Mes courses',
            isSelected: _filter == 'mine',
            onTap: () {
              setState(() => _filter = 'mine');
              _loadRequests();
            },
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadRequests,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 20,
              color: AppTheme.muted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryMuted : AppTheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? AppTheme.primary : AppTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _DeliveryRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final Map<String, Map<String, dynamic>> urgencyConfig;
  final bool showAcceptButton;
  final VoidCallback onAccept;

  const _DeliveryRequestCard({
    required this.request,
    required this.urgencyConfig,
    required this.showAcceptButton,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = request['urgency'] as String? ?? 'normal';
    final config = urgencyConfig[urgency] ?? urgencyConfig['normal']!;
    final color = config['color'] as Color;
    final price = (request['proposed_price'] as num?)?.toDouble() ?? 0.0;
    final requester = request['requester'] as Map<String, dynamic>?;
    final requesterName = requester?['full_name'] as String? ?? 'Client';
    final status = request['status'] as String? ?? 'pending';

    final statusColors = {
      'pending': AppTheme.warning,
      'accepted': AppTheme.primary,
      'in_progress': AppTheme.warning,
      'completed': AppTheme.success,
      'cancelled': AppTheme.error,
    };
    final statusLabels = {
      'pending': 'En attente',
      'accepted': 'Acceptée',
      'in_progress': 'En cours',
      'completed': 'Terminée',
      'cancelled': 'Annulée',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            config['icon'] as IconData,
                            size: 12,
                            color: color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            config['label'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (statusColors[status] ?? AppTheme.muted)
                            .withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabels[status] ?? status,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColors[status] ?? AppTheme.muted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${price.toStringAsFixed(0)} FCFA',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RouteRow(
                  pickup: request['pickup_address'] as String? ?? '',
                  delivery: request['dropoff_address'] as String? ?? '',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 13,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        request['package_description'] as String? ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 13,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        requesterName,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (request['notes'] != null &&
                    (request['notes'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          request['notes'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (showAcceptButton)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.outlineVariant, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {},
                      child: Text(
                        'Détails',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: AppTheme.outlineVariant,
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: onAccept,
                      child: Text(
                        'Accepter la course',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
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
}
