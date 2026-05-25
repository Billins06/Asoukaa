import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loading_skeleton_widget.dart';

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
  bool _availableOnline = true;
  bool _acceptUrgent = true;
  String _selectedLanguage = 'Français';
  String _selectedVehicle = 'Moto';

  final List<String> _vehicleTypes = [
    'Moto',
    'Vélo',
    'Voiture',
    'Camionnette',
    'À pied',
  ];

  // Real data from Supabase
  List<Map<String, dynamic>> _earningsHistory = [];
  Map<String, dynamic>? _profileData;
  double _totalEarnings = 0;
  int _totalDeliveries = 0;
  double _rating = 0;

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

      // Load missions for earnings history
      List<Map<String, dynamic>> missions = [];
      try {
        final missionsResult = await Supabase.instance.client
            .from('deliverer_missions')
            .select('*, orders(order_number, total)')
            .eq('deliverer_id', user.id)
            .eq('status', 'livre')
            .order('delivered_at', ascending: false)
            .limit(20);
        missions = List<Map<String, dynamic>>.from(missionsResult as List);
      } catch (_) {}

      // Calculate stats
      double totalEarnings = 0;
      for (final m in missions) {
        final fee = (m['delivery_fee'] as num? ?? 0).toDouble();
        totalEarnings += fee;
      }

      // Load earnings history (weekly grouping)
      List<Map<String, dynamic>> earningsHistory = [];
      try {
        final withdrawalsResult = await Supabase.instance.client
            .from('deliverer_earnings')
            .select()
            .eq('deliverer_id', user.id)
            .order('created_at', ascending: false)
            .limit(10);
        final withdrawals = List<Map<String, dynamic>>.from(
          withdrawalsResult as List,
        );
        earningsHistory = withdrawals.map((w) {
          final status = w['status'] as String? ?? 'pending';
          return {
            'id':
                '#LIV-${(w['id'] as String? ?? '').substring(0, 8).toUpperCase()}',
            'date': _formatDate(w['created_at'] as String?),
            'amount':
                '${_formatPrice((w['amount'] as num? ?? 0).toInt())} FCFA',
            'deliveries': '${w['delivery_count'] ?? 0} livraisons',
            'status': status == 'paid' ? 'Versé' : 'En attente',
            'statusColor': status == 'paid'
                ? AppTheme.success
                : AppTheme.warning,
            'statusBg': status == 'paid'
                ? AppTheme.successContainer
                : AppTheme.warningContainer,
          };
        }).toList();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _profileData = profile;
          _earningsHistory = earningsHistory;
          _totalEarnings = totalEarnings;
          _totalDeliveries = missions.length;
          _rating = (profile?['rating'] as num? ?? 0).toDouble();
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
                Stack(
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
                      child: const CircleAvatar(
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
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Moussa Diallo',
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
                            '4.8 · Livreur Vérifié',
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
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Résumé des Gains',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildEarningTile(
                  label: 'Ce mois',
                  amount: '36 500',
                  unit: 'FCFA',
                  icon: Icons.trending_up_rounded,
                  iconColor: AppTheme.success,
                  bgColor: AppTheme.successContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEarningTile(
                  label: 'En attente',
                  amount: '9 800',
                  unit: 'FCFA',
                  icon: Icons.schedule_rounded,
                  iconColor: AppTheme.warning,
                  bgColor: AppTheme.warningContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildEarningTile(
                  label: 'Total versé',
                  amount: '214 200',
                  unit: 'FCFA',
                  icon: Icons.payments_rounded,
                  iconColor: AppTheme.primary,
                  bgColor: AppTheme.primaryMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEarningTile(
                  label: 'Bonus',
                  amount: '12 000',
                  unit: 'FCFA',
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  bgColor: const Color(0xFFEDE9FE),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                  value: '342',
                  label: 'Livraisons\ntotales',
                  icon: Icons.local_shipping_rounded,
                  color: AppTheme.primary,
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: '98%',
                  label: 'Taux de\nsuccès',
                  icon: Icons.check_circle_rounded,
                  color: AppTheme.success,
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: '4.8',
                  label: 'Note\nmoyenne',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.outlineVariant),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  value: '28',
                  label: 'Ce mois',
                  icon: Icons.calendar_month_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: '2.4h',
                  label: 'Temps moyen',
                  icon: Icons.timer_rounded,
                  color: const Color(0xFF0891B2),
                ),
              ),
              _buildStatDivider(),
              Expanded(
                child: _buildStatItem(
                  value: '7',
                  label: 'Jours actifs',
                  icon: Icons.bolt_rounded,
                  color: AppTheme.warning,
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
            value: 'Moussa Diallo',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: 'moussa.diallo@email.com',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.cake_rounded,
            label: 'Date de naissance',
            value: '12 Juin 1992',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Zone de livraison',
            value: 'Cotonou & Environs',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.verified_user_rounded,
            label: 'Statut',
            value: 'Vérifié',
            valueColor: AppTheme.success,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.successContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Actif',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.success,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
                onTap: () => setState(() => _selectedVehicle = v),
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
            value: 'DK-4521-AB',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.card_membership_rounded,
            label: 'Permis de conduire',
            value: 'SN-2019-00847',
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.security_rounded,
            label: 'Assurance',
            value: 'Valide jusqu\'au 31 Déc 2024',
            valueColor: AppTheme.success,
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
      case 'Camionnette':
        return Icons.local_shipping_rounded;
      case 'À pied':
        return Icons.directions_walk_rounded;
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
            value: '+221 77 123 45 67',
            isVerified: true,
          ),
          _buildDivider(),
          _buildContactRow(
            icon: Icons.phone_android_rounded,
            label: 'Téléphone secondaire',
            value: '+221 76 987 65 43',
            isVerified: false,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.emergency_rounded,
            label: 'Contact urgence',
            value: 'Fatou Diallo · +221 78 555 00 11',
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
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildBankAccountSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.account_balance_rounded,
            title: 'Compte Bancaire & Paiement',
          ),
          const SizedBox(height: 16),
          _buildBankCard(
            bankName: 'Ecobank Sénégal',
            accountNumber: '•••• •••• 4821',
            accountHolder: 'Moussa Diallo',
            isDefault: true,
            icon: Icons.account_balance_rounded,
            color: const Color(0xFF1E40AF),
          ),
          const SizedBox(height: 12),
          _buildMobileMoneyCard(
            provider: 'Orange Money',
            phone: '+221 77 123 45 67',
            isDefault: false,
            color: const Color(0xFFFF6600),
          ),
          const SizedBox(height: 12),
          _buildMobileMoneyCard(
            provider: 'Wave',
            phone: '+221 77 123 45 67',
            isDefault: false,
            color: const Color(0xFF00B8D9),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              'Ajouter un moyen de paiement',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              side: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankCard({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required bool isDefault,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDefault ? color.withAlpha(80) : AppTheme.outline,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bankName,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
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
                          'Principal',
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
                  accountNumber,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  accountHolder,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppTheme.muted,
              size: 20,
            ),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMoneyCard({
    required String provider,
    required String phone,
    required bool isDefault,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                provider[0],
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
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
                  provider,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  phone,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppTheme.muted,
              size: 20,
            ),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsHistory() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader(
                icon: Icons.history_rounded,
                title: 'Historique des Versements',
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Voir tout',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._earningsHistory.map((e) => _buildEarningsRow(e)),
        ],
      ),
    );
  }

  Widget _buildEarningsRow(Map<String, dynamic> entry) {
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
                  entry['id'],
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${entry['date']} · ${entry['deliveries']}',
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
                entry['amount'],
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
                  color: entry['statusBg'],
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  entry['status'],
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: entry['statusColor'],
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
            onChanged: (v) => setState(() => _selectedLanguage = v!),
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
            onChanged: (v) => setState(() => _availableOnline = v),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.flash_on_rounded,
            label: 'Accepter livraisons urgentes',
            subtitle: 'Livraisons express avec bonus',
            value: _acceptUrgent,
            onChanged: (v) => setState(() => _acceptUrgent = v),
          ),
          _buildDivider(),
          const SizedBox(height: 8),
          Text(
            'Notifications',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildToggleRow(
            icon: Icons.local_shipping_rounded,
            label: 'Nouvelles livraisons',
            subtitle: 'Alertes pour les nouvelles missions',
            value: _notifNewDeliveries,
            onChanged: (v) => setState(() => _notifNewDeliveries = v),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.chat_bubble_rounded,
            label: 'Messages',
            subtitle: 'Notifications de chat',
            value: _notifMessages,
            onChanged: (v) => setState(() => _notifMessages = v),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Paiements',
            subtitle: 'Confirmations de versement',
            value: _notifPayments,
            onChanged: (v) => setState(() => _notifPayments = v),
          ),
          _buildDivider(),
          _buildToggleRow(
            icon: Icons.campaign_rounded,
            label: 'Promotions',
            subtitle: 'Offres et bonus spéciaux',
            value: _notifPromotions,
            onChanged: (v) => setState(() => _notifPromotions = v),
          ),
        ],
      ),
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

  void _showEditProfileDialog() {
    final controller = TextEditingController(text: 'Moussa Diallo');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Modifier le profil',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Nom complet',
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
              Navigator.pop(ctx);
              AppToast.show(
                context,
                message: 'Profil mis à jour avec succès.',
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
  }

  Widget _buildDivider() {
    return const Divider(height: 1, color: AppTheme.outlineVariant);
  }
}
