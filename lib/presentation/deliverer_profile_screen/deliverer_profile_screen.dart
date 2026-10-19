import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../routes/app_routes.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/deliverer_availability.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../utils/lecture_json.dart';
import '../../utils/telephone.dart';

class DelivererProfileScreen extends StatefulWidget {
  const DelivererProfileScreen({super.key});

  @override
  State<DelivererProfileScreen> createState() => _DelivererProfileScreenState();
}

class _DelivererProfileScreenState extends State<DelivererProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isLoading = true;

  // Preferences toggles
  bool _notifNewDeliveries = true;
  bool _notifMessages = true;
  bool _notifPayments = true;
  bool _notifPromotions = false;
  // Les 4 interrupteurs de notifications reflètent les valeurs RÉELLES du
  // serveur : _notifLoaded passe à vrai une fois la lecture réussie.
  bool _notifLoading = true;
  bool _notifLoaded = false;
  bool _availableOnline = false;
  final bool _acceptUrgent = true;
  String _selectedLanguage = 'Français';
  String _selectedVehicle = 'Moto';

  final List<String> _vehicleTypes = [
    'Moto',
    'Voiture',
    'Tricycle',
    'Vélo',
  ];

  // Real data (users/me + delivery-agents/me + delivery/me)
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _agentData;
  int _totalDeliveries = 0;
  double _rating = 0;
  double _tauxReussite = 0;
  bool _isUploadingAvatar = false;

  // Gains livreur : GET /api/v1/delivery-agents/me/earnings renvoie
  // { soldeDisponible, enAttente, totalRecu, historique[] }. L'ancien code
  // appelait /api/v1/deliverer-earnings (inexistant) et affichait donc un
  // message « pas encore disponible » alors que l'endpoint existe bel et
  // bien. _earningsError garde la raison d'un echec (403 si le dossier
  // n'est pas encore valide, par exemple) pour l'afficher honnetement.
  Map<String, dynamic>? _earningsData;
  String? _earningsError;
  bool _isRefreshingEarnings = false;

  // Seule la langue reste un reglage purement local (persiste sur l'appareil).
  static const String _prefLanguage = 'app_language';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _loadData();
    _loadNotificationPreferences();
  }

  // Relit le reglage local (langue) persiste par SharedPreferences.
  // (Les notifications viennent du serveur : voir
  // _loadNotificationPreferences.)
  Future<void> _loadLocalPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _selectedLanguage = prefs.getString(_prefLanguage) ?? _selectedLanguage;
      });
    } catch (_) {
      // Stockage local indisponible : on garde les valeurs par defaut.
    }
  }

  Future<void> _savePreference(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    await _loadLocalPreferences();
    final isLoggedIn = await NestAuthService.instance
        .isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      Map<String, dynamic>? profile;
      Map<String, dynamic>? agent;
      int totalDeliveries = 0;

      try {
        final r = await ApiService.instance.client.get('/api/v1/users/me');
        profile = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/delivery-agents/me');
        agent = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      } catch (_) {}

      // ⚠️ Le vrai statut backend est 'livré' (avec accent) — l'ancien
      // code envoyait 'livre' sur un chemin qui n'existe même pas
      // (/deliveries/mine au lieu de /delivery/me), donc ce comptage
      // retombait toujours silencieusement à 0.
      try {
        final r = await ApiService.instance.client.get(
          '/api/v1/delivery/me',
          queryParameters: {'status': 'livré', 'limit': '1'},
        );
        final raw = r.data;
        if (raw is Map && lireIntOuNull(raw['total']) != null) {
          totalDeliveries = lireInt(raw['total']);
        } else if (raw is List) {
          totalDeliveries = raw.length;
        }
      } catch (_) {}

      // Le profil livreur (noteMoyenne/tauxDeReussite/totalLivraisons) est
      // la source la plus fiable pour les stats — on ne s'en remet au
      // comptage ci-dessus que s'il est absent.
      final agentTotal = lireIntOuNull(agent?['totalLivraisons']);

      Map<String, dynamic>? earnings;
      String? earningsError;
      try {
        final r = await ApiService.instance.client.get(
          '/api/v1/delivery-agents/me/earnings',
        );
        earnings = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      } catch (e) {
        earningsError = _describeError(e);
      }

      if (mounted) {
        setState(() {
          _profileData = profile;
          _agentData = agent;
          _earningsData = earnings;
          _earningsError = earningsError;
          _totalDeliveries = agentTotal ?? totalDeliveries;
          // Les décimaux arrivent en texte (« 4.50 ») : lecture tolérante,
          // sinon le chargement s'interrompait ici (interrupteur
          // « disponible » désynchronisé).
          _rating = lireDouble(agent?['noteMoyenne']);
          _tauxReussite = lireDouble(agent?['tauxDeReussite']);
          _selectedVehicle = _vehicleLabelFor(agent?['vehicleType'] as String?) ?? _selectedVehicle;
          _availableOnline = agent?['isAvailableNow'] as bool? ?? _availableOnline;
          _isLoading = false;
        });
        _animController.forward();
        // Garde le badge « En ligne » du tableau de bord à jour.
        final available = agent?['isAvailableNow'];
        if (available is bool) {
          DelivererAvailability.instance.setAvailable(available);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _animController.forward();
      }
    }
  }

  // Lit les vraies preferences de notification (GET
  // /users/me/notification-preferences).
  Future<void> _loadNotificationPreferences() async {
    try {
      final prefs = await NotificationPreferencesService.instance.load();
      if (!mounted) return;
      setState(() {
        _notifNewDeliveries =
            prefs[NotificationPreferencesService.newDeliveries] ??
                _notifNewDeliveries;
        _notifMessages =
            prefs[NotificationPreferencesService.messages] ?? _notifMessages;
        _notifPayments =
            prefs[NotificationPreferencesService.payments] ?? _notifPayments;
        _notifPromotions = prefs[NotificationPreferencesService.promotions] ??
            _notifPromotions;
        _notifLoaded = true;
        _notifLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _notifLoading = false);
    }
  }

  // Numéro de la dernière demande par réglage : une réponse (succès ou échec)
  // d'une demande plus ancienne ne doit pas écraser un basculement plus récent.
  final Map<String, int> _notifSeq = <String, int>{};

  // Change UNE preference cote serveur (PUT avec la seule cle concernee) :
  // mise a jour optimiste, retour en arriere + message en cas d'echec.
  Future<void> _changeNotificationPreference(
    String key,
    bool value,
    void Function(bool) apply,
  ) async {
    if (!_notifLoaded) {
      if (!_notifLoading) {
        setState(() => _notifLoading = true);
        _loadNotificationPreferences();
      }
      AppToast.show(
        context,
        message: 'Chargement de vos réglages en cours…',
        type: ToastType.info,
      );
      return;
    }
    final seq = (_notifSeq[key] ?? 0) + 1;
    _notifSeq[key] = seq;
    setState(() => apply(value));
    try {
      final saved =
          await NotificationPreferencesService.instance.update(key, value);
      if (!mounted || _notifSeq[key] != seq) return;
      final confirmed = saved[key];
      if (confirmed != null && confirmed != value) {
        setState(() => apply(confirmed));
      }
    } catch (_) {
      if (!mounted || _notifSeq[key] != seq) return;
      setState(() => apply(!value));
      AppToast.show(
        context,
        message: 'Impossible de modifier ce réglage. Vérifiez votre connexion.',
        type: ToastType.error,
      );
    }
  }

  // Le backend stocke le type d'engin en majuscules (MOTO/VOITURE/...) —
  // la liste de chips de l'UI utilise des libellés français capitalisés.
  String? _vehicleLabelFor(String? backendType) {
    switch (backendType) {
      case 'MOTO':
        return 'Moto';
      case 'VOITURE':
        return 'Voiture';
      case 'TRICYCLE':
        return 'Tricycle';
      case 'VELO':
        return 'Vélo';
      default:
        return null;
    }
  }

  // Bascule la disponibilite du livreur cote serveur (PATCH
  // /api/v1/delivery-agents/me/availability). Avant ce correctif, le
  // switch "Disponible en ligne" ne faisait que du setState local : le
  // champ isAvailableNow restait donc a sa valeur par defaut (false) en
  // base, et le livreur n'apparaissait jamais dans la liste des livreurs
  // disponibles cote vendeur (GET /delivery-agents/available filtre sur
  // isAvailableNow = true).
  Future<void> _updateAvailability(bool value) async {
    // Seul un livreur APPROUVE peut changer sa disponibilite : le service
    // backend (DeliveryAgentsService.updateAvailability) renvoie sinon un
    // 403. On le dit tout de suite au lieu de faire bouger l'interrupteur
    // pour le voir revenir en arriere avec une erreur serveur.
    if (_agentData?['status'] != 'approuvé') {
      AppToast.show(
        context,
        message: 'Votre dossier doit être validé par un administrateur avant de pouvoir passer en service.',
        type: ToastType.info,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final previous = _availableOnline;
    setState(() => _availableOnline = value);
    try {
      final res = await ApiService.instance.client.patch(
        '/api/v1/delivery-agents/me/availability',
        data: {'isAvailableNow': value},
      );
      if (!mounted) return;
      DelivererAvailability.instance.setAvailable(value);
      String? serverMessage;
      final data = res.data;
      if (data is Map && data['message'] is String) {
        serverMessage = data['message'] as String;
      }
      AppToast.show(
        context,
        message: serverMessage ??
            (value
                ? 'Vous êtes maintenant en service.'
                : 'Vous êtes maintenant hors service.'),
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _availableOnline = previous);
      AppToast.show(
        context,
        message: "Impossible de mettre à jour la disponibilité : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  String _describeError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        final m = data['message'];
        if (m is List) return m.join(', ');
        return m.toString();
      }
      if (e.response?.statusCode != null) {
        return 'Erreur serveur (${e.response?.statusCode})';
      }
      return 'Connexion impossible. Vérifiez votre réseau.';
    }
    return e.toString();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Fév',
        'Mar',
        'Avr',
        'Mai',
        'Jun',
        'Jul',
        'Aoû',
        'Sep',
        'Oct',
        'Nov',
        'Déc',
      ];
      return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const DelivererProfileSkeleton()
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEarningsSummary(),
                          const SizedBox(height: 16),
                          _buildDeliveryStats(),
                          const SizedBox(height: 16),
                          _buildPersonalInfo(),
                          const SizedBox(height: 16),
                          _buildVehicleSection(),
                          const SizedBox(height: 16),
                          _buildContactSection(),
                          const SizedBox(height: 16),
                          _buildBankAccountSection(),
                          const SizedBox(height: 16),
                          _buildEarningsHistory(),
                          const SizedBox(height: 16),
                          _buildPreferences(),
                          const SizedBox(height: 16),
                          _buildLogoutButton(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppTheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
          onPressed: () => _showEditProfileDialog(),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                // ⚠️ Avant : avatar 100% decoratif (aucun onTap) — le tap
                // ouvre maintenant Galerie/Appareil photo, upload vers
                // /api/v1/upload/avatars puis PUT /api/v1/users/me pour
                // enregistrer l'avatarUrl (partage entre tous les roles,
                // il n'y a pas de logo separe pour un livreur).
                GestureDetector(
                  onTap: _isUploadingAvatar ? null : () => _showAvatarSourceDialog(),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _isUploadingAvatar
                            ? const CircleAvatar(
                                backgroundColor: AppTheme.primaryMuted,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              )
                            : ((_profileData?['avatarUrl'] as String?)?.isNotEmpty ?? false)
                                ? CircleAvatar(
                                    backgroundColor: AppTheme.primaryMuted,
                                    backgroundImage: NetworkImage(_profileData!['avatarUrl'] as String),
                                  )
                                : const CircleAvatar(
                                    backgroundColor: AppTheme.primaryMuted,
                                    child: Icon(
                                      Icons.delivery_dining_rounded,
                                      color: AppTheme.primary,
                                      size: 40,
                                    ),
                                  ),
                      ),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _profileData != null
                      ? '${_profileData!['prenom'] ?? ''} ${_profileData!['name'] ?? ''}'.trim()
                      : 'Mon profil',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_rating.toStringAsFixed(1)} · ${_agentData?['status'] == 'approuvé' ? 'Livreur Vérifié' : 'Livreur'}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      title: Text(
        'Mon Profil',
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildEarningsSummary() {
    // Les montants viennent de GET /api/v1/delivery-agents/me/earnings
    // (soldeDisponible / enAttente / totalRecu / historique). L'ancien code
    // affirmait qu'aucun gain n'existait cote backend : c'etait faux, il
    // appelait /api/v1/deliverer-earnings, un chemin qui n'existe pas.
    // Rien n'est invente ici : si l'appel echoue (dossier pas encore
    // valide, reseau), on affiche la raison renvoyee par le serveur.
    final data = _earningsData;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Résumé des Gains',
                ),
              ),
              IconButton(
                icon: _isRefreshingEarnings
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                tooltip: 'Actualiser mes gains',
                onPressed: _isRefreshingEarnings ? null : _refreshEarnings,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warningContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _earningsError ?? 'Vos gains ne sont pas encore disponibles.',
                      style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildEarningTile(
                    label: 'En attente de versement',
                    amount: _formatPrice(_earningAmount(data['enAttente'])),
                    unit: 'FCFA',
                    icon: Icons.schedule_rounded,
                    iconColor: AppTheme.warning,
                    bgColor: AppTheme.warningContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildEarningTile(
                    label: 'Total déjà reçu',
                    amount: _formatPrice(_earningAmount(data['totalRecu'])),
                    unit: 'FCFA',
                    icon: Icons.payments_rounded,
                    iconColor: AppTheme.success,
                    bgColor: AppTheme.successContainer,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  int _earningAmount(Object? raw) => lireDouble(raw).round();

  // Recharge uniquement la carte des gains (bouton « actualiser »), sans
  // relancer tout l'ecran.
  Future<void> _refreshEarnings() async {
    setState(() => _isRefreshingEarnings = true);
    try {
      final r = await ApiService.instance.client.get(
        '/api/v1/delivery-agents/me/earnings',
      );
      if (!mounted) return;
      setState(() {
        _isRefreshingEarnings = false;
        _earningsData =
            r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
        _earningsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshingEarnings = false;
        _earningsError = _describeError(e);
      });
      AppToast.show(
        context,
        message: 'Impossible de charger vos gains : ${_describeError(e)}',
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Widget _buildEarningTile({
    required String label,
    required String amount,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            unit,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStats() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.bar_chart_rounded,
            title: 'Statistiques de Livraison',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  value: '$_totalDeliveries',
                  label: 'Livraisons\ntotales',
                  icon: Icons.local_shipping_rounded,
                  color: AppTheme.primary,
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: '${_tauxReussite.toStringAsFixed(0)}%',
                  label: 'Taux de\nsuccès',
                  icon: Icons.check_circle_rounded,
                  color: AppTheme.success,
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: _rating.toStringAsFixed(1),
                  label: 'Note\nmoyenne',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppTheme.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 60,
      color: AppTheme.outlineVariant,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildPersonalInfo() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.person_rounded,
            title: 'Informations Personnelles',
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: 'Nom complet',
            value: _profileData != null
                ? '${_profileData!['prenom'] ?? ''} ${_profileData!['name'] ?? ''}'.trim()
                : 'Non renseigné',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email de connexion',
            value: _profileData?['email'] as String? ?? 'Non renseigné',
            onTap: _openChangeEmail,
            trailing: const Icon(
              Icons.edit_rounded,
              color: AppTheme.primary,
              size: 16,
            ),
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Zone de livraison',
            value: [_agentData?['ville'], _agentData?['quartier']]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(', ')
                    .isNotEmpty
                ? [_agentData?['ville'], _agentData?['quartier']]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(', ')
                : 'Non renseigné',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.verified_user_rounded,
            label: 'Statut',
            value: _agentStatusLabel,
            valueColor: _agentStatusColor,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _availableOnline ? AppTheme.successContainer : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _availableOnline ? 'En ligne' : 'Hors ligne',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _availableOnline ? AppTheme.success : AppTheme.muted,
                ),
              ),
            ),
          ),
          // Avant : un livreur refusé voyait juste "Refusé" ici, sans le
          // motif ni aucun moyen d'agir depuis l'app — le formulaire de
          // demande ne s'affichait que lors de la toute première
          // inscription. AgentReapplyScreen réutilise le mécanisme de
          // re-soumission déjà géré côté serveur (DeliveryAgentsService.
          // submitProfile → resubmitProfile), avec le dossier pré-rempli.
          if (_agentData?['status'] == 'rejeté') ...[
            const SizedBox(height: 12),
            if ((_agentData?['motifRefus'] as String?)?.isNotEmpty == true) ...[
              Text(
                'Motif : ${_agentData?['motifRefus']}',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.error,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Corriger et renvoyer ma demande'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
                onPressed: () async {
                  final resubmitted = await Navigator.pushNamed(
                    context,
                    AppRoutes.agentReapply,
                  );
                  if (resubmitted == true) _loadData();
                },
              ),
            ),
          ],

          if ((_agentData?['status'] == 'en attente') &&
              (((_agentData?['idDocumentUrl'] as String?)?.isEmpty ?? true) ||
                  ((_agentData?['selfieUrl'] as String?)?.isEmpty ?? true) ||
                  ((_agentData?['vehiclePhotoUrl'] as String?)?.isEmpty ?? true))) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Compléter mon dossier'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
                onPressed: () async {
                  final completed = await Navigator.pushNamed(
                    context,
                    AppRoutes.agentCompleteDocuments,
                  );
                  if (completed == true) _loadData();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _agentStatusLabel {
    switch (_agentData?['status']) {
      case 'approuvé':
        return 'Vérifié';
      case 'en attente':
        return 'En attente de validation';
      case 'rejeté':
        return 'Refusé';
      case 'bloqué':
        return 'Bloqué';
      default:
        return 'Inconnu';
    }
  }

  Color get _agentStatusColor {
    switch (_agentData?['status']) {
      case 'approuvé':
        return AppTheme.success;
      case 'en attente':
        return AppTheme.warning;
      case 'rejeté':
      case 'bloqué':
        return AppTheme.error;
      default:
        return AppTheme.muted;
    }
  }

  Widget _buildVehicleSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.two_wheeler_rounded,
            title: 'Type de Véhicule',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _vehicleTypes.map((v) {
              final isSelected = v == _selectedVehicle;
              return GestureDetector(
                onTap: () => _showVehicleNotEditableMessage(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _vehicleIcon(v),
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        v,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.outlineVariant),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.confirmation_number_rounded,
            label: 'Immatriculation',
            value: _agentData?['licensePlate'] as String? ?? 'Non renseigné',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.card_membership_rounded,
            label: 'Permis de conduire',
            value: 'Non renseigné',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.security_rounded,
            label: 'Assurance',
            value: 'Non renseigné',
          ),
        ],
      ),
    );
  }

  IconData _vehicleIcon(String vehicle) {
    switch (vehicle) {
      case 'Moto':
        return Icons.two_wheeler_rounded;
      case 'Vélo':
        return Icons.pedal_bike_rounded;
      case 'Voiture':
        return Icons.directions_car_rounded;
      case 'Tricycle':
        return Icons.local_shipping_rounded;
      default:
        return Icons.two_wheeler_rounded;
    }
  }

  Widget _buildContactSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.contact_phone_rounded,
            title: 'Contact',
          ),
          const SizedBox(height: 16),
          _buildContactRow(
            icon: Icons.phone_rounded,
            label: 'Téléphone principal',
            value: _profileData?['phone'] as String? ?? 'Non renseigné',
            isVerified: _profileData?['isVerified'] as bool? ?? false,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.emergency_rounded,
            label: 'Contact urgence',
            value: 'Non renseigné',
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isVerified,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppTheme.success,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppTheme.muted,
            ),
            onPressed: () => _showEditProfileDialog(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildBankAccountSection() {
    // ⚠️ Il n'existe aucun champ bancaire/mobile money pour un livreur
    // cote backend (DeliveryAgentProfile n'a pas ces colonnes, contrairement
    // au vendeur qui a un vrai paymentDetails chiffre + un endpoint dedie).
    // On ne fabrique donc plus de fausses cartes bancaires ici.
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.account_balance_rounded,
            title: 'Compte Bancaire & Paiement',
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showUnsupportedFieldMessage(),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warningContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La gestion des moyens de paiement n\'est pas encore disponible pour les livreurs.',
                      style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textPrimary),
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

  // Le type d'engin n'est renseigne que dans le dossier livreur
  // (POST /api/v1/delivery-agents/apply) et le serveur refuse toute
  // re-soumission quand le dossier est deja approuve : aucun endpoint ne
  // permet de le changer depuis cet ecran.
  void _showVehicleNotEditableMessage() {
    AppToast.show(
      context,
      message: "Le type d'engin est figé après validation de votre dossier. Contactez le support pour le modifier.",
      type: ToastType.info,
      duration: const Duration(seconds: 5),
    );
  }

  void _showUnsupportedFieldMessage() {
    AppToast.show(
      context,
      message: "Cette information n'est pas encore modifiable depuis l'application.",
      type: ToastType.info,
    );
  }

  Widget _buildEarningsHistory() {
    // historique[] = les 30 derniers gains du livreur, renvoyes par
    // GET /api/v1/delivery-agents/me/earnings sous la forme
    // { id, orderNumber, montant, statut, date }.
    final raw = _earningsData?['historique'];
    final entries = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.history_rounded,
            title: 'Historique des Versements',
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'Aucun historique de versement pour le moment.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.muted),
            )
          else
            ...entries.map(_buildEarningsRow),
        ],
      ),
    );
  }

  Widget _buildEarningsRow(Map<String, dynamic> entry) {
    final isPaid = entry['statut'] == 'payé';
    final orderNumber = (entry['orderNumber'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commande ${orderNumber.isEmpty ? '—' : orderNumber}',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(entry['date'] as String?),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
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
                '${_formatPrice(_earningAmount(entry['montant']))} FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppTheme.successContainer
                      : AppTheme.warningContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isPaid ? 'Versé' : 'En attente',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isPaid ? AppTheme.success : AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferences() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(icon: Icons.tune_rounded, title: 'Préférences'),
          const SizedBox(height: 16),
          // Language
          _buildDropdownRow(
            icon: Icons.language_rounded,
            label: 'Langue',
            value: _selectedLanguage,
            options: ['Français', 'English', 'Arabic', 'Wolof'],
            onChanged: _onLanguageChanged,
          ),
          _buildDivider(),
          const SizedBox(height: 8),
          Text(
            'Disponibilité',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildToggleRow(
            icon: Icons.wifi_tethering_rounded,
            label: 'Disponible en ligne',
            subtitle: 'Recevoir des nouvelles livraisons',
            value: _availableOnline,
            onChanged: (v) => _updateAvailability(v),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.flash_on_rounded,
            label: 'Accepter livraisons urgentes',
            subtitle: 'Livraisons express avec bonus',
            value: _acceptUrgent,
            onChanged: (_) => _showUrgentDeliveriesMessage(),
          ),
          _buildDivider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Notifications',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (_notifLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildToggleRow(
            icon: Icons.local_shipping_rounded,
            label: 'Nouvelles livraisons',
            subtitle: 'Alertes pour les nouvelles missions',
            value: _notifNewDeliveries,
            onChanged: (v) => _changeNotificationPreference(
              NotificationPreferencesService.newDeliveries,
              v,
              (x) => _notifNewDeliveries = x,
            ),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.chat_bubble_rounded,
            label: 'Messages',
            subtitle: 'Notifications de chat',
            value: _notifMessages,
            onChanged: (v) => _changeNotificationPreference(
              NotificationPreferencesService.messages,
              v,
              (x) => _notifMessages = x,
            ),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Paiements',
            subtitle: 'Confirmations de versement',
            value: _notifPayments,
            onChanged: (v) => _changeNotificationPreference(
              NotificationPreferencesService.payments,
              v,
              (x) => _notifPayments = x,
            ),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.campaign_rounded,
            label: 'Promotions',
            subtitle: 'Offres et bonus spéciaux',
            value: _notifPromotions,
            onChanged: (v) => _changeNotificationPreference(
              NotificationPreferencesService.promotions,
              v,
              (x) => _notifPromotions = x,
            ),
          ),
        ],
      ),
    );
  }

  // L'application n'embarque aucune traduction (ni flutter_localizations,
  // ni fichiers l10n) : seul le francais est reellement applique. On garde
  // le choix persiste pour le francais et on annonce honnetement que les
  // autres langues ne sont pas encore traduites.
  void _onLanguageChanged(String? value) {
    if (value == null || value == _selectedLanguage) return;
    if (value != 'Français') {
      AppToast.show(
        context,
        message: "Bientôt disponible : l'application n'est traduite qu'en français pour le moment.",
        type: ToastType.info,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    setState(() => _selectedLanguage = value);
    _savePreference(_prefLanguage, value);
  }

  // Aucune notion de livraison « urgente » cote backend (ni colonne dans
  // deliveries, ni endpoint, ni filtre) : laisser l'interrupteur bouger
  // ferait croire a un reglage suivi par le serveur.
  void _showUrgentDeliveriesMessage() {
    AppToast.show(
      context,
      message: 'Bientôt disponible : les livraisons urgentes ne sont pas encore gérées par le serveur.',
      type: ToastType.info,
      duration: const Duration(seconds: 5),
    );
  }

  Widget _buildDropdownRow({
    required IconData icon,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.primary,
              size: 18,
            ),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.error),
        label: Text(
          'Se déconnecter',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
      ),
    );
  }

  void _showAvatarSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpdateAvatar(ImageSource.gallery);
              },
            ),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpdateAvatar(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpdateAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: "Impossible d'accéder à la galerie/caméra : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await UploadService.instance.uploadFile(picked, 'avatars');
      final res = await ApiService.instance.client.put(
        '/api/v1/users/me',
        data: {'avatarUrl': url},
      );
      if (!mounted) return;
      setState(() {
        _isUploadingAvatar = false;
        _profileData = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : {...?_profileData, 'avatarUrl': url};
      });
      AppToast.show(
        context,
        message: 'Photo de profil mise à jour.',
        type: ToastType.success,
        actionLabel: 'OK',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      AppToast.show(
        context,
        message: "Échec de l'envoi de la photo : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _showEditProfileDialog() {
    final prenomController = TextEditingController(
      text: _profileData?['prenom'] as String? ?? '',
    );
    final nameController = TextEditingController(
      text: _profileData?['name'] as String? ?? '',
    );
    final phoneController = TextEditingController(
      text: _profileData?['phone'] as String? ?? '',
    );
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Text(
            'Modifier le profil',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: prenomController,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(
                'Annuler',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              ),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final res = await ApiService.instance.client.put(
                          '/api/v1/users/me',
                          data: {
                            'prenom': prenomController.text.trim(),
                            'name': nameController.text.trim(),
                            'phone': normaliserTelephone(phoneController.text),
                          },
                        );
                        if (!mounted) return;
                        setState(() {
                          _profileData = res.data is Map
                              ? Map<String, dynamic>.from(res.data as Map)
                              : _profileData;
                        });
                        Navigator.pop(ctx);
                        AppToast.show(
                          context,
                          message: 'Profil mis à jour avec succès.',
                          type: ToastType.success,
                          actionLabel: 'OK',
                        );
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (!ctx.mounted) return;
                        AppToast.show(
                          ctx,
                          message: 'Échec : ${_describeError(e)}',
                          type: ToastType.error,
                          duration: const Duration(seconds: 6),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Enregistrer',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Se déconnecter ?',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Vous serez déconnecté de votre compte livreur.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Annuler',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await NestAuthService.instance.logout();
              DelivererAvailability.instance.reset();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.signUpLogin,
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Déconnecter',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primaryMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _buildDivider() {
    return const Divider(height: 1, color: AppTheme.outlineVariant);
  }

  // Changement d'e-mail en 3 étapes (code reçu sur la nouvelle adresse).
  Future<void> _openChangeEmail() async {
    final current = (_profileData?['email'] as String?) ?? '';
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.changeEmail,
      arguments: current,
    );
    if (!mounted) return;
    if (result is String && result.isNotEmpty) {
      setState(() {
        _profileData = {...?_profileData, 'email': result};
      });
    }
  }
}
