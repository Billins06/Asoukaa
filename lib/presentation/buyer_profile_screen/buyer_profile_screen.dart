import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/nest_auth_service.dart';
import '../../services/user_service.dart';

class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  bool _notifOrders = true;
  bool _notifPromos = true;
  bool _notifMessages = false;

  bool _isLoading = true;
  String? _loadError;

  UserProfile? _profile;
  List<UserAddress> _addresses = [];
  final List<Map<String, dynamic>> _paymentMethods = [];

  // Raccourcis lisibles
  String get _fullName => _profile?.fullName ?? '';
  String get _email => _profile?.email ?? '';
  String get _phone => _profile?.phone ?? '';

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

      if (!mounted) return;
      setState(() {
        if (profileResult.success && profileResult.data != null) {
          _profile = profileResult.data;
          _loadError = null;
        } else {
          _loadError = profileResult.error ?? 'Profil introuvable. Reconnectez-vous.';
        }
        if (addressResult.success) _addresses = addressResult.data ?? [];
        _notifOrders = prefs.getBool('notif_orders') ?? true;
        _notifPromos = prefs.getBool('notif_promos') ?? true;
        _notifMessages = prefs.getBool('notif_messages') ?? false;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('[Profile] Exception: $e\n$stack');
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
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
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
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
                onTap: null, // L'email n'est pas modifiable
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
                              color: (method['color'] as Color).withAlpha(30),
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Icon(
                              method['icon'] as IconData,
                              color: method['color'] as Color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method['type'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  method['number'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (method['isDefault'] as bool)
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
                                'Défaut',
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
                                setState(() {
                                  for (var m in _paymentMethods) {
                                    m['isDefault'] = false;
                                  }
                                  _paymentMethods[index]['isDefault'] = true;
                                });
                              } else if (value == 'delete') {
                                setState(() => _paymentMethods.removeAt(index));
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
                    if (index < _paymentMethods.length - 1) _buildDivider(),
                  ],
                );
              }),
              _buildDivider(),
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
                        'Ajouter un moyen de paiement',
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

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Préférences', Icons.tune_rounded),
        _buildCard(
          child: Column(
            children: [
              // Language
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
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.language_rounded,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Langue',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
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
                  ],
                ),
              ),
              _buildNotifToggle(
                label: 'Commandes & livraisons',
                value: _notifOrders,
                onChanged: (v) {
                  setState(() => _notifOrders = v);
                  _savePreference('notif_orders', v);
                },
              ),
              _buildNotifToggle(
                label: 'Promotions & offres',
                value: _notifPromos,
                onChanged: (v) {
                  setState(() => _notifPromos = v);
                  _savePreference('notif_promos', v);
                },
              ),
              _buildNotifToggle(
                label: 'Messages',
                value: _notifMessages,
                onChanged: (v) {
                  setState(() => _notifMessages = v);
                  _savePreference('notif_messages', v);
                },
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

  void _showAddAddressDialog() {
    final labelCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final quartierCtrl = TextEditingController();
    final villeCtrl = TextEditingController();
    final countryCtrl = TextEditingController(text: 'Bénin');

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
                TextField(
                  controller: villeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Ville',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
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
              'Ajouter un moyen de paiement',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...['Orange Money', 'Wave', 'Moov Money', 'MTN Mobile Money'].map(
              (method) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
                title: Text(
                  method,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.muted,
                ),
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
                icon: Icons.chat_outlined,
                label: 'Chat avec le support',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.supportHelp),
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.phone_outlined,
                label: '+229 0164693637',
                onTap: () {},
              ),
              _buildDivider(),
              _buildNavRow(
                icon: Icons.email_outlined,
                label: 'contact@asoukaa.com',
                onTap: () {},
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
