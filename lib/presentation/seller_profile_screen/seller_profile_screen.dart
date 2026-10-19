import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/category_multi_select.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';
import '../../services/mode_service.dart';
import '../../services/notification_preferences_service.dart';
import '../../utils/telephone.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isLoading = true;

  // Shop Settings toggles
  // Reflète GET /vendors/me (shopVisible) ; change via PATCH /vendors/me/settings.
  bool _shopVisible = true;
  bool _shopVisibleBusy = false;

  // Preferences toggles
  bool _notifNewOrders = true;
  bool _notifMessages = true;
  bool _notifPayments = true;
  bool _notifPromotions = false;
  // Les 4 interrupteurs de notifications reflètent les valeurs RÉELLES du
  // serveur : _notifLoaded passe à vrai une fois la lecture réussie.
  bool _notifLoading = true;
  bool _notifLoaded = false;
  String _selectedLanguage = 'Français';
  String _selectedCurrency = 'XOF (FCFA)';

  // Real data from Supabase
  List<Map<String, dynamic>> _paymentHistory = [];
  Map<String, dynamic>? _shopData;
  Map<String, dynamic>? _profileData;
  bool _isUploadingLogo = false;
  // Upload en cours de la bannière (photo de couverture) de la boutique.
  bool _isUploadingBanner = false;
  // Totaux réels issus de GET /vendors/me/earnings (commissions "payé" /
  // "en attente") — remplacent les montants figés 422 500 / 45 000 FCFA.
  double _totalPaidOut = 0;
  double _pendingPayout = 0;

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

  // Ouvre un lien externe (tel:, mailto:...). Meme implementation que
  // l'ecran profil acheteur, pour un comportement identique partout.
  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppToast.show(
          context,
          message: "Impossible d'ouvrir ce lien",
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: "Impossible d'ouvrir ce lien",
          type: ToastType.error,
        );
      }
    }
  }

  // Reglages boutique pas encore pilotables : aucune API ne les expose
  // cote serveur pour l'instant. On le dit honnetement au vendeur plutot
  // que de laisser un bouton qui ne reagit pas.
  void _reglageBientotDisponible(String reglage) {
    AppToast.show(
      context,
      message: "$reglage : ce réglage sera modifiable prochainement.",
      type: ToastType.info,
    );
  }

  // Lit les vraies preferences de notification (GET
  // /users/me/notification-preferences).
  Future<void> _loadNotificationPreferences() async {
    try {
      final prefs = await NotificationPreferencesService.instance.load();
      if (!mounted) return;
      setState(() {
        _notifNewOrders = prefs[NotificationPreferencesService.newOrders] ??
            _notifNewOrders;
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

  // « Boutique visible » : PATCH /vendors/me/settings {shopVisible}.
  // Masquer demande une confirmation ; mise a jour optimiste avec retour en
  // arriere + message en cas d'echec.
  Future<void> _changeShopVisible(bool value) async {
    if (_shopVisibleBusy) return;
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Text(
            'Masquer votre boutique ?',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Votre boutique et vos produits ne seront plus visibles par les '
            'acheteurs. Les commandes déjà passées continuent normalement. '
            'Vous pourrez la réactiver à tout moment.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Annuler',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
              child: Text(
                'Masquer',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _shopVisible = value;
      _shopVisibleBusy = true;
    });
    try {
      final res = await ApiService.instance.client.patch(
        '/api/v1/vendors/me/settings',
        data: {'shopVisible': value},
      );
      if (!mounted) return;
      final data = res.data;
      final saved =
          data is Map && data['shopVisible'] is bool
              ? data['shopVisible'] as bool
              : value;
      setState(() {
        _shopVisible = saved;
        _shopVisibleBusy = false;
      });
      AppToast.show(
        context,
        message: saved
            ? 'Votre boutique est de nouveau visible par les acheteurs.'
            : 'Votre boutique est maintenant masquée aux acheteurs.',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shopVisible = !value;
        _shopVisibleBusy = false;
      });
      AppToast.show(
        context,
        message: 'Impossible de modifier la visibilité : ${_describeError(e)}',
        type: ToastType.error,
      );
    }
  }

  // Le mode vacances n'a pas encore de comportement cote serveur : on
  // l'annonce honnetement plutot que de laisser croire qu'il est actif.
  void _showVacationModeComingSoon() {
    AppToast.show(
      context,
      message: "Bientôt disponible : le mode vacances n'est pas encore actif.",
      type: ToastType.info,
    );
  }

  Future<void> _loadData() async {
    final isLoggedIn = await NestAuthService.instance
        .isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      Map<String, dynamic>? profile;
      Map<String, dynamic>? shop;
      List<Map<String, dynamic>> payments = [];
      double totalPaidOut = 0;
      double pendingPayout = 0;

      try {
        final r = await ApiService.instance.client.get('/api/v1/users/me');
        profile = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      } catch (_) {}

      try {
        final r = await ApiService.instance.client.get('/api/v1/vendors/me');
        shop = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      } catch (_) {}

      // '/api/v1/withdrawals' n'existe pas côté serveur (404 silencieux →
      // historique toujours vide). La vraie source est
      // GET /vendors/me/earnings (VendorsService.getMyEarnings) :
      // { enAttente, totalRetire, historique: [{id, orderNumber, montant,
      // statut, date}] }.
      try {
        final r = await ApiService.instance.client.get('/api/v1/vendors/me/earnings');
        final raw = r.data;
        if (raw is Map) {
          totalPaidOut = double.tryParse(raw['totalRetire']?.toString() ?? '') ?? 0;
          pendingPayout = double.tryParse(raw['enAttente']?.toString() ?? '') ?? 0;
          final list = raw['historique'] is List ? raw['historique'] as List : const [];
          payments = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _profileData = profile;
          _shopData = shop;
          final visible = shop?['shopVisible'];
          if (visible is bool) _shopVisible = visible;
          _totalPaidOut = totalPaidOut;
          _pendingPayout = pendingPayout;
          _paymentHistory = payments.map((p) {
            // CommissionStatus backend : 'payé' (reversé) | 'en attente'.
            final isPaid = p['statut']?.toString() == 'payé';
            final id = (p['id']?.toString() ?? '');
            final orderNumber = p['orderNumber']?.toString() ?? '';
            final amount = double.tryParse(p['montant']?.toString() ?? '') ?? 0;
            return {
              'id': orderNumber.isNotEmpty && orderNumber != '—'
                  ? orderNumber
                  : '#PAY-${id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
              'date': _formatDate(p['date']?.toString()),
              'amount': '${_formatPrice(amount.round())} FCFA',
              'status': isPaid ? 'Versé' : 'En attente',
              'statusColor': isPaid ? AppTheme.success : AppTheme.warning,
              'statusBg': isPaid ? AppTheme.successContainer : AppTheme.warningContainer,
            };
          }).toList();
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _animController.forward();
      }
    }
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

  // Statut reel de la boutique (vendor.status backend), au lieu du
  // "Verifie" fige qui s'affichait meme pour une boutique en attente.
  String get _verificationStatusLabel {
    switch (_shopData?['status'] as String?) {
      case 'approuvé':
        return 'Vérifié ✓';
      case 'en attente':
        return 'En attente de validation';
      case 'rejeté':
        return 'Rejeté';
      case 'bloqué':
        return 'Bloqué';
      default:
        return 'Inconnu';
    }
  }

  Color get _verificationStatusColor {
    switch (_shopData?['status'] as String?) {
      case 'approuvé':
        return AppTheme.success;
      case 'rejeté':
      case 'bloqué':
        return AppTheme.error;
      default:
        return AppTheme.warning;
    }
  }

  // Statistiques réelles renvoyées par GET /vendors/me dans 'stats'
  // (VendorsService.getShopStats) : salesCount (commandes livrées),
  // productsCount (produits publiés), rating/reviewsCount (avis approuvés),
  // followersCount (abonnés réels, table shop_follows).
  // Donnée absente => 0, jamais un chiffre inventé.
  Map<String, dynamic> get _stats {
    final s = _shopData?['stats'];
    return s is Map ? Map<String, dynamic>.from(s) : const <String, dynamic>{};
  }

  int _statInt(String key) => int.tryParse(_stats[key]?.toString() ?? '') ?? 0;

  String get _ratingLabel {
    final r = double.tryParse(_stats['rating']?.toString() ?? '') ?? 0;
    return r > 0 ? r.toStringAsFixed(1) : '0';
  }

  // "Membre depuis" réel (vendor.createdAt) au lieu de "Jan 2023" figé.
  String get _memberSinceLabel {
    final formatted = _formatDate(_shopData?['createdAt']?.toString());
    // _formatDate renvoie "jj Mmm aaaa" : on ne garde que "Mmm aaaa".
    final parts = formatted.split(' ');
    if (parts.length == 3) return 'Vendeur · Membre depuis ${parts[1]} ${parts[2]}';
    return 'Vendeur';
  }

  // Le backend ne renvoie jamais les coordonnees bancaires en clair (voir
  // VendorsService.getMyProfile) — seul ce booleen est expose.
  String get _paymentConfiguredLabel =>
      _shopData?['hasPaymentConfigured'] == true ? 'Configuré' : 'Non configuré';

  Color get _paymentConfiguredColor =>
      _shopData?['hasPaymentConfigured'] == true ? AppTheme.success : AppTheme.muted;

  // Champs sans colonne correspondante en base (NINEA, raison sociale,
  // registre de commerce, telephone/email boutique dedies) : impossible de
  // les rendre editables tant que le backend ne les stocke pas. On le dit
  // clairement au lieu de laisser le bouton "Modifier" ne rien faire.
  void _showUnsupportedFieldMessage() {
    AppToast.show(
      context,
      message: 'Ce champ n\'est pas encore modifiable depuis l\'application. '
          'Contactez le support pour le mettre à jour.',
      type: ToastType.info,
    );
  }

  String _describeError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String? backendMsg;
      if (data is Map) {
        final m = data['message'];
        backendMsg = m is List ? m.join(', ') : m?.toString();
      } else if (data is String && data.isNotEmpty) {
        backendMsg = data;
      }
      if (backendMsg != null && backendMsg.isNotEmpty) return backendMsg;
      if (status != null) return 'HTTP $status';
      return e.message ?? 'erreur réseau';
    }
    return e.toString();
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
          ? const SellerProfileSkeleton()
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          _buildShopInfoSection(),
                          const SizedBox(height: 16),
                          _buildBusinessSection(),
                          const SizedBox(height: 16),
                          _buildBankAccountSection(),
                          const SizedBox(height: 16),
                          _buildPaymentHistorySection(),
                          const SizedBox(height: 16),
                          _buildShopSettingsSection(),
                          const SizedBox(height: 16),
                          _buildPreferencesSection(),
                          const SizedBox(height: 16),
                          _buildSellerSupportSection(),
                          const SizedBox(height: 16),
                          _buildSellerLegalSection(),
                          const SizedBox(height: 16),
                          _buildModeClientButton(),
                          const SizedBox(height: 12),
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
      // 210 ne suffisait pas une fois l'encoche/barre de statut (SafeArea)
      // prise en compte : le contenu (avatar + nom + badge + stats)
      // depassait de quelques pixels (RenderFlex overflow en debug).
      // +44 (232 -> 276) pour laisser la place a la banniere (photo de
      // couverture) affichee derriere la barre d'outils, au-dessus de
      // l'avatar : voir _buildShopBanner().
      expandedHeight: 276,
      pinned: true,
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
          onPressed: () => _showEditShopDialog(),
        ),
        const SizedBox(width: 4),
      ],
      title: Text(
        'Profil Vendeur',
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF3EE), Color(0xFFFFEDE3), Color(0xFFFFF8F5)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Banniere de la boutique (sous le contenu : l'avatar la
              // chevauche comme une photo de couverture).
              _buildShopBanner(),
              SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 44 -> 88 : l'avatar descend sous la zone de la banniere.
                const SizedBox(height: 88),
                // ⚠️ Avant : avatar + nom purement decoratifs, aucun onTap.
                // Le tap sur l'avatar/le nom ouvre desormais le choix
                // Galerie/Appareil photo pour changer le logo de la
                // boutique (PUT me/shop avec le nouveau logoUrl) — PAS le
                // meme formulaire que le crayon en haut a droite, qui reste
                // le seul a ouvrir _showEditShopDialog(). Le nom affiche est
                // aussi desormais le vrai nom de boutique (_shopData), et le
                // badge "Verifie" ne s'affiche plus que si la boutique est
                // reellement approuvee (avant : toujours affiche, meme en
                // attente).
                GestureDetector(
                  onTap: _isUploadingLogo ? null : () => _showLogoSourceDialog(),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppTheme.primary, AppTheme.primaryLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withAlpha(77),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _isUploadingLogo
                                ? const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : ((_shopData?['logoUrl'] as String?)?.isNotEmpty ?? false)
                                    ? ClipOval(
                                        child: Image.network(
                                          _shopData!['logoUrl'] as String,
                                          width: 84,
                                          height: 84,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.storefront_rounded,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.storefront_rounded,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.outline, width: 1),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: AppTheme.primary,
                                size: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _shopData?['shopName'] as String? ?? 'Ma boutique',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (_shopData?['status'] == 'approuvé') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.successContainer,
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: AppTheme.success,
                                    size: 11,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Vérifié',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _memberSinceLabel,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                // 3 chips seulement (Note / Ventes / Abonnés) : un 4e chip
                // "Produits" ne tient pas sur 360dp dans l'en-tête à hauteur
                // fixe. FittedBox(scaleDown) : filet de sécurité anti-overflow
                // si les nombres deviennent longs.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatChip(Icons.star_rounded, _ratingLabel, 'Note'),
                      const SizedBox(width: 12),
                      _buildStatChip(
                        Icons.shopping_bag_rounded,
                        '${_statInt('salesCount')}',
                        'Ventes',
                      ),
                      const SizedBox(width: 12),
                      // Vrai nombre d'abonnés (stats.followersCount, table
                      // shop_follows côté serveur).
                      _buildStatChip(
                        Icons.people_rounded,
                        '${_statInt('followersCount')}',
                        'Abonnés',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // BANNIERE DE LA BOUTIQUE (photo de couverture)
  // ─────────────────────────────────────────────────────
  // Affichee en haut du header (derriere la barre d'outils, jusqu'a mi-
  // hauteur de l'avatar). Hauteur fixe + BoxFit.cover : pas de risque
  // d'overflow quelle que soit l'image. Le tap sur la banniere (ou sur la
  // pastille "Modifier la banniere") ouvre _showBannerSourceDialog ; le
  // tap sur l'avatar reste reserve au logo (_showLogoSourceDialog).
  Widget _buildShopBanner() {
    final double topPad = MediaQuery.of(context).padding.top;
    // barre de statut + 88 (espace avant l'avatar) + 42 (moitie de l'avatar)
    final double bannerHeight = topPad + 130;
    final String bannerUrl = (_shopData?['bannerUrl'] as String?) ?? '';
    final bool hasBanner = bannerUrl.isNotEmpty;

    final Widget placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryLight.withAlpha(110),
            AppTheme.primary.withAlpha(60),
            AppTheme.primaryContainer,
          ],
        ),
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: bannerHeight,
      child: GestureDetector(
        onTap: _isUploadingBanner ? null : () => _showBannerSourceDialog(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasBanner)
              Image.network(
                bannerUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              )
            else
              placeholder,
            // Voile clair en haut pour garder lisibles le titre et les
            // icones (sombres) de la barre d'outils au-dessus de la photo.
            if (hasBanner)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topPad + 64,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withAlpha(180),
                          Colors.white.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_isUploadingBanner)
              Container(
                color: Colors.black.withAlpha(90),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              )
            else
              // Pastille d'edition : juste sous la barre d'outils, a
              // droite, au-dessus de l'avatar (pas de chevauchement).
              Positioned(
                top: topPad + kToolbarHeight + 4,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasBanner
                            ? Icons.camera_alt_rounded
                            : Icons.add_photo_alternate_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasBanner ? 'Modifier la bannière' : 'Ajouter une bannière',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(180),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: AppTheme.outline.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primary, size: 13),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(8.0),
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
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  // Noms des categories choisies (GET /vendors/me -> 'categories').
  List<String> _shopCategoryNames() {
    final raw = _shopData?['categories'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((c) => (c['name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  // Ligne "Catégories" : puces si le vendeur a choisi des categories,
  // sinon l'ancien texte libre (activityType).
  Widget _buildCategoriesRow() {
    final names = _shopCategoryNames();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: const Icon(Icons.category_rounded,
                color: AppTheme.textSecondary, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catégories',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 4),
                if (names.isEmpty)
                  Text(
                    _shopData?['activityType'] as String? ?? 'Non renseigné',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: names
                        .map((n) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEDE3),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                n,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showEditShopDialog(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Icon(Icons.edit_rounded,
                  color: AppTheme.primary, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isEditable = false,
    VoidCallback? onEdit,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(icon, color: AppTheme.textSecondary, size: 17),
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
                    fontWeight: FontWeight.w500,
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
          if (isEditable)
            GestureDetector(
              onTap: onEdit,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: AppTheme.primary,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.outlineVariant,
      indent: 62,
    );
  }

  // ─── SHOP INFO ───────────────────────────────────────────────────────────────
  Widget _buildShopInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Informations Boutique', Icons.storefront_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.store_rounded,
                label: 'Nom de la boutique',
                value: _shopData?['shopName'] as String? ?? 'Non renseigné',
                isEditable: true,
                onEdit: () => _showEditShopDialog(),
              ),
              _buildDivider(),
              _buildCategoriesRow(),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.location_on_rounded,
                label: 'Localisation',
                value: _shopData?['shopAddress'] as String? ?? 'Non renseigné',
                isEditable: true,
                onEdit: () => _showEditShopDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_rounded,
                label: 'Téléphone boutique',
                value: _profileData?['phone'] as String? ?? 'Non renseigné',
                isEditable: true,
                onEdit: () => _showUnsupportedFieldMessage(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.email_rounded,
                label: 'Email de connexion',
                value: _profileData?['email'] as String? ?? 'Non renseigné',
                isEditable: true,
                onEdit: () => _openChangeEmail(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── BUSINESS / SIRET ────────────────────────────────────────────────────────
  Widget _buildBusinessSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Informations Légales',
          Icons.business_center_rounded,
        ),
        _buildCard(
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.badge_rounded,
                label: 'NINEA / SIRET',
                value: 'Non renseigné',
                isEditable: true,
                onEdit: () => _showUnsupportedFieldMessage(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.apartment_rounded,
                label: 'Raison sociale',
                value: 'Non renseigné',
                isEditable: true,
                onEdit: () => _showUnsupportedFieldMessage(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.description_rounded,
                label: 'Registre de commerce',
                value: 'Non renseigné',
                isEditable: true,
                onEdit: () => _showUnsupportedFieldMessage(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.verified_user_rounded,
                label: 'Statut de vérification',
                value: _verificationStatusLabel,
                valueColor: _verificationStatusColor,
              ),
              // Avant : un vendeur refusé voyait juste "Rejeté" ici, sans le
              // motif ni aucun moyen d'agir depuis l'app — le formulaire de
              // demande ne s'affichait que lors de la toute première
              // inscription. VendorReapplyScreen réutilise le mécanisme de
              // re-soumission déjà géré côté serveur (VendorsService.
              // submitProfile → resubmitProfile), avec le dossier
              // pré-rempli.
              if (_shopData?['status'] == 'rejeté') ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((_shopData?['motifRefus'] as String?)?.isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Motif : ${_shopData?['motifRefus']}',
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
                              AppRoutes.vendorReapply,
                            );
                            if (resubmitted == true) _loadData();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _buildDivider(),
              if ((_shopData?['status'] == 'en attente') &&
                  (((_shopData?['idDocumentUrl'] as String?)?.isEmpty ?? true) ||
                      ((_shopData?['selfieUrl'] as String?)?.isEmpty ?? true) ||
                      ((_shopData?['sampleProductUrls'] as List?)?.isEmpty ?? true))) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
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
                          AppRoutes.vendorCompleteDocuments,
                        );
                        if (completed == true) _loadData();
                      },
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: const Icon(
                        Icons.upload_file_rounded,
                        color: AppTheme.textSecondary,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Documents justificatifs',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '3 documents téléversés',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      // Ouvre l'ecran de consultation / completion des
                      // documents (pieces fournies, remplacement possible).
                      onPressed: () async {
                        final maj = await Navigator.pushNamed(
                          context,
                          AppRoutes.vendorCompleteDocuments,
                        );
                        if (maj == true && mounted) _loadData();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: const BorderSide(color: AppTheme.primary),
                        ),
                      ),
                      child: Text(
                        'Voir',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── BANK ACCOUNT ────────────────────────────────────────────────────────────
  Widget _buildBankAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Compte Bancaire', Icons.account_balance_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.account_balance_rounded,
                label: 'Banque',
                value: _paymentConfiguredLabel,
                valueColor: _paymentConfiguredColor,
                isEditable: true,
                onEdit: () => _showEditPaymentSettingsDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.credit_card_rounded,
                label: 'Numéro de compte',
                value: _paymentConfiguredLabel,
                valueColor: _paymentConfiguredColor,
                isEditable: true,
                onEdit: () => _showEditPaymentSettingsDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.person_rounded,
                label: 'Titulaire du compte',
                value: _paymentConfiguredLabel,
                valueColor: _paymentConfiguredColor,
                isEditable: true,
                onEdit: () => _showEditPaymentSettingsDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_android_rounded,
                label: 'Mobile Money (Orange)',
                value: _paymentConfiguredLabel,
                valueColor: _paymentConfiguredColor,
                isEditable: true,
                onEdit: () => _showEditPaymentSettingsDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.waves_rounded,
                label: 'Wave',
                value: _paymentConfiguredLabel,
                valueColor: _paymentConfiguredColor,
                isEditable: true,
                onEdit: () => _showEditPaymentSettingsDialog(),
              ),
              _buildDivider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryMuted,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Les versements sont effectués tous les 15 jours après validation des commandes.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.primary,
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
      ],
    );
  }

  // ─── PAYMENT HISTORY ─────────────────────────────────────────────────────────
  Widget _buildPaymentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSectionHeader(
                'Historique des Paiements',
                Icons.receipt_long_rounded,
              ),
            ),
            TextButton(
              // Historique complet des retraits + solde retirable.
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.vendorWithdrawals),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                'Voir tout',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        _buildCard(
          child: Column(
            children: [
              // Summary row
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPaymentSummaryTile(
                        'Total versé',
                        '${_formatPrice(_totalPaidOut.round())} FCFA',
                        AppTheme.success,
                        AppTheme.successContainer,
                        Icons.trending_up_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildPaymentSummaryTile(
                        'En attente',
                        '${_formatPrice(_pendingPayout.round())} FCFA',
                        AppTheme.warning,
                        AppTheme.warningContainer,
                        Icons.hourglass_empty_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.outlineVariant),
              ...List.generate(_paymentHistory.length, (i) {
                final p = _paymentHistory[i];
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (p['statusBg'] as Color),
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Icon(
                              Icons.payments_rounded,
                              color: p['statusColor'] as Color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['id'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p['date'] as String,
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
                                p['amount'] as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: p['statusBg'] as Color,
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                                child: Text(
                                  p['status'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: p['statusColor'] as Color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (i < _paymentHistory.length - 1)
                      const Divider(
                        height: 1,
                        color: AppTheme.outlineVariant,
                        indent: 66,
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSummaryTile(
    String label,
    String value,
    Color color,
    Color bg,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
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
          ),
        ],
      ),
    );
  }

  // ─── SHOP SETTINGS ───────────────────────────────────────────────────────────
  Widget _buildShopSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Paramètres Boutique', Icons.settings_rounded),
        _buildCard(
          child: Column(
            children: [
              // Codes promo de la boutique : création, liste, désactivation.
              _buildNavRow(
                icon: Icons.local_offer_outlined,
                label: 'Mes coupons (codes promo)',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.sellerCoupons),
              ),
              _buildDivider(),
              _buildToggleRow(
                icon: Icons.visibility_rounded,
                label: 'Boutique visible',
                subtitle: _shopVisible
                    ? 'Votre boutique est visible par les acheteurs'
                    : 'Désactivée : votre boutique et vos produits sont masqués aux acheteurs',
                value: _shopVisible,
                onChanged: _changeShopVisible,
              ),
              _buildDivider(),
              _buildToggleRow(
                icon: Icons.beach_access_rounded,
                label: 'Mode vacances',
                subtitle: 'Suspendre temporairement les commandes',
                value: false,
                onChanged: (_) => _showVacationModeComingSoon(),
                isDestructive: true,
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.schedule_rounded,
                label: 'Délai de traitement',
                value: '1-2 jours ouvrés',
                onTap: () => _reglageBientotDisponible('Délai de traitement'),
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.local_shipping_rounded,
                label: 'Zones de livraison',
                value: 'Cotonou + Régions',
                onTap: () => _reglageBientotDisponible('Zones de livraison'),
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.policy_rounded,
                label: 'Politique de retour',
                value: '7 jours',
                onTap: () => _reglageBientotDisponible('Politique de retour'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDestructive
                  ? AppTheme.errorContainer
                  : AppTheme.background,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(
              icon,
              color: isDestructive ? AppTheme.error : AppTheme.textSecondary,
              size: 17,
            ),
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
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isDestructive ? AppTheme.error : AppTheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Icon(icon, color: AppTheme.textSecondary, size: 17),
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
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ─── PREFERENCES ─────────────────────────────────────────────────────────────
  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Préférences', Icons.tune_rounded),
        _buildCard(
          child: Column(
            children: [
              // Language picker
              InkWell(
                onTap: () => _showLanguagePicker(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: const Icon(
                          Icons.language_rounded,
                          color: AppTheme.textSecondary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Langue',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.muted,
                              ),
                            ),
                            Text(
                              _selectedLanguage,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.muted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              _buildDivider(),
              // Currency picker
              InkWell(
                onTap: () => _showCurrencyPicker(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: const Icon(
                          Icons.currency_exchange_rounded,
                          color: AppTheme.textSecondary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Devise',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.muted,
                              ),
                            ),
                            Text(
                              _selectedCurrency,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.muted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              _buildDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: const Icon(
                        Icons.notifications_rounded,
                        color: AppTheme.textSecondary,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Notifications',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
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
              ),
              _buildNotifToggle(
                'Nouvelles commandes',
                _notifNewOrders,
                (v) => _changeNotificationPreference(
                  NotificationPreferencesService.newOrders,
                  v,
                  (x) => _notifNewOrders = x,
                ),
              ),
              _buildNotifToggle(
                'Messages clients',
                _notifMessages,
                (v) => _changeNotificationPreference(
                  NotificationPreferencesService.messages,
                  v,
                  (x) => _notifMessages = x,
                ),
              ),
              _buildNotifToggle(
                'Paiements reçus',
                _notifPayments,
                (v) => _changeNotificationPreference(
                  NotificationPreferencesService.payments,
                  v,
                  (x) => _notifPayments = x,
                ),
              ),
              _buildNotifToggle(
                'Promotions & offres',
                _notifPromotions,
                (v) => _changeNotificationPreference(
                  NotificationPreferencesService.promotions,
                  v,
                  (x) => _notifPromotions = x,
                ),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifToggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 46),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                  ),
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
        ),
        if (!isLast)
          const Divider(height: 1, color: AppTheme.outlineVariant, indent: 62),
      ],
    );
  }

  // ─── CHANGEMENT D'E-MAIL ─────────────────────────────────────────────────────
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

  // ─── MODE CLIENT ─────────────────────────────────────────────────────────────
  Future<void> _switchToClientMode() async {
    await ModeService.instance.setLastMode(ModeService.client);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.home,
      (route) => false,
    );
  }

  Widget _buildModeClientButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _switchToClientMode,
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        label: Text(
          'Passer en mode client',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
      ),
    );
  }

  // ─── LOGOUT ──────────────────────────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showLogoutDialog(),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(
          'Se déconnecter',
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
      ),
    );
  }

  // ─── DIALOGS ─────────────────────────────────────────────────────────────────
  // ⚠️ Avant : le champ etait pre-rempli avec un nom fictif fige et
  // "Enregistrer" se contentait d'un toast de succes sans jamais appeler le
  // backend (PUT /api/v1/vendors/me/shop). Desormais les 3 champs sont
  // pre-remplis avec les vraies donnees de _shopData et la sauvegarde
  // persiste reellement, avec le vrai message d'erreur en cas d'echec (ex :
  // "Votre boutique doit etre validee avant de pouvoir la modifier" si le
  // vendeur n'est pas encore approuve).
  // Tap sur l'avatar / le nom de la boutique : contrairement au crayon
  // en haut a droite (qui ouvre le formulaire texte _showEditShopDialog),
  // ceci propose de choisir une photo (galerie ou appareil photo) pour
  // mettre a jour le logo de la boutique. Upload via /api/v1/upload/shop
  // puis enregistrement de l'URL via PUT /api/v1/vendors/me/shop.
  void _showLogoSourceDialog() {
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
                _pickAndUpdateShopLogo(ImageSource.gallery);
              },
            ),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpdateShopLogo(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpdateShopLogo(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: "Impossible d'acceder a la galerie/camera : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _isUploadingLogo = true);
    try {
      final url = await UploadService.instance.uploadFile(picked, 'shop');
      final res = await ApiService.instance.client.put(
        '/api/v1/vendors/me/shop',
        data: {'logoUrl': url},
      );
      if (!mounted) return;
      final saved = res.data is Map
          ? (res.data as Map)['logoUrl']?.toString()
          : null;
      setState(() {
        _isUploadingLogo = false;
        // On ne remplace que logoUrl : la réponse de PUT me/shop ne contient
        // pas 'stats' — remplacer tout _shopData remettait les stats à 0 et
        // pouvait faire disparaître le badge "Vérifié" jusqu'au rechargement.
        _shopData = {
          ..._shopData ?? {},
          'logoUrl': (saved != null && saved.isNotEmpty) ? saved : url,
        };
      });
      AppToast.show(
        context,
        message: 'Logo de la boutique mis a jour.',
        type: ToastType.success,
        actionLabel: 'OK',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingLogo = false);
      AppToast.show(
        context,
        message: "Echec de l'envoi du logo : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  // Choix de la source (galerie / appareil photo) pour la banniere de la
  // boutique — meme principe que _showLogoSourceDialog.
  void _showBannerSourceDialog() {
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Bannière de la boutique — privilégiez une image large (paysage).',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpdateShopBanner(ImageSource.gallery);
              },
            ),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpdateShopBanner(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Upload via /api/v1/upload/shop puis PUT /api/v1/vendors/me/shop
  // {'bannerUrl': url}. Le backend refuse (403) tant que la boutique
  // n'est pas approuvee.
  Future<void> _pickAndUpdateShopBanner(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: "Impossible d'acceder a la galerie/camera : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _isUploadingBanner = true);
    try {
      final url = await UploadService.instance.uploadFile(picked, 'shop');
      final res = await ApiService.instance.client.put(
        '/api/v1/vendors/me/shop',
        data: {'bannerUrl': url},
      );
      if (!mounted) return;
      final saved = res.data is Map
          ? (res.data as Map)['bannerUrl']?.toString()
          : null;
      setState(() {
        _isUploadingBanner = false;
        // On ne remplace que bannerUrl : le reste de _shopData (statut
        // "approuvé", stats...) vient de GET me/shop et doit rester intact.
        _shopData = {
          ..._shopData ?? {},
          'bannerUrl': (saved != null && saved.isNotEmpty) ? saved : url,
        };
      });
      AppToast.show(
        context,
        message: 'Bannière mise à jour',
        type: ToastType.success,
        actionLabel: 'OK',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingBanner = false);
      final bool notApproved =
          e is DioException && e.response?.statusCode == 403;
      AppToast.show(
        context,
        message: notApproved
            ? 'Votre boutique doit être validée avant de pouvoir ajouter une bannière.'
            : "Échec de l'envoi de la bannière : ${_describeError(e)}",
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  // Ids des categories choisies : categoryIds, sinon (reponse sans ce champ)
  // les ids des objets de 'categories'.
  List<String> _categoryIdsFrom(Map<String, dynamic>? data) {
    final ids = data?['categoryIds'];
    if (ids is List && ids.isNotEmpty) {
      return ids.map((e) => e.toString()).toList();
    }
    final cats = data?['categories'];
    if (cats is List) {
      return cats
          .whereType<Map>()
          .map((c) => (c['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  void _showEditShopDialog() {
    final nameController = TextEditingController(
      text: _shopData?['shopName'] as String? ?? '',
    );
    // Categories de la plateforme deja choisies (vide pour un ancien
    // vendeur a texte libre : il peut en choisir, sans y etre force).
    List<String> selectedCategoryIds = _categoryIdsFrom(_shopData);
    final addressController = TextEditingController(
      text: _shopData?['shopAddress'] as String? ?? '',
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
            'Modifier la boutique',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom de la boutique'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Catégories (5 maximum)',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CategoryMultiSelect(
                  selectedIds: selectedCategoryIds,
                  maxSelection: 5,
                  onChanged: (ids) =>
                      setDialogState(() => selectedCategoryIds = ids),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Localisation'),
                  maxLines: 2,
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
                          '/api/v1/vendors/me/shop',
                          data: {
                            'shopName': nameController.text.trim(),
                            if (selectedCategoryIds.isNotEmpty)
                              'categoryIds': selectedCategoryIds,
                            'shopAddress': addressController.text.trim(),
                          },
                        );
                        if (!mounted) return;
                        setState(() {
                          // Fusion (et non remplacement) : la réponse de
                          // PUT me/shop ne contient pas 'stats' — on garde
                          // les stats déjà chargées.
                          _shopData = res.data is Map
                              ? {
                                  ..._shopData ?? {},
                                  ...Map<String, dynamic>.from(res.data as Map),
                                }
                              : _shopData;
                        });
                        Navigator.pop(ctx);
                        AppToast.show(
                          context,
                          message: 'Informations de la boutique mises à jour.',
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

  // Les 5 lignes "Banque / Numero de compte / Titulaire / Mobile Money /
  // Wave" representent en realite UN SEUL reglage cote backend
  // (paymentMethod + ses champs, chiffres ensemble dans paymentDetails) —
  // on ne peut pas les modifier independamment, donc les 5 icones
  // "Modifier" ouvrent ce meme formulaire. Le backend ne renvoyant jamais
  // les valeurs en clair, on ne peut pas les pre-remplir : le vendeur
  // ressaisit tout, comme pour un nouveau moyen de paiement.
  void _showEditPaymentSettingsDialog() {
    String method = 'bank';
    final bankNameController = TextEditingController();
    final accountNumberController = TextEditingController();
    final operatorController = TextEditingController(text: 'Orange');
    final mobileNumberController = TextEditingController();
    final holderNameController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paramètres de paiement',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ces informations remplacent celles déjà enregistrées.',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Compte bancaire'),
                        selected: method == 'bank',
                        onSelected: (_) => setSheetState(() => method = 'bank'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Mobile Money'),
                        selected: method == 'mobile_money',
                        onSelected: (_) => setSheetState(() => method = 'mobile_money'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (method == 'bank') ...[
                  TextField(
                    controller: bankNameController,
                    decoration: const InputDecoration(labelText: 'Banque'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accountNumberController,
                    decoration: const InputDecoration(labelText: 'Numéro de compte'),
                  ),
                ] else ...[
                  TextField(
                    controller: operatorController,
                    decoration: const InputDecoration(
                      labelText: 'Opérateur (Orange, MTN, Wave, Moov...)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mobileNumberController,
                    decoration: const InputDecoration(labelText: 'Numéro Mobile Money'),
                    keyboardType: TextInputType.phone,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: holderNameController,
                  decoration: const InputDecoration(labelText: 'Nom du titulaire'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setSheetState(() => isSaving = true);
                            try {
                              await ApiService.instance.client.patch(
                                '/api/v1/vendors/me/payment-settings',
                                data: {
                                  'paymentMethod': method,
                                  if (method == 'bank') ...{
                                    'bankName': bankNameController.text.trim(),
                                    'accountNumber': accountNumberController.text.trim(),
                                  } else ...{
                                    'operator': operatorController.text.trim(),
                                    'mobileNumber': normaliserTelephone(mobileNumberController.text),
                                  },
                                  'holderName': holderNameController.text.trim(),
                                },
                              );
                              if (!mounted) return;
                              setState(() {
                                _shopData = {
                                  ...?_shopData,
                                  'hasPaymentConfigured': true,
                                };
                              });
                              Navigator.pop(ctx);
                              AppToast.show(
                                context,
                                message: 'Paramètres de paiement enregistrés.',
                                type: ToastType.success,
                                actionLabel: 'OK',
                              );
                            } catch (e) {
                              setSheetState(() => isSaving = false);
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final languages = ['Français', 'English', 'العربية'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choisir la langue',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...languages.map(
              (lang) => ListTile(
                title: Text(lang, style: GoogleFonts.outfit(fontSize: 14)),
                trailing: _selectedLanguage == lang
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedLanguage = lang);
                  Navigator.pop(ctx);
                },
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCurrencyPicker() {
    final currencies = ['XOF (FCFA)', 'EUR (€)', 'USD (\$)', 'GBP (£)'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choisir la devise',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...currencies.map(
              (cur) => ListTile(
                title: Text(cur, style: GoogleFonts.outfit(fontSize: 14)),
                trailing: _selectedCurrency == cur
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedCurrency = cur);
                  Navigator.pop(ctx);
                },
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerSupportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Support et Aide', Icons.support_agent_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildNavRow(
                icon: Icons.confirmation_number_outlined,
                label: 'Ouvrir un ticket',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.supportHelp),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.phone_outlined,
                label: '+229 0164693637',
                onTap: () => _launchExternalUrl('tel:+2290164693637'),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.email_outlined,
                label: 'contact@asoukaa.com',
                onTap: () => _launchExternalUrl('mailto:contact@asoukaa.com'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSellerLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Informations légales', Icons.gavel_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildNavRow(
                icon: Icons.security_rounded,
                label: 'Sécurité et Confidentialité',
                onTap: () => _showLegalPage(
                  'Sécurité et Confidentialité',
                  _securityContent,
                ),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.assignment_return_outlined,
                label: 'Remboursement et Retours',
                onTap: () =>
                    _showLegalPage('Remboursement et Retours', _refundContent),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.article_outlined,
                label: 'Conditions Générales d\'Utilisation',
                onTap: () => _showLegalPage(
                  'Conditions Générales d\'Utilisation',
                  _termsContent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.textSecondary, size: 18),
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
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  void _showLegalPage(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppTheme.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              content,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.7,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const String _securityContent =
      'POLITIQUE DE SÉCURITÉ ET CONFIDENTIALITÉ\nAsoukaa — Bénin Facile\n\nAsoukaa collecte uniquement les données nécessaires au fonctionnement de la plateforme. Toutes les données sont sécurisées via des serveurs chiffrés SSL/TLS. Nous ne vendons ni ne partageons vos données personnelles.\n\nContact : contact@asoukaa.com | +229 0164693637\nSiège : Cotonou, Akpakpa Segbeya Nord, Immeuble Avé Maria';
  static const String _refundContent =
      'POLITIQUE DE REMBOURSEMENT ET RETOURS\nAsoukaa — Bénin Facile\n\nRetours acceptés dans les 7 jours suivant la réception pour articles défectueux ou non conformes. Remboursement via Mobile Money sous 24-72h.\n\nContact : contact@asoukaa.com | +229 0164693637';
  static const String _termsContent =
      'CONDITIONS GÉNÉRALES D\'UTILISATION\nAsoukaa — Bénin Facile\nSiège : Cotonou, Akpakpa Segbeya Nord, Immeuble Avé Maria\n\nEn utilisant Asoukaa, vous acceptez les présentes conditions. Les vendeurs doivent fournir des informations exactes. Les produits illicites sont interdits. Asoukaa se réserve le droit de suspendre tout compte frauduleux.\n\nContact : contact@asoukaa.com | +229 0164693637';

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Se déconnecter ?',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Vous serez redirigé vers l\'écran de connexion.',
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
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: Text(
              'Déconnecter',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
