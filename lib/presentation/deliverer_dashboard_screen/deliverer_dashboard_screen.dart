import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../routes/app_routes.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/connection_error_widget.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';

class DelivererDashboardScreen extends StatefulWidget {
  const DelivererDashboardScreen({super.key});

  @override
  State<DelivererDashboardScreen> createState() =>
      _DelivererDashboardScreenState();
}

class _DelivererDashboardScreenState extends State<DelivererDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentNavIndex = 4;
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  // Real data
  List<Map<String, dynamic>> _availableMissions = [];
  List<Map<String, dynamic>> _myMissions = [];
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

      List<Map<String, dynamic>> available = [];
      List<Map<String, dynamic>> mine = [];
      int pendingCount = 0;

      try {
        final r = await ApiService.instance.client.get('/api/v1/deliveries/available');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        available = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/deliveries/mine');
        final raw = r.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
        mine = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get(
          '/api/v1/delivery-requests',
          queryParameters: {'status': 'pending', 'limit': '1'},
        );
        final raw = r.data;
        pendingCount = raw is List
            ? raw.length
            : (raw is Map ? ((raw['total'] ?? raw['count'] ?? (raw['data'] as List?)?.length) as int? ?? 0) : 0);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _availableMissions = available;
          _myMissions = mine;
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
                    // Already on deliverer dashboard
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
                          'Espace Livreur',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Cotonou & Environs',
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
                            'En ligne',
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
            children: const [
              _MissionsDisponiblesTab(),
              _MissionsEnCoursTab(),
              _ColisRecuperesTab(),
              _ColisLivresTab(),
              _CoursesExpressTab(),
              _RevenusTab(),
              _RetraitTab(),
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

// ─────────────────────────────────────────────────────────────
// TAB 1 — Missions Disponibles
// ─────────────────────────────────────────────────────────────
class _MissionsDisponiblesTab extends StatefulWidget {
  const _MissionsDisponiblesTab();

  @override
  State<_MissionsDisponiblesTab> createState() =>
      _MissionsDisponiblesTabState();
}

class _MissionsDisponiblesTabState extends State<_MissionsDisponiblesTab> {
  final List<Map<String, dynamic>> _availableMissions = [];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'Disponibles',
              value: '${_availableMissions.length}',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.primary,
            ),
            _SummaryItem(
              label: 'Rayon max',
              value: '25 km',
              icon: Icons.location_on_outlined,
              color: AppTheme.warning,
            ),
            _SummaryItem(
              label: 'Moy. gain',
              value: '4 250 F',
              icon: Icons.payments_outlined,
              color: AppTheme.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._availableMissions.map((m) => _MissionCard(mission: m)),
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  const _MissionCard({required this.mission});

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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Mission ${mission['id']} acceptée !',
                            style: GoogleFonts.outfit(),
                          ),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Text(
                      'Accepter',
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
class _MissionsEnCoursTab extends StatefulWidget {
  const _MissionsEnCoursTab();

  @override
  State<_MissionsEnCoursTab> createState() => _MissionsEnCoursTabState();
}

class _MissionsEnCoursTabState extends State<_MissionsEnCoursTab> {
  final List<Map<String, dynamic>> _myMissions = [];

  @override
  Widget build(BuildContext context) {
    if (_myMissions.isEmpty) {
      return const Center(
        child: _EmptyMissions(
          icon: Icons.directions_bike_rounded,
          message: 'Aucune mission en cours',
          subtitle: 'Acceptez une mission dans l\'onglet Disponibles',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'En cours',
              value: '${_myMissions.length}',
              icon: Icons.directions_bike_rounded,
              color: AppTheme.warning,
            ),
            _SummaryItem(
              label: 'À gagner',
              value: '7 900 F',
              icon: Icons.payments_outlined,
              color: AppTheme.success,
            ),
            _SummaryItem(
              label: 'Km restants',
              value: '27.5',
              icon: Icons.route_rounded,
              color: AppTheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._myMissions.map((m) => _EnCoursCard(mission: m)),
      ],
    );
  }
}

class _EnCoursCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  const _EnCoursCard({required this.mission});

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
            _RouteRow(pickup: mission['pickup'], delivery: mission['delivery']),
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
                    onPressed: () {},
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    label: Text('Appeler', style: GoogleFonts.outfit()),
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Statut mis à jour pour ${mission['id']}',
                            style: GoogleFonts.outfit(),
                          ),
                          backgroundColor: AppTheme.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text('Confirmer', style: GoogleFonts.outfit()),
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
  const _ColisRecuperesTab();

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> colis = [
      {
        'id': 'CLR-101',
        'description': 'Tissu Wax 6 yards',
        'seller': 'Boutique Aminata',
        'buyer': 'Rokhaya Sow',
        'address': 'Cadjehoun, Cotonou',
        'retrievedAt': 'Aujourd\'hui 09:15',
        'weight': '2.5 kg',
      },
      {
        'id': 'CLR-102',
        'description': 'Chaussures x2 paires',
        'seller': 'Mode Africaine Shop',
        'buyer': 'Ibrahima Fall',
        'address': 'Akpakpa, Cotonou',
        'retrievedAt': 'Aujourd\'hui 10:40',
        'weight': '1.8 kg',
      },
      {
        'id': 'CLR-103',
        'description': 'Accessoires bijoux',
        'seller': 'Bijoux Cotonou',
        'buyer': 'Aissatou Bah',
        'address': 'Fidjrossè, Cotonou',
        'retrievedAt': 'Aujourd\'hui 11:05',
        'weight': '0.5 kg',
      },
    ];

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
              label: 'Poids total',
              value: '4.8 kg',
              icon: Icons.scale_rounded,
              color: AppTheme.warning,
            ),
            _SummaryItem(
              label: 'À livrer',
              value: '3',
              icon: Icons.pending_actions_rounded,
              color: AppTheme.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...colis.map((c) => _ColisCard(colis: c, showDeliverButton: true)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB 4 — Colis Livrés
// ─────────────────────────────────────────────────────────────
class _ColisLivresTab extends StatelessWidget {
  const _ColisLivresTab();

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> livres = [
      {
        'id': 'CLV-088',
        'description': 'Boubou brodé homme',
        'seller': 'Tailor Cotonou',
        'buyer': 'Cheikh Diop',
        'address': 'Haie Vive, Cotonou',
        'retrievedAt': 'Hier 14:30',
        'weight': '1.2 kg',
        'reward': '2 200 FCFA',
      },
      {
        'id': 'CLV-089',
        'description': 'Sac à main cuir',
        'seller': 'Maroquinerie Bénin',
        'buyer': 'Mariama Camara',
        'address': 'Zogbo, Cotonou',
        'retrievedAt': 'Hier 16:00',
        'weight': '0.8 kg',
        'reward': '1 800 FCFA',
      },
      {
        'id': 'CLV-090',
        'description': 'Épices et condiments',
        'seller': 'Épicerie Dantokpa',
        'buyer': 'Ndèye Mbaye',
        'address': 'Gbèdjromèdé, Cotonou',
        'retrievedAt': 'Avant-hier 11:20',
        'weight': '3.0 kg',
        'reward': '3 500 FCFA',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          items: [
            _SummaryItem(
              label: 'Livrés',
              value: '${livres.length}',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.success,
            ),
            _SummaryItem(
              label: 'Cette semaine',
              value: '12',
              icon: Icons.calendar_today_rounded,
              color: AppTheme.primary,
            ),
            _SummaryItem(
              label: 'Gains',
              value: '7 500 F',
              icon: Icons.payments_outlined,
              color: AppTheme.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...livres.map((c) => _ColisCard(colis: c, showDeliverButton: false)),
      ],
    );
  }
}

// Shared Colis Card
class _ColisCard extends StatelessWidget {
  final Map<String, dynamic> colis;
  final bool showDeliverButton;
  const _ColisCard({required this.colis, required this.showDeliverButton});

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
              Text(
                colis['seller'],
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: AppTheme.muted,
              ),
              const SizedBox(width: 4),
              Text(
                colis['buyer'],
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${colis['id']} marqué comme livré !',
                            style: GoogleFonts.outfit(),
                          ),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      'Livré',
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
    final List<Map<String, dynamic>> transactions = [
      {
        'id': 'TXN-441',
        'description': 'Livraison CLV-090',
        'date': '18 Mar 2026',
        'amount': '3 500 FCFA',
        'type': 'credit',
      },
      {
        'id': 'TXN-440',
        'description': 'Livraison CLV-089',
        'date': '18 Mar 2026',
        'amount': '1 800 FCFA',
        'type': 'credit',
      },
      {
        'id': 'TXN-439',
        'description': 'Livraison CLV-088',
        'date': '17 Mar 2026',
        'amount': '2 200 FCFA',
        'type': 'credit',
      },
      {
        'id': 'TXN-438',
        'description': 'Retrait Orange Money',
        'date': '15 Mar 2026',
        'amount': '-25 000 FCFA',
        'type': 'debit',
      },
      {
        'id': 'TXN-437',
        'description': 'Livraison CLV-085',
        'date': '14 Mar 2026',
        'amount': '4 100 FCFA',
        'type': 'credit',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Balance card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary, AppTheme.primary.withAlpha(191)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Solde disponible',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                '47 350 FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _BalanceStat(
                    label: 'Ce mois',
                    value: '38 200 F',
                    icon: Icons.trending_up_rounded,
                  ),
                  const SizedBox(width: 24),
                  _BalanceStat(
                    label: 'Total livraisons',
                    value: '127',
                    icon: Icons.local_shipping_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Monthly bar chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gains mensuels (FCFA)',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _SimpleBarChart(
                data: const [
                  {'label': 'Oct', 'value': 0.55},
                  {'label': 'Nov', 'value': 0.70},
                  {'label': 'Déc', 'value': 0.90},
                  {'label': 'Jan', 'value': 0.65},
                  {'label': 'Fév', 'value': 0.80},
                  {'label': 'Mar', 'value': 1.0},
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Transactions récentes',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        ...transactions.map((t) => _TransactionRow(tx: t)),
      ],
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _BalanceStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(fontSize: 10, color: Colors.white60),
            ),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SimpleBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _SimpleBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final value = (d['value'] as double);
          final isMax = value == 1.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 60 * value,
                    decoration: BoxDecoration(
                      color: isMax
                          ? AppTheme.primary
                          : AppTheme.primary.withAlpha(89),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d['label'],
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx['type'] == 'credit';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCredit
                  ? AppTheme.successContainer
                  : AppTheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 18,
              color: isCredit ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['description'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  tx['date'],
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            tx['amount'],
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isCredit ? AppTheme.success : AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB 6 — Retrait (Fund Withdrawal)
// ─────────────────────────────────────────────────────────────
class _RetraitTab extends StatefulWidget {
  const _RetraitTab();

  @override
  State<_RetraitTab> createState() => _RetraitTabState();
}

class _RetraitTabState extends State<_RetraitTab> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _selectedMethod = 'MTN Mobile Money';
  bool _isProcessing = false;

  final List<String> _methods = [
    'MTN Mobile Money',
    'Moov Money',
    'Wave',
    'Virement bancaire',
  ];

  final List<Map<String, dynamic>> _withdrawalHistory = [
    {
      'id': 'RTR-001',
      'amount': '15 000 FCFA',
      'method': 'MTN Mobile Money',
      'date': '18 Mar 2026',
      'status': 'Validé',
      'phone': '+229 97 XX XX XX',
    },
    {
      'id': 'RTR-002',
      'amount': '8 500 FCFA',
      'method': 'Wave',
      'date': '12 Mar 2026',
      'status': 'Validé',
      'phone': '+229 97 XX XX XX',
    },
    {
      'id': 'RTR-003',
      'amount': '22 000 FCFA',
      'method': 'Moov Money',
      'date': '5 Mar 2026',
      'status': 'En attente',
      'phone': '+229 96 XX XX XX',
    },
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _requestWithdrawal() async {
    final amount = double.tryParse(_amountController.text.replaceAll(' ', ''));
    if (amount == null || amount < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Montant minimum: 1 000 FCFA'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer votre numéro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _withdrawalHistory.insert(0, {
          'id': 'RTR-${_withdrawalHistory.length + 1}',
          'amount': '${_amountController.text} FCFA',
          'method': _selectedMethod,
          'date': 'Aujourd\'hui',
          'status': 'En attente',
          'phone': _phoneController.text,
        });
        _amountController.clear();
        _phoneController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande de retrait soumise avec succès !'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solde disponible',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '45 700 FCFA',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cotonou, Bénin',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withAlpha(180),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Demander un retrait',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
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
                Text(
                  'Méthode de paiement',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedMethod,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: _methods
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            m,
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedMethod = v!),
                ),
                const SizedBox(height: 12),
                Text(
                  'Numéro de téléphone',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+229 97 XX XX XX',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      color: const Color(0xFF9E9E9E),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    prefixIcon: const Icon(
                      Icons.phone_rounded,
                      size: 18,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Montant (FCFA)',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Ex: 10000',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      color: const Color(0xFF9E9E9E),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    prefixIcon: const Icon(
                      Icons.payments_rounded,
                      size: 18,
                      color: Color(0xFF9E9E9E),
                    ),
                    suffixText: 'FCFA',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _requestWithdrawal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6210),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Demander le retrait',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Historique des retraits',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          ..._withdrawalHistory.map((w) {
            final isValidated = w['status'] == 'Validé';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isValidated
                          ? const Color(0xFF10B981).withAlpha(25)
                          : const Color(0xFFD97706).withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isValidated
                          ? Icons.check_circle_rounded
                          : Icons.pending_rounded,
                      color: isValidated
                          ? const Color(0xFF10B981)
                          : const Color(0xFFD97706),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w['method'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          '${w['phone']} · ${w['date']}',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        w['amount'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFF6210),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isValidated
                              ? const Color(0xFF10B981).withAlpha(25)
                              : const Color(0xFFD97706).withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          w['status'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isValidated
                                ? const Color(0xFF10B981)
                                : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────
// SHARED HELPER WIDGETS
// ─────────────────────────────────────────────────────────────

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
  const _RouteRow({required this.pickup, required this.delivery});

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
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
      if (_filter == 'pending') {
        path = '/api/v1/delivery-requests';
        params = {'status': 'pending'};
      } else {
        path = '/api/v1/delivery-requests/mine';
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
        '/api/v1/delivery-requests/$requestId/accept',
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
                    Text(
                      requesterName,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.muted,
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
