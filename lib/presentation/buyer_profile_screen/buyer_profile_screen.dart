import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/auth_service.dart';

class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  bool _notifOrders = true;
  bool _notifPromos = true;
  bool _notifMessages = false;
  String _selectedLanguage = 'Français';
  bool _isLoading = true;

  // Profile data state - mutable so edits are reflected
  String _fullName = '';
  String _email = '';
  String _birthDate = '';
  String _phone = '';
  String _address = '';
  String _city = '';
  String? _avatarUrl;

  final List<Map<String, dynamic>> _addresses = [];
  final List<Map<String, dynamic>> _paymentMethods = [];

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
    try {
      final prefs = await SharedPreferences.getInstance();
      // Load real user profile from Supabase
      final user = AuthService.instance.currentUser;
      if (user != null) {
        try {
          final profile = await Supabase.instance.client
              .from('user_profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();
          if (profile != null && mounted) {
            setState(() {
              _fullName = profile['full_name'] as String? ?? '';
              _email = user.email ?? '';
              _phone = profile['phone'] as String? ?? '';
              _birthDate = profile['birth_date'] as String? ?? '';
              _address = profile['address'] as String? ?? '';
              _city = profile['city'] as String? ?? '';
              _avatarUrl = profile['avatar_url'] as String?;
            });
          } else if (mounted) {
            setState(() {
              _email = user.email ?? '';
              _fullName = user.userMetadata?['full_name'] as String? ?? '';
              _phone = user.userMetadata?['phone'] as String? ?? '';
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _email = user.email ?? '';
              _fullName = user.userMetadata?['full_name'] as String? ?? '';
            });
          }
        }
      }
      setState(() {
        _selectedLanguage = prefs.getString('selected_language') ?? 'Français';
        _notifOrders = prefs.getBool('notif_orders') ?? true;
        _notifPromos = prefs.getBool('notif_promos') ?? true;
        _notifMessages = prefs.getBool('notif_messages') ?? false;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
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

  Widget _buildSliverAppBar() {
    final user = AuthService.instance.currentUser;
    final initials = _fullName.isNotEmpty
        ? _fullName
              .trim()
              .split(' ')
              .map((e) => e.isNotEmpty ? e[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : 'U';

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
                  user?.email ?? _email,
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
                onTap: () => _showEditDialog(
                  'Nom complet',
                  _fullName,
                  onSave: (v) => _fullName = v,
                ),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: _email,
                onTap: () =>
                    _showEditDialog('Email', _email, onSave: (v) => _email = v),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: _phone,
                onTap: () => _showEditDialog(
                  'Téléphone',
                  _phone,
                  onSave: (v) => _phone = v,
                ),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.cake_outlined,
                label: 'Date de naissance',
                value: _birthDate,
                onTap: () => _showEditDialog(
                  'Date de naissance',
                  _birthDate,
                  onSave: (v) => _birthDate = v,
                ),
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
                              color: addr['isDefault'] as bool
                                  ? AppTheme.primaryMuted
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Icon(
                              addr['icon'] as IconData,
                              color: addr['isDefault'] as bool
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
                                      addr['label'] as String,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    if (addr['isDefault'] as bool) ...[
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
                                  '${addr['address']}, ${addr['city']}',
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
                            onSelected: (value) {
                              if (value == 'default') {
                                setState(() {
                                  for (var a in _addresses) {
                                    a['isDefault'] = false;
                                  }
                                  _addresses[index]['isDefault'] = true;
                                });
                              } else if (value == 'delete') {
                                setState(() => _addresses.removeAt(index));
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
    required VoidCallback onTap,
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

  void _showEditDialog(
    String field,
    String currentValue, {
    Function(String)? onSave,
  }) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Modifier $field',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Annuler',
              style: GoogleFonts.outfit(color: AppTheme.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final newValue = controller.text.trim();
              Navigator.pop(ctx);
              if (onSave != null) setState(() => onSave(newValue));
              AppToast.show(
                context,
                message: '$field mis à jour avec succès.',
                type: ToastType.success,
                actionLabel: 'OK',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: Text(
              'Enregistrer',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    _showEditDialog('Nom complet', _fullName, onSave: (v) => _fullName = v);
  }

  void _showAddAddressDialog() {
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
              'Nouvelle adresse',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Libellé (ex: Domicile)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: 'Adresse complète',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: 'Ville / Pays',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _addresses.add({
                      'label': 'Nouvelle adresse',
                      'address': 'Adresse saisie',
                      'city': 'Ville, Pays',
                      'isDefault': false,
                      'icon': Icons.location_on_rounded,
                    });
                  });
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: Text(
                  'Ajouter',
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

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Choisir la langue',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Français', 'English', 'العربية'].map((lang) {
            return RadioListTile<String>(
              title: Text(lang, style: GoogleFonts.outfit(fontSize: 14)),
              value: lang,
              groupValue: _selectedLanguage,
              activeColor: AppTheme.primary,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) async {
                setState(() => _selectedLanguage = v!);
                await _savePreference('selected_language', v!);
                Navigator.pop(ctx);
                AppToast.show(
                  context,
                  message: 'Langue changée : $v',
                  type: ToastType.success,
                  actionLabel: 'OK',
                );
              },
            );
          }).toList(),
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
              await AuthService.instance.signOut();
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
