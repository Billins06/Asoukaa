import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/auth_service.dart';

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
  bool _shopVisible = true;
  bool _autoAcceptOrders = false;
  bool _vacationMode = false;

  // Preferences toggles
  bool _notifNewOrders = true;
  bool _notifMessages = true;
  bool _notifPayments = true;
  bool _notifPromotions = false;
  String _selectedLanguage = 'Français';
  String _selectedCurrency = 'XOF (FCFA)';

  // Real data from Supabase
  List<Map<String, dynamic>> _paymentHistory = [];
  Map<String, dynamic>? _shopData;
  Map<String, dynamic>? _profileData;

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
  }

  Future<void> _loadData() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Load profile
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // Load shop
      final shop = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('owner_id', user.id)
          .maybeSingle();

      // Load payment history (withdrawals)
      List<Map<String, dynamic>> payments = [];
      try {
        final paymentsResult = await Supabase.instance.client
            .from('withdrawals')
            .select()
            .eq('seller_id', user.id)
            .order('created_at', ascending: false)
            .limit(20);
        payments = List<Map<String, dynamic>>.from(paymentsResult as List);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _profileData = profile;
          _shopData = shop;
          _paymentHistory = payments.map((p) {
            final status = p['status'] as String? ?? 'pending';
            return {
              'id':
                  '#PAY-${(p['id'] as String? ?? '').substring(0, 8).toUpperCase()}',
              'date': _formatDate(p['created_at'] as String?),
              'amount':
                  '${_formatPrice((p['amount'] as num? ?? 0).toInt())} FCFA',
              'status': status == 'completed'
                  ? 'Versé'
                  : status == 'pending'
                  ? 'En attente'
                  : 'Rejeté',
              'statusColor': status == 'completed'
                  ? AppTheme.success
                  : status == 'pending'
                  ? AppTheme.warning
                  : AppTheme.error,
              'statusBg': status == 'completed'
                  ? AppTheme.successContainer
                  : status == 'pending'
                  ? AppTheme.warningContainer
                  : const Color(0xFFFFEDED),
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
      expandedHeight: 210,
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
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 44),
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
                      child: const Icon(
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
                      'Boutique Cotonou Mode',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
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
                ),
                const SizedBox(height: 4),
                Text(
                  'Vendeur · Membre depuis Jan 2023',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatChip(Icons.star_rounded, '4.8', 'Note'),
                    const SizedBox(width: 12),
                    _buildStatChip(Icons.shopping_bag_rounded, '342', 'Ventes'),
                    const SizedBox(width: 12),
                    _buildStatChip(Icons.people_rounded, '128', 'Abonnés'),
                  ],
                ),
              ],
            ),
          ),
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
                value: 'Boutique Cotonou Mode',
                isEditable: true,
                onEdit: () => _showEditShopDialog(),
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.category_rounded,
                label: 'Catégorie principale',
                value: 'Mode & Vêtements',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.location_on_rounded,
                label: 'Localisation',
                value: 'Cotonou, Bénin',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_rounded,
                label: 'Téléphone boutique',
                value: '+221 77 XXX XX XX',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.email_rounded,
                label: 'Email boutique',
                value: 'cotonomode@email.com',
                isEditable: true,
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
                value: '00123456 7A8',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.apartment_rounded,
                label: 'Raison sociale',
                value: 'Cotonou Mode SARL',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.description_rounded,
                label: 'Registre de commerce',
                value: 'SN-DKR-2023-B-12345',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.verified_user_rounded,
                label: 'Statut de vérification',
                value: 'Vérifié ✓',
                valueColor: AppTheme.success,
              ),
              _buildDivider(),
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
                      onPressed: () {},
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
                value: 'Ecobank Sénégal',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.credit_card_rounded,
                label: 'Numéro de compte',
                value: 'SN•• •••• •••• 4521',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.person_rounded,
                label: 'Titulaire du compte',
                value: 'Mamadou Diallo',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.phone_android_rounded,
                label: 'Mobile Money (Orange)',
                value: '+221 77 XXX XX XX',
                isEditable: true,
              ),
              _buildDivider(),
              _buildInfoRow(
                icon: Icons.waves_rounded,
                label: 'Wave',
                value: '+221 78 XXX XX XX',
                isEditable: true,
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
              onPressed: () {},
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
                        '422 500 FCFA',
                        AppTheme.success,
                        AppTheme.successContainer,
                        Icons.trending_up_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildPaymentSummaryTile(
                        'En attente',
                        '45 000 FCFA',
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
              _buildToggleRow(
                icon: Icons.visibility_rounded,
                label: 'Boutique visible',
                subtitle: 'Votre boutique est visible par les acheteurs',
                value: _shopVisible,
                onChanged: (v) => setState(() => _shopVisible = v),
              ),
              _buildDivider(),
              _buildToggleRow(
                icon: Icons.check_circle_rounded,
                label: 'Acceptation automatique',
                subtitle: 'Accepter les commandes automatiquement',
                value: _autoAcceptOrders,
                onChanged: (v) => setState(() => _autoAcceptOrders = v),
              ),
              _buildDivider(),
              _buildToggleRow(
                icon: Icons.beach_access_rounded,
                label: 'Mode vacances',
                subtitle: 'Suspendre temporairement les commandes',
                value: _vacationMode,
                onChanged: (v) => setState(() => _vacationMode = v),
                isDestructive: true,
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.schedule_rounded,
                label: 'Délai de traitement',
                value: '1-2 jours ouvrés',
                onTap: () {},
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.local_shipping_rounded,
                label: 'Zones de livraison',
                value: 'Cotonou + Régions',
                onTap: () {},
              ),
              _buildDivider(),
              _buildActionRow(
                icon: Icons.policy_rounded,
                label: 'Politique de retour',
                value: '7 jours',
                onTap: () {},
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
                  ],
                ),
              ),
              _buildNotifToggle(
                'Nouvelles commandes',
                _notifNewOrders,
                (v) => setState(() => _notifNewOrders = v),
              ),
              _buildNotifToggle(
                'Messages clients',
                _notifMessages,
                (v) => setState(() => _notifMessages = v),
              ),
              _buildNotifToggle(
                'Paiements reçus',
                _notifPayments,
                (v) => setState(() => _notifPayments = v),
              ),
              _buildNotifToggle(
                'Promotions & offres',
                _notifPromotions,
                (v) => setState(() => _notifPromotions = v),
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
  void _showEditShopDialog() {
    final controller = TextEditingController(text: 'Boutique Cotonou Mode');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Modifier la boutique',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nom de la boutique'),
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
              Navigator.pop(ctx);
              AppToast.show(
                context,
                message: 'Informations de la boutique mises à jour.',
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
                onTap: () => _showSellerSupportTicket(),
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

  void _showSellerSupportTicket() {
    final subjectCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ouvrir un ticket',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectCtrl,
                decoration: InputDecoration(
                  labelText: 'Sujet',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final user = AuthService.instance.currentUser;
                      if (user != null) {
                        await Supabase.instance.client
                            .from('support_tickets')
                            .insert({
                              'user_id': user.id,
                              'subject': subjectCtrl.text.trim(),
                              'message': msgCtrl.text.trim(),
                              'status': 'open',
                              'created_at': DateTime.now().toIso8601String(),
                            });
                      }
                    } catch (_) {}
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ticket envoyé ! Réponse sous 24h.'),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Envoyer',
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
