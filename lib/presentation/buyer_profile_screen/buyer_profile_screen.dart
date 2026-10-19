import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/user_service.dart';
import '../../services/delivery_zone_service.dart';
import '../../services/mode_service.dart';
import '../../services/upload_service.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/payment_prefs_service.dart';
import '../../utils/telephone.dart';

class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  bool _notifOrders = true;
  bool _notifPromos = true;
  bool _notifMessages = false;
  // Les 3 interrupteurs de notifications reflètent les valeurs RÉELLES du
  // serveur : _notifLoaded passe à vrai une fois la lecture réussie.
  bool _notifLoading = true;
  bool _notifLoaded = false;

  // Langue d'affichage choisie par l'utilisateur, persistee dans
  // SharedPreferences sous la cle 'app_language'.
  String _selectedLanguage = 'Français';

  bool _isLoading = true;
  String? _loadError;

  UserProfile? _profile;
  List<UserAddress> _addresses = [];
  // Numéros Mobile Money enregistrés (stockés sur l'appareil, voir PaymentPrefsService).
  List<SavedPaymentMethod> _paymentMethods = [];

  // Demande vendeur/livreur en cours ou refusée pour ce compte.
  //
  // Avant : tant qu'une demande vendeur/livreur n'est pas APPROUVÉE, le
  // rôle du compte reste "client" (voir AuthService.register — CLIENT est
  // attribué à l'inscription, VENDOR/DELIVERY_AGENT seulement à
  // l'approbation admin dans reviewVendor/reviewAgent). AuthGate route donc
  // ces comptes vers l'accueil acheteur normal, PAS vers le tableau de bord
  // vendeur/livreur — qui est le seul endroit d'où VendorReapplyScreen /
  // AgentReapplyScreen étaient accessibles. Un vendeur ou livreur refusé
  // n'avait donc AUCUN moyen d'atteindre la page de correction : elle
  // existait, mais nulle part où un compte "client" pouvait cliquer pour
  // y arriver. Cette section corrige ça en affichant le statut ici, dans
  // le profil que ces comptes voient réellement.
  Map<String, dynamic>? _vendorApplication;
  Map<String, dynamic>? _agentApplication;

  // Vrai seulement quand le serveur a répondu 404 à GET /vendors/me : le
  // compte n'a aucun profil vendeur et peut en demander un. Reste faux en
  // cas d'erreur réseau (on n'affiche pas « Devenir vendeur » à tort).
  bool _canBecomeVendor = false;

  // Le profil chargé indique le rôle 'vendor' : permet d'afficher « Passer en
  // mode vendeur » même si GET /vendors/me a échoué (réseau, 5xx).
  bool _hasVendorRole = false;

  // Photo de profil : envoi en cours + sélecteur d'image.
  bool _isUploadingAvatar = false;
  final ImagePicker _picker = ImagePicker();

  // Raccourcis lisibles
  String get _fullName => _profile?.fullName ?? '';
  String get _email => _profile?.email ?? '';
  String get _phone => _profile?.phone ?? '';

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppToast.show(context, message: 'Impossible d\'ouvrir ce lien', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Impossible d\'ouvrir ce lien', type: ToastType.error);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _loadPreferences();
    _loadNotificationPreferences();
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    final list = await PaymentPrefsService.instance.load();
    if (mounted) setState(() => _paymentMethods = list);
  }

  Future<void> _savePaymentMethods(List<SavedPaymentMethod> list) async {
    setState(() => _paymentMethods = list);
    await PaymentPrefsService.instance.save(list);
    // Relit la liste normalisée (un seul numéro par défaut).
    await _loadPaymentMethods();
  }

  Future<void> _loadPreferences() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final prefs = await SharedPreferences.getInstance();

      debugPrint('[Profile] Chargement du profil...');
      final profileResult = await UserService.instance.getMyProfile();
      debugPrint('[Profile] Résultat profil: success=${profileResult.success} error=${profileResult.error} data=${profileResult.data?.id}');

      final addressResult = await UserService.instance.getAddresses();
      debugPrint('[Profile] Adresses: success=${addressResult.success} count=${addressResult.data?.length}');

      // Silencieux si absent (404) : la grande majorité des acheteurs n'ont
      // jamais soumis de demande vendeur/livreur, ce n'est pas une erreur.
      Map<String, dynamic>? vendorApp;
      bool vendorAbsent = false;
      try {
        final r = await ApiService.instance.client.get('/api/v1/vendors/me');
        if (r.data is Map) vendorApp = Map<String, dynamic>.from(r.data as Map);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) vendorAbsent = true;
      } catch (_) {}
      Map<String, dynamic>? agentApp;
      try {
        final r = await ApiService.instance.client.get('/api/v1/delivery-agents/me');
        if (r.data is Map) agentApp = Map<String, dynamic>.from(r.data as Map);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        if (profileResult.success && profileResult.data != null) {
          _profile = profileResult.data;
          _loadError = null;
        } else {
          _loadError = profileResult.error ?? 'Profil introuvable. Reconnectez-vous.';
        }
        if (addressResult.success) _addresses = addressResult.data ?? [];
        _vendorApplication = vendorApp;
        _agentApplication = agentApp;
        _hasVendorRole = profileResult.data?.roles.contains('vendor') ?? false;
        // Pas de « Devenir vendeur » pour un compte livreur (ou en cours de
        // demande livreur) : devenir vendeur changerait son espace de travail.
        _canBecomeVendor = vendorAbsent &&
            agentApp == null &&
            !(profileResult.data?.roles.contains('delivery_agent') ?? false);
        _selectedLanguage = prefs.getString('app_language') ?? 'Français';
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('[Profile] Exception: $e\n$stack');
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  // Lit les vraies preferences de notification (GET
  // /users/me/notification-preferences).
  Future<void> _loadNotificationPreferences() async {
    try {
      final prefs = await NotificationPreferencesService.instance.load();
      if (!mounted) return;
      setState(() {
        _notifOrders =
            prefs[NotificationPreferencesService.orders] ?? _notifOrders;
        _notifPromos =
            prefs[NotificationPreferencesService.promotions] ?? _notifPromos;
        _notifMessages =
            prefs[NotificationPreferencesService.messages] ?? _notifMessages;
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

  Future<void> _savePreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const BuyerProfileSkeleton()
          : _profile == null
          ? _buildErrorState()
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        _buildAccountSection(),
                        if (_vendorApplication != null &&
                            _vendorApplication!['status'] != 'approuvé') ...[
                          const SizedBox(height: 16),
                          _buildProfessionalApplicationSection(
                            title: 'Ma demande vendeur',
                            application: _vendorApplication!,
                            reapplyRoute: AppRoutes.vendorReapply,
                          ),
                        ],
                        if ((_vendorApplication != null &&
                                _vendorApplication!['status'] == 'approuvé') ||
                            (_vendorApplication == null && _hasVendorRole)) ...[
                          const SizedBox(height: 16),
                          _buildVendorModeCard(),
                        ] else if (_canBecomeVendor) ...[
                          const SizedBox(height: 16),
                          _buildBecomeVendorCard(),
                        ],
                        if (_agentApplication != null &&
                            _agentApplication!['status'] != 'approuvé') ...[
                          const SizedBox(height: 16),
                          _buildProfessionalApplicationSection(
                            title: 'Ma demande livreur',
                            application: _agentApplication!,
                            reapplyRoute: AppRoutes.agentReapply,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildFollowedShopsSection(),
                        const SizedBox(height: 16),
                        _buildAddressSection(),
                        const SizedBox(height: 16),
                        _buildPaymentSection(),
                        const SizedBox(height: 16),
                        _buildPreferencesSection(),
                        const SizedBox(height: 16),
                        _buildSupportSection(),
                        const SizedBox(height: 16),
                        _buildLegalSection(),
                        const SizedBox(height: 16),
                        _buildLogoutButton(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppTheme.muted),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger le profil',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPreferences,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Réessayer', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final initials = _profile?.initials ?? 'U';

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppTheme.surface,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                _buildAvatar(initials),
                const SizedBox(height: 10),
                Text(
                  _fullName,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _email,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      title: Text(
        'Mon Compte',
        style: GoogleFonts.outfit(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Informations personnelles', Icons.person_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.person_outline_rounded,
                label: 'Nom complet',
                value: _fullName,
                onTap: _showEditProfileDialog,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: _email,
                // Changement en 3 étapes (code reçu sur la nouvelle adresse).
                onTap: _openChangeEmail,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: _phone,
                onTap: () => _showEditPhoneDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.lock_outline_rounded,
                label: 'Mot de passe',
                value: '••••••••',
                onTap: _showChangePasswordDialog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Mes adresses', Icons.location_on_rounded),
        _buildCard(
          child: Column(
            children: [
              ..._addresses.asMap().entries.map((entry) {
                final index = entry.key;
                final addr = entry.value;
                final icon = addr.label.toLowerCase().contains('bureau')
                    ? Icons.work_outline_rounded
                    : addr.label.toLowerCase().contains('domicile')
                        ? Icons.home_outlined
                        : Icons.location_on_outlined;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: addr.isDefault
                                  ? AppTheme.primaryMuted
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Icon(
                              icon,
                              color: addr.isDefault
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      addr.label,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    if (addr.isDefault) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryMuted,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Défaut',
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  addr.displayLine,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                            onSelected: (value) async {
                              if (value == 'default') {
                                final result = await UserService.instance.setDefaultAddress(addr.id);
                                if (!mounted) return;
                                if (result.success) {
                                  final r = await UserService.instance.getAddresses();
                                  if (mounted && r.success) {
                                    setState(() => _addresses = r.data ?? []);
                                  }
                                } else {
                                  AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
                                }
                              } else if (value == 'delete') {
                                // Action irreversible : confirmation obligatoire.
                                final confirmed = await _confirmDialog(
                                  title: 'Supprimer cette adresse',
                                  message: "Voulez-vous vraiment supprimer l'adresse « ${addr.label} » ? Cette action est irréversible.",
                                  confirmLabel: 'Supprimer',
                                  danger: true,
                                );
                                if (!confirmed || !mounted) return;
                                final result = await UserService.instance.deleteAddress(addr.id);
                                if (!mounted) return;
                                if (result.success) {
                                  setState(() => _addresses.removeAt(index));
                                } else {
                                  AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'default',
                                child: Text(
                                  'Définir par défaut',
                                  style: GoogleFonts.outfit(fontSize: 13),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Supprimer',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: AppTheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (index < _addresses.length - 1) _buildDivider(),
                  ],
                );
              }),
              _buildDivider(),
              InkWell(
                onTap: _showAddAddressDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ajouter une adresse',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primary,
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

  Widget _buildPaymentSection() {
    Color colorFor(String op) =>
        op == 'MTN' ? const Color(0xFFE0A100) : const Color(0xFF0066CC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Moyens de paiement', Icons.payment_rounded),
        _buildCard(
          child: Column(
            children: [
              ..._paymentMethods.asMap().entries.map((entry) {
                final index = entry.key;
                final method = entry.value;
                final color = colorFor(method.operator);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withAlpha(30),
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Icon(
                              Icons.phone_android_rounded,
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method.operator == 'MTN'
                                      ? 'MTN Mobile Money'
                                      : 'Moov Money',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  method.number,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (method.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryMuted,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Par défaut',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                            onSelected: (value) {
                              if (value == 'default') {
                                _savePaymentMethods([
                                  for (var i = 0; i < _paymentMethods.length; i++)
                                    _paymentMethods[i].copyWith(isDefault: i == index),
                                ]);
                              } else if (value == 'delete') {
                                final next = List<SavedPaymentMethod>.from(_paymentMethods)
                                  ..removeAt(index);
                                _savePaymentMethods(next);
                              }
                            },
                            itemBuilder: (_) => [
                              if (!method.isDefault)
                                PopupMenuItem(
                                  value: 'default',
                                  child: Text(
                                    'Définir par défaut',
                                    style: GoogleFonts.outfit(fontSize: 13),
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Supprimer',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: AppTheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (index < _paymentMethods.length - 1) _buildDivider(),
                  ],
                );
              }),
              if (_paymentMethods.isNotEmpty) _buildDivider(),
              if (_paymentMethods.length < PaymentPrefsService.maxMethods)
                InkWell(
                  onTap: _showAddPaymentDialog,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Ajouter un numéro de paiement',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Le numéro par défaut est proposé automatiquement quand vous payez une commande ; vous pouvez le changer à ce moment-là.',
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Préférences', Icons.tune_rounded),
        _buildCard(
          child: Column(
            children: [
              // Langue : la ligne etait un simple Padding, donc muette
              // au clic. Elle ouvre maintenant un selecteur de langue.
              _buildInfoRow(
                icon: Icons.language_rounded,
                label: 'Langue',
                value: _selectedLanguage,
                onTap: _showLanguagePicker,
              ),
              _buildDivider(),
              // Notifications header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.notifications_rounded,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Notifications',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
                label: 'Commandes & livraisons',
                value: _notifOrders,
                onChanged: (v) => _changeNotificationPreference(
                  NotificationPreferencesService.orders,
                  v,
                  (x) => _notifOrders = x,
                ),
              ),
              _buildNotifToggle(
                label: 'Promotions & offres',
                value: _notifPromos,
                onChanged: (v) => _changeNotificationPreference(
                  NotificationPreferencesService.promotions,
                  v,
                  (x) => _notifPromos = x,
                ),
              ),
              _buildNotifToggle(
                label: 'Messages',
                value: _notifMessages,
                onChanged: (v) => _changeNotificationPreference(
                  NotificationPreferencesService.messages,
                  v,
                  (x) => _notifMessages = x,
                ),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 64,
            right: 16,
            top: 4,
            bottom: 4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
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
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: const Divider(height: 1, color: AppTheme.outlineVariant),
          ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return _buildCard(
      child: InkWell(
        onTap: () => _showLogoutDialog(),
        borderRadius: BorderRadius.circular(16.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.errorContainer,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppTheme.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Se déconnecter',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalApplicationSection({
    required String title,
    required Map<String, dynamic> application,
    required String reapplyRoute,
  }) {
    final status = application['status'] as String?;
    final motif = application['motifRefus'] as String?;

    late final String statusLabel;
    late final Color statusColor;
    late final Color statusBg;
    switch (status) {
      case 'en attente':
        statusLabel = 'En attente de validation';
        statusColor = AppTheme.warning;
        statusBg = AppTheme.warningContainer;
        break;
      case 'rejeté':
        statusLabel = 'Refusée';
        statusColor = AppTheme.error;
        statusBg = AppTheme.errorContainer;
        break;
      case 'bloqué':
        statusLabel = 'Bloquée';
        statusColor = AppTheme.error;
        statusBg = AppTheme.errorContainer;
        break;
      default:
        statusLabel = status ?? 'Inconnu';
        statusColor = AppTheme.muted;
        statusBg = AppTheme.surfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (status == 'rejeté') ...[
            if (motif != null && motif.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Motif : $motif',
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
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
                  final resubmitted = await Navigator.pushNamed(context, reapplyRoute);
                  if (resubmitted == true) _loadPreferences();
                },
              ),
            ),
          ] else if (status == 'en attente') ...[
            const SizedBox(height: 8),
            Text(
              'Votre dossier est en cours d\'examen par notre équipe. '
              'Vous serez notifié par email dès qu\'une décision sera prise.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ] else if (status == 'bloqué') ...[
            const SizedBox(height: 8),
            Text(
              'Votre compte a été bloqué. Contactez le support pour plus d\'informations.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
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
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16.0), child: child),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Color? valueColor,
    Widget? trailing,
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
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(icon, color: AppTheme.textSecondary, size: 18),
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
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            const SizedBox(width: 4),
            if (onTap != null)
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

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppTheme.outlineVariant),
    );
  }

  void _showEditProfileDialog() {
    final prenomCtrl = TextEditingController(text: _profile?.prenom ?? '');
    final nameCtrl = TextEditingController(text: _profile?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Modifier le nom',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prenomCtrl,
              decoration: InputDecoration(
                labelText: 'Prénom',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.outfit(color: AppTheme.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await UserService.instance.updateProfile(
                prenom: prenomCtrl.text.trim(),
                name: nameCtrl.text.trim(),
              );
              if (!mounted) return;
              if (result.success) {
                setState(() => _profile = result.data);
                AppToast.show(context, message: 'Profil mis à jour.', type: ToastType.success, actionLabel: 'OK');
              } else {
                AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Enregistrer', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditPhoneDialog() {
    final ctrl = TextEditingController(text: _phone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Modifier le téléphone',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Numéro de téléphone',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.outfit(color: AppTheme.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await UserService.instance.updateProfile(phone: ctrl.text.trim());
              if (!mounted) return;
              if (result.success) {
                setState(() => _profile = result.data);
                AppToast.show(context, message: 'Téléphone mis à jour.', type: ToastType.success, actionLabel: 'OK');
              } else {
                AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Enregistrer', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Changer le mot de passe',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Mot de passe actuel',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirmer le mot de passe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.outfit(color: AppTheme.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await UserService.instance.changePassword(
                currentPassword: currentCtrl.text,
                newPassword: newCtrl.text,
                confirmPassword: confirmCtrl.text,
              );
              if (!mounted) return;
              if (result.success) {
                AppToast.show(context, message: 'Mot de passe changé avec succès.', type: ToastType.success, actionLabel: 'OK');
              } else {
                AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Changer', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAddressDialog() async {
    final labelCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final quartierCtrl = TextEditingController();
    final villeCtrl = TextEditingController();
    final countryCtrl = TextEditingController(text: 'Bénin');
    // Liste des communes pour l'auto-complétion ; simple champ libre
    // si la récupération échoue (ex: hors-ligne).
    final communes = await DeliveryZoneService.instance.communeNames();
    if (!mounted) return;
    late TextEditingController villeFieldCtrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nouvelle adresse',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Libellé (ex: Domicile)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nomCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nom du destinataire',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Téléphone du destinataire',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quartierCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quartier',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue value) {
                    if (value.text.isEmpty) return communes;
                    final q = value.text.toLowerCase();
                    return communes.where((cm) => cm.toLowerCase().contains(q));
                  },
                  onSelected: (String selection) {
                    villeFieldCtrl.text = selection;
                    villeCtrl.text = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    villeFieldCtrl = controller;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (v) => villeCtrl.text = v,
                      decoration: InputDecoration(
                        labelText: 'Ville / Commune',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countryCtrl,
                  decoration: InputDecoration(
                    labelText: 'Pays',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (labelCtrl.text.trim().isEmpty ||
                          quartierCtrl.text.trim().isEmpty ||
                          villeCtrl.text.trim().isEmpty) {
                        AppToast.show(
                          context,
                          message: 'Veuillez remplir les champs obligatoires.',
                          type: ToastType.error,
                          actionLabel: 'OK',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      final result = await UserService.instance.createAddress(
                        label: labelCtrl.text.trim(),
                        nomDestinataire: nomCtrl.text.trim(),
                        phoneDestinataire: phoneCtrl.text.trim(),
                        quartier: quartierCtrl.text.trim(),
                        ville: villeCtrl.text.trim(),
                        country: countryCtrl.text.trim().isEmpty ? null : countryCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (result.success && result.data != null) {
                        setState(() => _addresses.add(result.data!));
                        AppToast.show(context, message: 'Adresse ajoutée.', type: ToastType.success, actionLabel: 'OK');
                      } else {
                        AppToast.show(context, message: result.error ?? 'Erreur.', type: ToastType.error, actionLabel: 'OK');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                    ),
                    child: Text(
                      'Ajouter',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
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

  void _showAddPaymentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          top: 24,
          left: 20,
          right: 20,
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
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ajouter un numéro de paiement',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choisissez votre opérateur Mobile Money.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            // (libellé, code serveur, disponible ?) — Orange Money et Wave ne sont
            // pas encore pris en charge pour le paiement.
            ...const [
              ('MTN Mobile Money', 'MTN', true),
              ('Moov Money', 'Moov', true),
              ('Orange Money', 'Orange', false),
              ('Wave', 'Wave', false),
            ].map(
              (m) => ListTile(
                enabled: m.$3,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: m.$3 ? AppTheme.textSecondary : AppTheme.muted,
                    size: 20,
                  ),
                ),
                title: Text(
                  m.$1,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: m.$3
                    ? null
                    : Text(
                        'Bientôt disponible',
                        style: GoogleFonts.outfit(fontSize: 11.5),
                      ),
                trailing: m.$3
                    ? const Icon(Icons.chevron_right_rounded, color: AppTheme.muted)
                    : null,
                onTap: m.$3
                    ? () {
                        Navigator.pop(ctx);
                        _askPaymentNumber(m.$2);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Saisie du numéro pour l'opérateur choisi, puis enregistrement.
  void _askPaymentNumber(String operator) {
    final ctrl = TextEditingController();
    String? error;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            operator == 'MTN' ? 'Numéro MTN Mobile Money' : 'Numéro Moov Money',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Ex : 0197000000',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                final number = normaliserTelephone(ctrl.text);
                if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(number)) {
                  setLocal(() => error = 'Numéro invalide (8 à 15 chiffres)');
                  return;
                }
                if (_paymentMethods.any(
                  (m) => m.operator == operator && m.number == number,
                )) {
                  setLocal(() => error = 'Ce numéro est déjà enregistré');
                  return;
                }
                Navigator.pop(ctx);
                _savePaymentMethods([
                  ..._paymentMethods,
                  SavedPaymentMethod(
                    operator: operator,
                    number: number,
                    // Le premier numéro enregistré devient le numéro par défaut.
                    isDefault: _paymentMethods.isEmpty,
                  ),
                ]);
                if (mounted) {
                  AppToast.show(
                    context,
                    message: 'Numéro enregistré',
                    type: ToastType.success,
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  // Boutiques que l'utilisateur suit (abonnements réels, table
  // shop_follows côté serveur — GET /vendors/me/following).
  Widget _buildFollowedShopsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Mes abonnements', Icons.storefront_rounded),
        _buildCard(
          child: Column(
            children: [
              _buildNavRow(
                icon: Icons.favorite_border_rounded,
                label: 'Boutiques suivies',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.followedShops),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.menu_book_rounded,
                label: 'Ma Bibliothèque (livres numériques)',
                onTap: () => Navigator.pushNamed(context, AppRoutes.library),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection() {
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
                icon: Icons.assignment_return_rounded,
                label: 'Demander un remboursement',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.refundRequest),
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

  Widget _buildLegalSection() {
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
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.legalSecurity),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.assignment_return_outlined,
                label: 'Remboursement et Retours',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.legalRefund),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.article_outlined,
                label: 'Conditions Générales d\'Utilisation',
                onTap: () => Navigator.pushNamed(context, AppRoutes.legalTerms),
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
                borderRadius: BorderRadius.circular(10.0),
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

  // Boite de confirmation generique pour les actions irreversibles.
  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Annuler',
              style: GoogleFonts.outfit(
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppTheme.error : AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: Text(
              confirmLabel,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Changement d'e-mail ─────────────────────────────────────────────────────
  Future<void> _openChangeEmail() async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.changeEmail,
      arguments: _email,
    );
    if (!mounted) return;
    if (result is String && result.isNotEmpty) {
      await _loadPreferences();
    }
  }

  // ── Photo de profil ─────────────────────────────────────────────────────────
  Widget _buildAvatar(String initials) {
    final url = _profile?.avatarUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    Widget initialsWidget() => Center(
          child: Text(
            initials,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        );

    return GestureDetector(
      onTap: _isUploadingAvatar ? null : _showAvatarSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: ClipOval(
              child: _isUploadingAvatar
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  : hasPhoto
                      ? Image.network(
                          url!,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => initialsWidget(),
                        )
                      : initialsWidget(),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary, width: 1.5),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 14,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarSheet() {
    final hasPhoto = (_profile?.avatarUrl ?? '').isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.primary),
              title: Text('Prendre une photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary),
              title: Text('Choisir dans la galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                title: Text(
                  'Supprimer la photo',
                  style: GoogleFonts.outfit(color: AppTheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _avatarErrorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'Connexion impossible. Vérifiez votre réseau.';
      }
    }
    return 'Impossible de mettre à jour la photo. Réessayez.';
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible d\'accéder à la photo.',
          type: ToastType.error,
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await UploadService.instance.uploadFile(file, 'avatars');
      final result = await UserService.instance.updateProfile(avatarUrl: url);
      if (!mounted) return;
      if (result.success && result.data != null) {
        setState(() => _profile = result.data);
        AppToast.show(
          context,
          message: 'Photo de profil mise à jour.',
          type: ToastType.success,
        );
      } else {
        AppToast.show(
          context,
          message: result.error ?? 'Impossible de mettre à jour la photo.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: _avatarErrorMessage(e),
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploadingAvatar = true);
    try {
      // UserService.updateProfile n'envoie pas de valeur nulle : on appelle
      // directement l'API avec avatarUrl = null (suppression côté serveur).
      await ApiService.instance.client
          .put('/api/v1/users/me', data: {'avatarUrl': null});
      final refreshed = await UserService.instance.getMyProfile();
      if (!mounted) return;
      if (refreshed.success && refreshed.data != null) {
        setState(() => _profile = refreshed.data);
      }
      AppToast.show(
        context,
        message: 'Photo de profil supprimée.',
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: _avatarErrorMessage(e),
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ── Devenir vendeur / mode vendeur ──────────────────────────────────────────
  Widget _buildBecomeVendorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Travaillez avec Asoukaa',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ouvrez votre boutique ou devenez livreur avec ce même compte. '
            'Votre demande est examinée par notre équipe, puis vous êtes '
            'prévenu par e-mail.',
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withAlpha(235),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _becomeButton(
                  icon: Icons.add_business_rounded,
                  label: 'Devenir vendeur',
                  route: AppRoutes.becomeVendor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _becomeButton(
                  icon: Icons.moped_rounded,
                  label: 'Devenir livreur',
                  route: AppRoutes.becomeAgent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Bouton blanc « Devenir ... » (deux par ligne dans la carte ci-dessus).
  Widget _becomeButton({
    required IconData icon,
    required String label,
    required String route,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () async {
          final sent = await Navigator.pushNamed(context, route);
          if (sent == true && mounted) _loadPreferences();
        },
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendorModeCard() {
    final shopName = (_vendorApplication?['shopName'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shopName.isNotEmpty
                      ? 'Ma boutique : $shopName'
                      : 'Ma boutique',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(
                'Passer en mode vendeur',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _switchToVendorMode,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchToVendorMode() async {
    await ModeService.instance.promoteStoredRoleToVendor();
    await ModeService.instance.setLastMode(ModeService.vendeur);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.sellerDashboard,
      (route) => false,
    );
  }

  // Selecteur de langue. L'application n'embarque encore aucune
  // traduction (pas de flutter_localizations ni de dossier l10n) : les
  // autres langues sont annoncees comme a venir plutot qu'appliquees en
  // silence. Le choix est persiste sous la cle 'app_language'.
  void _showLanguagePicker() {
    const languages = ['Français', 'English', 'Fon', 'Yoruba'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Langue de l'application",
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...languages.map(
              (lang) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  lang,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: lang == 'Français'
                    ? null
                    : Text(
                        'Bientôt disponible',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                trailing: _selectedLanguage == lang
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (lang != 'Français') {
                    AppToast.show(
                      context,
                      message:
                          "L'application n'est pour l'instant disponible qu'en français. La traduction en $lang arrive bientôt.",
                      type: ToastType.info,
                      actionLabel: 'OK',
                    );
                    return;
                  }
                  setState(() => _selectedLanguage = lang);
                  _savePreference('app_language', lang);
                  AppToast.show(
                    context,
                    message: 'Langue : $lang.',
                    type: ToastType.success,
                    actionLabel: 'OK',
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Se déconnecter',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Êtes-vous sûr de vouloir vous déconnecter de votre compte ?',
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
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
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
