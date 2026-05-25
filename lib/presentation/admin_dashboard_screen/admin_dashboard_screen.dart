import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../routes/app_routes.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  int _totalUsers = 0;
  int _totalOrders = 0;
  int _totalProducts = 0;
  int _totalShops = 0;
  double _totalRevenue = 0;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _shops = [];
  List<Map<String, dynamic>> _deliverers = [];
  final List<Map<String, dynamic>> _supportTickets = [];

  SupabaseClient get _client => SupabaseService.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 16, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final usersRes = await _client.from('user_profiles').select().limit(200);
      final ordersRes = await _client
          .from('orders')
          .select('*, buyer:user_profiles!buyer_id(full_name)')
          .order('created_at', ascending: false)
          .limit(200);
      final productsRes = await _client
          .from('products')
          .select('*, shop:shops(name)')
          .order('created_at', ascending: false)
          .limit(200);
      final shopsRes = await _client
          .from('shops')
          .select('*, owner:user_profiles!owner_id(full_name)')
          .limit(100);

      double revenue = 0;
      for (final o in (ordersRes as List)) {
        if (o['status'] == 'delivered') {
          revenue += (o['total_amount'] as num? ?? 0).toDouble();
        }
      }

      final allUsers = List<Map<String, dynamic>>.from(usersRes as List);
      final deliverers = allUsers.where((u) => u['role'] == 'livreur').toList();

      if (mounted) {
        setState(() {
          _users = allUsers;
          _orders = List<Map<String, dynamic>>.from(ordersRes);
          _products = List<Map<String, dynamic>>.from(productsRes as List);
          _shops = List<Map<String, dynamic>>.from(shopsRes as List);
          _deliverers = deliverers;
          _totalUsers = _users.length;
          _totalOrders = _orders.length;
          _totalProducts = _products.length;
          _totalShops = _shops.length;
          _totalRevenue = revenue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatPrice(double price) {
    final p = price.toInt();
    final s = p.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
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
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Super Admin',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: Color(0xFFFF6210),
            ),
            onPressed: () => _showSendNotificationDialog(),
            tooltip: 'Envoyer notification',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFF6210)),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF9E9E9E)),
            onPressed: () async {
              await AuthService.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, AppRoutes.signUpLogin);
              }
            },
          ),
        ],
        bottom: TabBar(
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
            Tab(text: 'Vue d\'ensemble'),
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Approbations'),
            Tab(text: 'Vérification ID'),
            Tab(text: 'Commandes'),
            Tab(text: 'Produits'),
            Tab(text: 'Boutiques'),
            Tab(text: 'Commissions'),
            Tab(text: 'Livreurs'),
            Tab(text: 'Bannières'),
            Tab(text: 'Paiements'),
            Tab(text: 'Remboursements'),
            Tab(text: 'Retraits'),
            Tab(text: 'Avis'),
            Tab(text: 'Journaux'),
            Tab(text: 'Support Tickets'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6210)),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(
                  totalUsers: _totalUsers,
                  totalOrders: _totalOrders,
                  totalProducts: _totalProducts,
                  totalShops: _totalShops,
                  totalRevenue: _totalRevenue,
                  formatPrice: _formatPrice,
                  recentOrders: _orders.take(5).toList(),
                  onSendNotification: _showSendNotificationDialog,
                  onSendMessage: _showSendMessageDialog,
                ),
                _UsersTab(users: _users, onRefresh: _loadData, client: _client),
                _AccountApprovalsTab(client: _client, onRefresh: _loadData),
                _IdentityVerificationTab(client: _client, onRefresh: _loadData),
                _OrdersTab(
                  orders: _orders,
                  onRefresh: _loadData,
                  client: _client,
                ),
                _ProductsTab(
                  products: _products,
                  onRefresh: _loadData,
                  client: _client,
                  shops: _shops,
                ),
                _ShopsTab(shops: _shops, onRefresh: _loadData),
                _CommissionsTab(client: _client),
                _DeliverersTab(
                  deliverers: _deliverers,
                  orders: _orders,
                  client: _client,
                  onRefresh: _loadData,
                ),
                _BannersTab(client: _client),
                _PaymentModulesTab(client: _client),
                _RefundsTab(
                  orders: _orders,
                  client: _client,
                  onRefresh: _loadData,
                ),
                _WithdrawalsTab(client: _client, onRefresh: _loadData),
                _ReviewModerationTab(client: _client),
                _ActivityLogsTab(client: _client),
                _SupportTicketsAdminTab(client: _client),
              ],
            ),
    );
  }

  void _showSendNotificationDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Envoyer une notification',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Titre',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
              try {
                // Insert notification for all users
                for (final user in _users) {
                  await _client.from('notifications').insert({
                    'user_id': user['id'],
                    'title': titleCtrl.text,
                    'body': bodyCtrl.text,
                    'type': 'admin_broadcast',
                    'is_read': false,
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Notification envoyée à ${_users.length} utilisateurs',
                      ),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Envoyer à tous'),
          ),
        ],
      ),
    );
  }

  void _showSendMessageDialog() {
    final msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Message à tous les utilisateurs',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: msgCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message envoyé à tous les utilisateurs'),
                  backgroundColor: Color(0xFF10B981),
                ),
              );
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}

// ─── Account Approvals Tab ─────────────────────────────────────────────────────

class _AccountApprovalsTab extends StatefulWidget {
  final SupabaseClient client;
  final VoidCallback onRefresh;
  const _AccountApprovalsTab({required this.client, required this.onRefresh});

  @override
  State<_AccountApprovalsTab> createState() => _AccountApprovalsTabState();
}

class _AccountApprovalsTabState extends State<_AccountApprovalsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingAccounts = [];
  String _filter = 'Tous';

  @override
  void initState() {
    super.initState();
    _loadPendingAccounts();
  }

  Future<void> _loadPendingAccounts() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.client
          .from('user_profiles')
          .select()
          .inFilter('role', ['vendeur', 'livreur'])
          .or('account_status.is.null,account_status.eq.pending')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _pendingAccounts = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      // Fallback: load all sellers and deliverers
      try {
        final res = await widget.client
            .from('user_profiles')
            .select()
            .inFilter('role', ['vendeur', 'livreur'])
            .order('created_at', ascending: false);
        if (mounted) {
          setState(() {
            _pendingAccounts = List<Map<String, dynamic>>.from(res as List);
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return _pendingAccounts;
    if (_filter == 'Vendeurs') {
      return _pendingAccounts.where((u) => u['role'] == 'vendeur').toList();
    }
    if (_filter == 'Livreurs') {
      return _pendingAccounts.where((u) => u['role'] == 'livreur').toList();
    }
    final statusMap = {
      'En attente': 'pending',
      'Approuvés': 'approved',
      'Rejetés': 'rejected',
    };
    return _pendingAccounts
        .where((u) => (u['account_status'] ?? 'pending') == statusMap[_filter])
        .toList();
  }

  Future<void> _approveAccount(Map<String, dynamic> user) async {
    try {
      await widget.client
          .from('user_profiles')
          .update({'account_status': 'approved'})
          .eq('id', user['id']);
      // Send notification
      await widget.client.from('notifications').insert({
        'user_id': user['id'],
        'title': 'Compte approuvé ✅',
        'body':
            'Félicitations ! Votre compte ${user['role']} a été approuvé. Vous pouvez maintenant utiliser toutes les fonctionnalités.',
        'type': 'account_approved',
        'is_read': false,
      });
      _loadPendingAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Compte de ${user['full_name'] ?? 'l\'utilisateur'} approuvé',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'approbation')),
        );
      }
    }
  }

  Future<void> _rejectAccount(Map<String, dynamic> user, String reason) async {
    try {
      await widget.client
          .from('user_profiles')
          .update({'account_status': 'rejected', 'rejection_reason': reason})
          .eq('id', user['id']);
      await widget.client.from('notifications').insert({
        'user_id': user['id'],
        'title': 'Compte rejeté ❌',
        'body':
            'Votre demande de compte ${user['role']} a été rejetée. Raison: $reason',
        'type': 'account_rejected',
        'is_read': false,
      });
      _loadPendingAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Compte de ${user['full_name'] ?? 'l\'utilisateur'} rejeté',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur lors du rejet')));
      }
    }
  }

  void _showRejectDialog(Map<String, dynamic> user) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rejeter le compte',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Indiquez la raison du rejet pour ${user['full_name'] ?? 'cet utilisateur'}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Ex: Documents incomplets, informations incorrectes...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _rejectAccount(user, reasonCtrl.text.trim());
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                    'Tous',
                    'Vendeurs',
                    'Livreurs',
                    'En attente',
                    'Approuvés',
                    'Rejetés',
                  ].map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryMuted
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            f,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6210)),
                )
              : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.how_to_reg_outlined,
                        size: 48,
                        color: Color(0xFF9E9E9E),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Aucun compte à approuver',
                        style: GoogleFonts.outfit(
                          color: AppTheme.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPendingAccounts,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final u = _filtered[i];
                      final role = u['role'] as String? ?? 'vendeur';
                      final status =
                          u['account_status'] as String? ?? 'pending';
                      final statusColors = {
                        'pending': const Color(0xFFD97706),
                        'approved': const Color(0xFF10B981),
                        'rejected': const Color(0xFFDC2626),
                      };
                      final statusLabels = {
                        'pending': 'En attente',
                        'approved': 'Approuvé',
                        'rejected': 'Rejeté',
                      };
                      final roleColor = role == 'vendeur'
                          ? const Color(0xFF10B981)
                          : const Color(0xFF8B5CF6);
                      final statusColor =
                          statusColors[status] ?? const Color(0xFFD97706);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: roleColor.withAlpha(30),
                                  child: Text(
                                    (u['full_name'] as String? ?? 'U')[0]
                                        .toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      color: roleColor,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u['full_name'] as String? ?? 'Inconnu',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        u['phone'] as String? ??
                                            u['email'] as String? ??
                                            '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: roleColor.withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        statusLabels[status] ?? status,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (u['rejection_reason'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 14,
                                      color: Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Raison: ${u['rejection_reason']}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (status == 'pending') ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showRejectDialog(u),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Rejeter'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFDC2626,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFDC2626),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _approveAccount(u),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Approuver'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
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
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Identity Verification Tab ─────────────────────────────────────────────────

class _IdentityVerificationTab extends StatefulWidget {
  final SupabaseClient client;
  final VoidCallback onRefresh;
  const _IdentityVerificationTab({
    required this.client,
    required this.onRefresh,
  });

  @override
  State<_IdentityVerificationTab> createState() =>
      _IdentityVerificationTabState();
}

class _IdentityVerificationTabState extends State<_IdentityVerificationTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _verificationRequests = [];
  String _filter = 'Tous';

  @override
  void initState() {
    super.initState();
    _loadVerifications();
  }

  Future<void> _loadVerifications() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.client
          .from('user_profiles')
          .select()
          .inFilter('role', ['vendeur', 'livreur'])
          .not('id_card_url', 'is', null)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _verificationRequests = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      // Fallback: load sellers and deliverers
      try {
        final res = await widget.client
            .from('user_profiles')
            .select()
            .inFilter('role', ['vendeur', 'livreur'])
            .order('created_at', ascending: false);
        if (mounted) {
          setState(() {
            _verificationRequests = List<Map<String, dynamic>>.from(
              res as List,
            );
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return _verificationRequests;
    final statusMap = {
      'En attente': 'pending',
      'Vérifiés': 'verified',
      'Rejetés': 'rejected',
    };
    return _verificationRequests
        .where(
          (u) => (u['verification_status'] ?? 'pending') == statusMap[_filter],
        )
        .toList();
  }

  Future<void> _verifyAccount(Map<String, dynamic> user) async {
    try {
      await widget.client
          .from('user_profiles')
          .update({'verification_status': 'verified', 'is_verified': true})
          .eq('id', user['id']);
      await widget.client.from('notifications').insert({
        'user_id': user['id'],
        'title': 'Identité vérifiée ✅',
        'body':
            'Votre identité a été vérifiée avec succès. Votre compte est maintenant certifié.',
        'type': 'identity_verified',
        'is_read': false,
      });
      _loadVerifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Identité de ${user['full_name'] ?? 'l\'utilisateur'} vérifiée',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la vérification')),
        );
      }
    }
  }

  Future<void> _rejectVerification(
    Map<String, dynamic> user,
    String reason,
  ) async {
    try {
      await widget.client
          .from('user_profiles')
          .update({
            'verification_status': 'rejected',
            'verification_rejection_reason': reason,
          })
          .eq('id', user['id']);
      await widget.client.from('notifications').insert({
        'user_id': user['id'],
        'title': 'Vérification rejetée ❌',
        'body':
            'Votre vérification d\'identité a été rejetée. Raison: $reason. Veuillez soumettre à nouveau vos documents.',
        'type': 'verification_rejected',
        'is_read': false,
      });
      _loadVerifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vérification de ${user['full_name'] ?? 'l\'utilisateur'} rejetée',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur lors du rejet')));
      }
    }
  }

  void _showRejectVerificationDialog(Map<String, dynamic> user) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rejeter la vérification',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Raison du rejet pour ${user['full_name'] ?? 'cet utilisateur'}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Ex: Photo floue, document expiré, informations illisibles...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _rejectVerification(user, reasonCtrl.text.trim());
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }

  void _showDocumentViewer(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Documents de ${user['full_name'] ?? 'l\'utilisateur'}',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DocumentItem(
                label: 'Carte d\'identité',
                url: user['id_card_url'] as String?,
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 10),
              _DocumentItem(
                label: 'Registre de commerce',
                url: user['business_reg_url'] as String?,
                icon: Icons.business_outlined,
              ),
              const SizedBox(height: 10),
              _DocumentItem(
                label: 'Photo de profil',
                url: user['avatar_url'] as String?,
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showRejectVerificationDialog(user);
                      },
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Rejeter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _verifyAccount(user);
                      },
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: const Text('Vérifier'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF3B82F6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Vérification d\'identité',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Examinez les documents soumis par les vendeurs et livreurs',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Tous', 'En attente', 'Vérifiés', 'Rejetés'].map((
                    f,
                  ) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryMuted
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            f,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6210)),
                )
              : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 48,
                        color: Color(0xFF9E9E9E),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Aucune vérification en attente',
                        style: GoogleFonts.outfit(
                          color: AppTheme.muted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les documents soumis apparaîtront ici',
                        style: GoogleFonts.outfit(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadVerifications,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final u = _filtered[i];
                      final role = u['role'] as String? ?? 'vendeur';
                      final verStatus =
                          u['verification_status'] as String? ?? 'pending';
                      final isVerified =
                          u['is_verified'] == true || verStatus == 'verified';
                      final hasIdCard = u['id_card_url'] != null;
                      final hasBusinessReg = u['business_reg_url'] != null;
                      final roleColor = role == 'vendeur'
                          ? const Color(0xFF10B981)
                          : const Color(0xFF8B5CF6);
                      final verColors = {
                        'pending': const Color(0xFFD97706),
                        'verified': const Color(0xFF10B981),
                        'rejected': const Color(0xFFDC2626),
                      };
                      final verLabels = {
                        'pending': 'En attente',
                        'verified': 'Vérifié',
                        'rejected': 'Rejeté',
                      };
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: roleColor.withAlpha(30),
                                  child: Text(
                                    (u['full_name'] as String? ?? 'U')[0]
                                        .toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      color: roleColor,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            u['full_name'] as String? ??
                                                'Inconnu',
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          if (isVerified) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.verified_rounded,
                                              size: 14,
                                              color: Color(0xFF3B82F6),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        u['phone'] as String? ??
                                            u['email'] as String? ??
                                            '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: roleColor.withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (verColors[verStatus] ??
                                                    const Color(0xFFD97706))
                                                .withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        verLabels[verStatus] ?? verStatus,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              verColors[verStatus] ??
                                              const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Documents status
                            Row(
                              children: [
                                _DocBadge(
                                  label: 'Carte d\'identité',
                                  hasDoc: hasIdCard,
                                ),
                                const SizedBox(width: 8),
                                _DocBadge(
                                  label: 'Registre commerce',
                                  hasDoc: hasBusinessReg,
                                ),
                              ],
                            ),
                            if (u['verification_rejection_reason'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 14,
                                      color: Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Raison: ${u['verification_rejection_reason']}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _showDocumentViewer(context, u),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Voir documents'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF3B82F6),
                                      side: const BorderSide(
                                        color: Color(0xFF3B82F6),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                                if (verStatus == 'pending') ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _verifyAccount(u),
                                      icon: const Icon(
                                        Icons.verified_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Vérifier'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _DocBadge extends StatelessWidget {
  final String label;
  final bool hasDoc;
  const _DocBadge({required this.label, required this.hasDoc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasDoc
            ? const Color(0xFF10B981).withAlpha(20)
            : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasDoc
              ? const Color(0xFF10B981).withAlpha(60)
              : AppTheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDoc
                ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 12,
            color: hasDoc ? const Color(0xFF10B981) : AppTheme.muted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: hasDoc ? const Color(0xFF10B981) : AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentItem extends StatelessWidget {
  final String label;
  final String? url;
  final IconData icon;
  const _DocumentItem({
    required this.label,
    required this.url,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: url != null ? const Color(0xFF3B82F6) : AppTheme.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  url != null ? 'Document soumis' : 'Aucun document',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: url != null
                        ? const Color(0xFF10B981)
                        : AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Voir',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Manquant',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Overview Tab ─────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final int totalUsers, totalOrders, totalProducts, totalShops;
  final double totalRevenue;
  final String Function(double) formatPrice;
  final List<Map<String, dynamic>> recentOrders;
  final VoidCallback onSendNotification;
  final VoidCallback onSendMessage;

  const _OverviewTab({
    required this.totalUsers,
    required this.totalOrders,
    required this.totalProducts,
    required this.totalShops,
    required this.totalRevenue,
    required this.formatPrice,
    required this.recentOrders,
    required this.onSendNotification,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statistiques globales',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _StatCard(
                label: 'Utilisateurs',
                value: '$totalUsers',
                icon: Icons.people_rounded,
                color: const Color(0xFF3B82F6),
              ),
              _StatCard(
                label: 'Commandes',
                value: '$totalOrders',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFFFF6210),
              ),
              _StatCard(
                label: 'Produits',
                value: '$totalProducts',
                icon: Icons.inventory_2_rounded,
                color: const Color(0xFF10B981),
              ),
              _StatCard(
                label: 'Boutiques',
                value: '$totalShops',
                icon: Icons.storefront_rounded,
                color: const Color(0xFF8B5CF6),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
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
                const Icon(
                  Icons.payments_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenus totaux (livrés)',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                    Text(
                      '${formatPrice(totalRevenue)} FCFA',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.notifications_active_rounded,
                  label: 'Notifier tous',
                  color: const Color(0xFF3B82F6),
                  onTap: onSendNotification,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.message_rounded,
                  label: 'Message global',
                  color: const Color(0xFF10B981),
                  onTap: onSendMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Commandes récentes',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (recentOrders.isEmpty)
            Center(
              child: Text(
                'Aucune commande',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              ),
            )
          else
            ...recentOrders.map((o) => _OrderRow(order: o)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    final statusColors = {
      'pending': const Color(0xFFD97706),
      'confirmed': const Color(0xFF3B82F6),
      'shipped': const Color(0xFF8B5CF6),
      'delivered': const Color(0xFF10B981),
      'cancelled': const Color(0xFFDC2626),
    };
    final color = statusColors[status] ?? AppTheme.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['id']?.toString().substring(0, 8) ?? 'N/A',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  (order['buyer'] as Map?)?['full_name'] as String? ??
                      'Acheteur',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${order['total_amount'] ?? 0} FCFA',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Users Tab ─────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final VoidCallback onRefresh;
  final SupabaseClient client;
  const _UsersTab({
    required this.users,
    required this.onRefresh,
    required this.client,
  });

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _filter = 'Tous';

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return widget.users;
    final roleMap = {
      'Acheteurs': 'acheteur',
      'Vendeurs': 'vendeur',
      'Livreurs': 'livreur',
      'Admins': 'admin',
    };
    return widget.users.where((u) => u['role'] == roleMap[_filter]).toList();
  }

  void _showUserActions(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _UserActionsSheet(
        user: user,
        client: widget.client,
        onDone: widget.onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Tous', 'Acheteurs', 'Vendeurs', 'Livreurs', 'Admins']
                  .map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryMuted
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            f,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    'Aucun utilisateur',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = _filtered[i];
                    final role = u['role'] as String? ?? 'acheteur';
                    final roleColors = {
                      'acheteur': const Color(0xFF3B82F6),
                      'vendeur': const Color(0xFF10B981),
                      'livreur': const Color(0xFF8B5CF6),
                      'admin': const Color(0xFFDC2626),
                    };
                    final color = roleColors[role] ?? AppTheme.muted;
                    final isBlocked = u['is_blocked'] == true;
                    return GestureDetector(
                      onTap: () => _showUserActions(u),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isBlocked
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
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
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: color.withAlpha(30),
                              child: Text(
                                (u['full_name'] as String? ?? 'U')[0]
                                    .toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u['full_name'] as String? ?? 'Inconnu',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    u['phone'] as String? ??
                                        u['email'] as String? ??
                                        '',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                  if (u['last_seen'] != null)
                                    Text(
                                      'Dernière connexion: ${_formatDate(u['last_seen'])}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
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
                                  child: Text(
                                    role,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                                if (isBlocked)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.block_rounded,
                                      size: 14,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }
}

class _UserActionsSheet extends StatelessWidget {
  final Map<String, dynamic> user;
  final SupabaseClient client;
  final VoidCallback onDone;
  const _UserActionsSheet({
    required this.user,
    required this.client,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = user['is_blocked'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user['full_name'] as String? ?? 'Utilisateur',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            user['role'] as String? ?? '',
            style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          _ActionTile(
            icon: Icons.manage_accounts_rounded,
            label: 'Changer le rôle',
            onTap: () => _changeRole(context),
          ),
          _ActionTile(
            icon: Icons.lock_reset_rounded,
            label: 'Réinitialiser mot de passe',
            onTap: () => _resetPassword(context),
          ),
          _ActionTile(
            icon: isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
            label: isBlocked ? 'Débloquer le compte' : 'Bloquer le compte',
            color: isBlocked ? AppTheme.success : AppTheme.error,
            onTap: () => _toggleBlock(context, isBlocked),
          ),
          _ActionTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Bloquer les retraits',
            onTap: () => _blockWithdrawals(context),
          ),
        ],
      ),
    );
  }

  void _changeRole(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Changer le rôle',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['acheteur', 'vendeur', 'livreur', 'admin']
              .map(
                (role) => ListTile(
                  title: Text(role, style: GoogleFonts.outfit()),
                  trailing: user['role'] == role
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFFFF6210),
                        )
                      : null,
                  onTap: () async {
                    await client
                        .from('user_profiles')
                        .update({'role': role})
                        .eq('id', user['id']);
                    Navigator.pop(ctx);
                    onDone();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _resetPassword(BuildContext context) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email de réinitialisation envoyé'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  void _toggleBlock(BuildContext context, bool isBlocked) async {
    Navigator.pop(context);
    await client
        .from('user_profiles')
        .update({'is_blocked': !isBlocked})
        .eq('id', user['id']);
    onDone();
  }

  void _blockWithdrawals(BuildContext context) async {
    Navigator.pop(context);
    await client
        .from('user_profiles')
        .update({'withdrawals_blocked': true})
        .eq('id', user['id']);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retraits bloqués pour cet utilisateur'),
        backgroundColor: Color(0xFFD97706),
      ),
    );
    onDone();
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return ListTile(
      leading: Icon(icon, color: c, size: 20),
      title: Text(label, style: GoogleFonts.outfit(fontSize: 14, color: c)),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// ─── Orders Tab ─────────────────────────────────────────────────────────────────

class _OrdersTab extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final VoidCallback onRefresh;
  final SupabaseClient client;
  const _OrdersTab({
    required this.orders,
    required this.onRefresh,
    required this.client,
  });

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  String _filter = 'Tous';

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return widget.orders;
    return widget.orders
        .where((o) => o['status'] == _filter.toLowerCase())
        .toList();
  }

  void _showOrderActions(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OrderActionsSheet(
        order: order,
        client: widget.client,
        onDone: widget.onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                    'Tous',
                    'Pending',
                    'Confirmed',
                    'Shipped',
                    'Delivered',
                    'Cancelled',
                  ].map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryMuted
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            f,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_filtered.length} commandes',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showCreateOrderDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Créer commande'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    'Aucune commande',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = _filtered[i];
                    return GestureDetector(
                      onTap: () => _showOrderActions(o),
                      child: _OrderRow(order: o),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCreateOrderDialog(BuildContext context) {
    final clientNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Créer une commande',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: clientNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nom du client',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Téléphone',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Adresse',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Montant (FCFA)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                final orderNumber =
                    'ASK-ADMIN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                await widget.client.from('orders').insert({
                  'order_number': orderNumber,
                  'status': 'pending',
                  'total_amount': double.tryParse(amountCtrl.text) ?? 0,
                  'delivery_address':
                      '${clientNameCtrl.text} - ${phoneCtrl.text} - ${addressCtrl.text}',
                  'created_by_admin': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                widget.onRefresh();
              } catch (_) {
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }
}

class _OrderActionsSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final SupabaseClient client;
  final VoidCallback onDone;
  const _OrderActionsSheet({
    required this.order,
    required this.client,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Commande #${order['id']?.toString().substring(0, 8) ?? ''}',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${order['total_amount'] ?? 0} FCFA',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Changer le statut:',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  'pending',
                  'confirmed',
                  'shipped',
                  'delivered',
                  'cancelled',
                ].map((s) {
                  return GestureDetector(
                    onTap: () async {
                      await client
                          .from('orders')
                          .update({'status': s})
                          .eq('id', order['id']);
                      Navigator.pop(context);
                      onDone();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: order['status'] == s
                            ? AppTheme.primaryMuted
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: order['status'] == s
                              ? AppTheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        s,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: order['status'] == s
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 16),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer la commande',
            color: AppTheme.error,
            onTap: () async {
              await client.from('orders').delete().eq('id', order['id']);
              Navigator.pop(context);
              onDone();
            },
          ),
        ],
      ),
    );
  }
}

// ─── Products Tab ─────────────────────────────────────────────────────────────

class _ProductsTab extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final VoidCallback onRefresh;
  final SupabaseClient client;
  final List<Map<String, dynamic>> shops;
  const _ProductsTab({
    required this.products,
    required this.onRefresh,
    required this.client,
    required this.shops,
  });

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  String _filter = 'Tous';

  List<Map<String, dynamic>> get _filteredProducts {
    if (_filter == 'Tous') return widget.products;
    if (_filter == 'En attente') {
      return widget.products
          .where((p) => (p['approval_status'] ?? 'pending') == 'pending')
          .toList();
    }
    if (_filter == 'Approuvés') {
      return widget.products
          .where(
            (p) => p['approval_status'] == 'approved' || p['is_active'] == true,
          )
          .toList();
    }
    if (_filter == 'Rejetés') {
      return widget.products
          .where((p) => p['approval_status'] == 'rejected')
          .toList();
    }
    return widget.products;
  }

  void _showProductActions(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductActionsSheet(
        product: product,
        client: widget.client,
        shops: widget.shops,
        onDone: widget.onRefresh,
      ),
    );
  }

  Future<void> _approveProduct(Map<String, dynamic> product) async {
    try {
      await widget.client
          .from('products')
          .update({'approval_status': 'approved', 'is_active': true})
          .eq('id', product['id']);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produit "${product['name']}" approuvé'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _rejectProduct(
    Map<String, dynamic> product,
    String reason,
  ) async {
    try {
      await widget.client
          .from('products')
          .update({
            'approval_status': 'rejected',
            'is_active': false,
            'rejection_reason': reason,
          })
          .eq('id', product['id']);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produit "${product['name']}" rejeté'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (_) {}
  }

  void _showRejectProductDialog(Map<String, dynamic> product) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rejeter le produit',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Raison du rejet pour "${product['name'] ?? 'ce produit'}"',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Ex: Images de mauvaise qualité, description insuffisante...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _rejectProduct(product, reasonCtrl.text.trim());
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Tous', 'En attente', 'Approuvés', 'Rejetés'].map((f) {
                final isSelected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryMuted
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        f,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${filtered.length} produits',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Aucun produit',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    final isActive = p['is_active'] == true;
                    final isFeatured = p['is_featured'] == true;
                    final approvalStatus =
                        p['approval_status'] as String? ?? 'pending';
                    final approvalColors = {
                      'pending': const Color(0xFFD97706),
                      'approved': const Color(0xFF10B981),
                      'rejected': const Color(0xFFDC2626),
                    };
                    final approvalLabels = {
                      'pending': 'En attente',
                      'approved': 'Approuvé',
                      'rejected': 'Rejeté',
                    };
                    return GestureDetector(
                      onTap: () => _showProductActions(p),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    p['images'] != null &&
                                            (p['images'] as List).isNotEmpty
                                        ? (p['images'] as List).first.toString()
                                        : 'https://via.placeholder.com/50',
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 50,
                                      height: 50,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['name'] as String? ?? 'Produit',
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        (p['shop'] as Map?)?['name']
                                                as String? ??
                                            '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            '${p['price'] ?? 0} FCFA',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${p['sold_count'] ?? 0} vendus',
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(
                                                0xFF10B981,
                                              ).withAlpha(25)
                                            : AppTheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isActive ? 'Actif' : 'Inactif',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? const Color(0xFF10B981)
                                              : AppTheme.muted,
                                        ),
                                      ),
                                    ),
                                    if (isFeatured)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFD97706,
                                            ).withAlpha(25),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Vedette',
                                            style: GoogleFonts.outfit(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFFD97706),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            // Approval status + quick actions
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (approvalColors[approvalStatus] ??
                                                const Color(0xFFD97706))
                                            .withAlpha(20),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    approvalLabels[approvalStatus] ??
                                        approvalStatus,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          approvalColors[approvalStatus] ??
                                          const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (approvalStatus != 'approved')
                                  GestureDetector(
                                    onTap: () => _approveProduct(p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Approuver',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (approvalStatus != 'rejected') ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _showRejectProductDialog(p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Rejeter',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProductActionsSheet extends StatelessWidget {
  final Map<String, dynamic> product;
  final SupabaseClient client;
  final List<Map<String, dynamic>> shops;
  final VoidCallback onDone;
  const _ProductActionsSheet({
    required this.product,
    required this.client,
    required this.shops,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final isFeatured = product['is_featured'] == true;
    final isActive = product['is_active'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product['name'] as String? ?? 'Produit',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${product['price'] ?? 0} FCFA',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _ActionTile(
            icon: isFeatured ? Icons.star_rounded : Icons.star_outline_rounded,
            label: isFeatured ? 'Retirer de la vedette' : 'Mettre en vedette',
            color: const Color(0xFFD97706),
            onTap: () async {
              await client
                  .from('products')
                  .update({'is_featured': !isFeatured})
                  .eq('id', product['id']);
              Navigator.pop(context);
              onDone();
            },
          ),
          _ActionTile(
            icon: isActive
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            label: isActive ? 'Désactiver le produit' : 'Activer le produit',
            onTap: () async {
              await client
                  .from('products')
                  .update({'is_active': !isActive})
                  .eq('id', product['id']);
              Navigator.pop(context);
              onDone();
            },
          ),
          _ActionTile(
            icon: Icons.storefront_outlined,
            label: 'Attribuer à une boutique',
            onTap: () => _assignToShop(context),
          ),
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Modifier le nombre de vendus',
            onTap: () => _editSoldCount(context),
          ),
          _ActionTile(
            icon: Icons.star_half_rounded,
            label: 'Modifier la note',
            onTap: () => _editRating(context),
          ),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer le produit',
            color: AppTheme.error,
            onTap: () async {
              await client.from('products').delete().eq('id', product['id']);
              Navigator.pop(context);
              onDone();
            },
          ),
        ],
      ),
    );
  }

  void _assignToShop(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Attribuer à une boutique',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shops.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(
                shops[i]['name'] as String? ?? 'Boutique',
                style: GoogleFonts.outfit(),
              ),
              onTap: () async {
                await client
                    .from('products')
                    .update({'shop_id': shops[i]['id']})
                    .eq('id', product['id']);
                Navigator.pop(ctx);
                onDone();
              },
            ),
          ),
        ),
      ),
    );
  }

  void _editSoldCount(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: '${product['sold_count'] ?? 0}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Modifier le nombre de vendus',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Nombre de vendus',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await client
                  .from('products')
                  .update({'sold_count': int.tryParse(ctrl.text) ?? 0})
                  .eq('id', product['id']);
              Navigator.pop(ctx);
              onDone();
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }

  void _editRating(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: '${product['rating'] ?? 4.5}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Modifier la note (1-5)',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await client
                  .from('products')
                  .update({'rating': double.tryParse(ctrl.text) ?? 4.5})
                  .eq('id', product['id']);
              Navigator.pop(ctx);
              onDone();
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }
}

// ─── Shops Tab ─────────────────────────────────────────────────────────────────

class _ShopsTab extends StatelessWidget {
  final List<Map<String, dynamic>> shops;
  final VoidCallback onRefresh;
  const _ShopsTab({required this.shops, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) {
      return Center(
        child: Text(
          'Aucune boutique',
          style: GoogleFonts.outfit(color: AppTheme.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: shops.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = shops[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name'] as String? ?? 'Boutique',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      (s['owner'] as Map?)?['full_name'] as String? ??
                          'Propriétaire',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                    Text(
                      s['category'] as String? ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Active',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Commissions Tab ─────────────────────────────────────────────────────────────

class _CommissionsTab extends StatefulWidget {
  final SupabaseClient client;
  const _CommissionsTab({required this.client});

  @override
  State<_CommissionsTab> createState() => _CommissionsTabState();
}

class _CommissionsTabState extends State<_CommissionsTab> {
  final _globalPctCtrl = TextEditingController(text: '10');
  bool _isSaving = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _commissions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _globalPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load current commission rate
      final rateResult = await widget.client
          .from('commission_settings')
          .select('rate')
          .eq('is_active', true)
          .maybeSingle();
      if (rateResult != null) {
        _globalPctCtrl.text = '${rateResult['rate'] ?? 10}';
      }

      // Load recent commissions
      final commissionsResult = await widget.client
          .from('commissions')
          .select('*, user_profiles!seller_id(full_name), orders(order_number)')
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _commissions = List<Map<String, dynamic>>.from(
            commissionsResult as List,
          );
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRate() async {
    final rate = double.tryParse(_globalPctCtrl.text);
    if (rate == null || rate < 0 || rate > 100) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Taux invalide (0-100%)')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.client.from('commission_settings').upsert({
        'rate': rate,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Commission mise à jour: $rate%'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  String _formatPrice(double price) {
    final p = price.toInt();
    final s = p.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Commission globale',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
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
              children: [
                TextField(
                  controller: _globalPctCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Commission globale (%)',
                    suffixText: '%',
                    helperText: 'Appliquée sur toutes les ventes et livraisons',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveRate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Sauvegarder',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Historique commissions (${_commissions.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: _loadData,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          else if (_commissions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Aucune commission enregistrée',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              ),
            )
          else
            ..._commissions.map((c) {
              final seller = c['user_profiles'] as Map<String, dynamic>?;
              final order = c['orders'] as Map<String, dynamic>?;
              final commAmt = (c['commission_amount'] as num? ?? 0).toDouble();
              final netAmt = (c['seller_net_amount'] as num? ?? 0).toDouble();
              final rate = (c['commission_rate'] as num? ?? 10).toDouble();
              final status = c['status'] as String? ?? 'pending';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                            order?['order_number'] as String? ?? 'Commande',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            seller?['full_name'] as String? ?? 'Vendeur',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
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
                          '${_formatPrice(commAmt)} FCFA ($rate%)',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          'Net vendeur: ${_formatPrice(netAmt)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: AppTheme.muted,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: status == 'paid'
                                ? AppTheme.successContainer
                                : AppTheme.warningContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status == 'paid' ? 'Payé' : 'En attente',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: status == 'paid'
                                  ? AppTheme.success
                                  : AppTheme.warning,
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

// ─── Deliverers Tab ─────────────────────────────────────────────────────────────

class _DeliverersTab extends StatefulWidget {
  final List<Map<String, dynamic>> deliverers;
  final List<Map<String, dynamic>> orders;
  final SupabaseClient client;
  final VoidCallback onRefresh;
  const _DeliverersTab({
    required this.deliverers,
    required this.orders,
    required this.client,
    required this.onRefresh,
  });

  @override
  State<_DeliverersTab> createState() => _DeliverersTabState();
}

class _DeliverersTabState extends State<_DeliverersTab> {
  void _assignDeliverer(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Affecter un livreur',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Commande #${order['id']?.toString().substring(0, 8) ?? ''}',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            if (widget.deliverers.isEmpty)
              Text(
                'Aucun livreur disponible',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              )
            else
              ...widget.deliverers.map(
                (d) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF8B5CF6).withAlpha(30),
                    child: Text(
                      (d['full_name'] as String? ?? 'L')[0],
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF8B5CF6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    d['full_name'] as String? ?? 'Livreur',
                    style: GoogleFonts.outfit(fontSize: 14),
                  ),
                  subtitle: Text(
                    d['phone'] as String? ?? '',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.muted,
                    ),
                  ),
                  onTap: () async {
                    await widget.client.from('deliverer_missions').upsert({
                      'order_id': order['id'],
                      'deliverer_id': d['id'],
                      'status': 'accepte',
                    }, onConflict: 'order_id');
                    Navigator.pop(context);
                    widget.onRefresh();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders = widget.orders
        .where((o) => o['status'] == 'confirmed' || o['status'] == 'shipped')
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Livreurs (${widget.deliverers.length})',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.deliverers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Aucun livreur enregistré',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              ),
            )
          else
            ...widget.deliverers.map(
              (d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                    CircleAvatar(
                      backgroundColor: const Color(0xFF8B5CF6).withAlpha(30),
                      child: Text(
                        (d['full_name'] as String? ?? 'L')[0],
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF8B5CF6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['full_name'] as String? ?? 'Livreur',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            d['phone'] as String? ?? '',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Livreur',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Commandes à affecter (${pendingOrders.length})',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (pendingOrders.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Aucune commande en attente d\'affectation',
                style: GoogleFonts.outfit(color: AppTheme.muted),
              ),
            )
          else
            ...pendingOrders.map(
              (o) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                            '#${o['id']?.toString().substring(0, 8) ?? ''}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          Text(
                            '${o['total_amount'] ?? 0} FCFA',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _assignDeliverer(o),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Affecter',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
}

// ─── Banners Tab ─────────────────────────────────────────────────────────────────

class _BannersTab extends StatefulWidget {
  final SupabaseClient client;
  const _BannersTab({required this.client});

  @override
  State<_BannersTab> createState() => _BannersTabState();
}

class _BannersTabState extends State<_BannersTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _banners = [];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.client
          .from('banners')
          .select()
          .order('position', ascending: true);
      if (mounted) {
        setState(() {
          _banners = List<Map<String, dynamic>>.from(result as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBannerDialog() {
    final titleCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Ajouter une bannière',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Titre',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: imageCtrl,
              decoration: InputDecoration(
                labelText: 'URL de l\'image',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: linkCtrl,
              decoration: InputDecoration(
                labelText: 'Lien (route)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await widget.client.from('banners').insert({
                  'title': titleCtrl.text,
                  'image_url': imageCtrl.text,
                  'link_url': linkCtrl.text,
                  'is_active': true,
                  'position': _banners.length,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadBanners();
              } catch (_) {
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'Bannières (${_banners.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAddBannerDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajouter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _banners.isEmpty
              ? Center(
                  child: Text(
                    'Aucune bannière',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _banners.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final b = _banners[i];
                    final isActive = b['is_active'] as bool? ?? true;
                    return Container(
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
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(14),
                            ),
                            child: Image.network(
                              b['image_url'] as String? ?? '',
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: AppTheme.surfaceVariant,
                                child: const Icon(
                                  Icons.image_outlined,
                                  color: AppTheme.muted,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b['title'] as String? ?? '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        b['link_url'] as String? ?? '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  onChanged: (v) async {
                                    try {
                                      await widget.client
                                          .from('banners')
                                          .update({'is_active': v})
                                          .eq('id', b['id']);
                                      setState(
                                        () => _banners[i]['is_active'] = v,
                                      );
                                    } catch (_) {}
                                  },
                                  activeThumbColor: AppTheme.primary,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppTheme.error,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    try {
                                      await widget.client
                                          .from('banners')
                                          .delete()
                                          .eq('id', b['id']);
                                      setState(() => _banners.removeAt(i));
                                    } catch (_) {}
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Payment Modules Tab ──────────────────────────────────────────────────────

class _PaymentModulesTab extends StatefulWidget {
  final SupabaseClient client;
  const _PaymentModulesTab({required this.client});

  @override
  State<_PaymentModulesTab> createState() => _PaymentModulesTabState();
}

class _PaymentModulesTabState extends State<_PaymentModulesTab> {
  final List<Map<String, dynamic>> _modules = [
    {
      'name': 'FeexPay',
      'icon': Icons.payment_rounded,
      'enabled': true,
      'color': const Color(0xFF3B82F6),
      'description': 'Mobile Money (MTN, Moov, Wave)',
    },
    {
      'name': 'Orange Money',
      'icon': Icons.phone_android_rounded,
      'enabled': false,
      'color': const Color(0xFFFF6210),
      'description': 'Paiement Orange Money',
    },
    {
      'name': 'Virement bancaire',
      'icon': Icons.account_balance_rounded,
      'enabled': true,
      'color': const Color(0xFF10B981),
      'description': 'Virement bancaire direct',
    },
    {
      'name': 'Paiement à la livraison',
      'icon': Icons.local_shipping_rounded,
      'enabled': true,
      'color': const Color(0xFF8B5CF6),
      'description': 'Cash à la livraison',
    },
    {
      'name': 'Stripe',
      'icon': Icons.credit_card_rounded,
      'enabled': false,
      'color': const Color(0xFF6366F1),
      'description': 'Carte bancaire internationale',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modules de paiement',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Activez ou désactivez les méthodes de paiement disponibles',
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          ..._modules.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (m['enabled'] as bool)
                      ? (m['color'] as Color).withAlpha(80)
                      : AppTheme.outlineVariant,
                ),
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (m['color'] as Color).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      m['icon'] as IconData,
                      color: m['color'] as Color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['name'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          m['description'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: m['enabled'] as bool,
                    onChanged: (v) =>
                        setState(() => _modules[i]['enabled'] = v),
                    activeThumbColor: AppTheme.primary,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paramètres de paiement',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingRow(
                  label: 'Délai de remboursement (jours)',
                  value: '7',
                ),
                _SettingRow(
                  label: 'Montant minimum de retrait (FCFA)',
                  value: '5 000',
                ),
                _SettingRow(label: 'Frais de transaction (%)', value: '2.5'),
                _SettingRow(
                  label: 'Délai de virement vendeur (jours)',
                  value: '3',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label, value;
  const _SettingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.outline),
            ),
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Refunds Tab ──────────────────────────────────────────────────────────────

class _RefundsTab extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final SupabaseClient client;
  final VoidCallback onRefresh;
  const _RefundsTab({
    required this.orders,
    required this.client,
    required this.onRefresh,
  });

  @override
  State<_RefundsTab> createState() => _RefundsTabState();
}

class _RefundsTabState extends State<_RefundsTab> {
  String _filter = 'Tous';
  bool _isLoading = true;
  List<Map<String, dynamic>> _refunds = [];

  @override
  void initState() {
    super.initState();
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.client
          .from('refund_requests')
          .select(
            '*, orders(order_number, total_amount), user_profiles!buyer_id(full_name)',
          )
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _refunds = List<Map<String, dynamic>>.from(result as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return _refunds;
    final statusMap = {
      'En attente': 'pending',
      'Approuvés': 'approved',
      'Rejetés': 'rejected',
    };
    return _refunds.where((r) => r['status'] == statusMap[_filter]).toList();
  }

  Future<void> _updateStatus(String refundId, String status) async {
    try {
      await widget.client
          .from('refund_requests')
          .update({'status': status})
          .eq('id', refundId);
      _loadRefunds();
    } catch (_) {}
  }

  String _formatPrice(double price) {
    final p = price.toInt();
    final s = p.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: ['Tous', 'En attente', 'Approuvés', 'Rejetés'].map((f) {
              final isSelected = _filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryMuted
                          : AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      f,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'Aucun remboursement',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    final order = r['orders'] as Map<String, dynamic>?;
                    final buyer = r['user_profiles'] as Map<String, dynamic>?;
                    final status = r['status'] as String? ?? 'pending';
                    final amount = (r['amount'] as num? ?? 0).toDouble();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(6),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order?['order_number'] as String? ??
                                          'Commande',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      buyer?['full_name'] as String? ??
                                          'Client',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${_formatPrice(amount)} FCFA',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            r['reason'] as String? ?? '',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (status == 'pending')
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _updateStatus(
                                      r['id'] as String,
                                      'rejected',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.error,
                                      side: const BorderSide(
                                        color: AppTheme.error,
                                      ),
                                    ),
                                    child: Text(
                                      'Rejeter',
                                      style: GoogleFonts.outfit(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _updateStatus(
                                      r['id'] as String,
                                      'approved',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.success,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      'Approuver',
                                      style: GoogleFonts.outfit(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'approved'
                                    ? AppTheme.successContainer
                                    : const Color(0xFFFFEDED),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status == 'approved' ? 'Approuvé' : 'Rejeté',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'approved'
                                      ? AppTheme.success
                                      : AppTheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Withdrawals Tab ──────────────────────────────────────────────────────────

class _WithdrawalsTab extends StatefulWidget {
  final SupabaseClient client;
  final VoidCallback onRefresh;
  const _WithdrawalsTab({required this.client, required this.onRefresh});

  @override
  State<_WithdrawalsTab> createState() => _WithdrawalsTabState();
}

class _WithdrawalsTabState extends State<_WithdrawalsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _withdrawals = [];

  @override
  void initState() {
    super.initState();
    _loadWithdrawals();
  }

  Future<void> _loadWithdrawals() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.client
          .from('withdrawals')
          .select('*, user_profiles!seller_id(full_name, phone)')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _withdrawals = List<Map<String, dynamic>>.from(result as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await widget.client
          .from('withdrawals')
          .update({
            'status': status,
            if (status == 'completed')
              'processed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      _loadWithdrawals();
    } catch (_) {}
  }

  String _formatPrice(double price) {
    final p = price.toInt();
    final s = p.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Demandes de retrait (${_withdrawals.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: _loadWithdrawals,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _withdrawals.isEmpty
              ? Center(
                  child: Text(
                    'Aucune demande de retrait',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _withdrawals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final w = _withdrawals[i];
                    final seller = w['user_profiles'] as Map<String, dynamic>?;
                    final status = w['status'] as String? ?? 'pending';
                    final amount = (w['amount'] as num? ?? 0).toDouble();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(6),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      seller?['full_name'] as String? ??
                                          'Vendeur',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      seller?['phone'] as String? ?? '',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${_formatPrice(amount)} FCFA',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Via: ${w['payment_method'] ?? 'mobile_money'}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (status == 'pending')
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _updateStatus(
                                      w['id'] as String,
                                      'rejected',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.error,
                                      side: const BorderSide(
                                        color: AppTheme.error,
                                      ),
                                    ),
                                    child: Text(
                                      'Rejeter',
                                      style: GoogleFonts.outfit(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _updateStatus(
                                      w['id'] as String,
                                      'completed',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.success,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      'Valider',
                                      style: GoogleFonts.outfit(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'completed'
                                    ? AppTheme.successContainer
                                    : const Color(0xFFFFEDED),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status == 'completed' ? 'Validé' : 'Rejeté',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'completed'
                                      ? AppTheme.success
                                      : AppTheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Review Moderation Tab ────────────────────────────────────────────────────

class _ReviewModerationTab extends StatefulWidget {
  final SupabaseClient client;
  const _ReviewModerationTab({required this.client});

  @override
  State<_ReviewModerationTab> createState() => _ReviewModerationTabState();
}

class _ReviewModerationTabState extends State<_ReviewModerationTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.client
          .from('reviews')
          .select(
            '*, user_profiles!reviewer_id(full_name, avatar_url), products(name)',
          )
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(result as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    try {
      await widget.client.from('reviews').delete().eq('id', reviewId);
      setState(() => _reviews.removeWhere((r) => r['id'] == reviewId));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Avis (${_reviews.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: _loadReviews,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _reviews.isEmpty
              ? Center(
                  child: Text(
                    'Aucun avis',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _reviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _reviews[i];
                    final reviewer =
                        r['user_profiles'] as Map<String, dynamic>?;
                    final product = r['products'] as Map<String, dynamic>?;
                    final rating = r['rating'] as int? ?? 5;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(6),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reviewer?['full_name'] as String? ?? 'Client',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  product?['name'] as String? ?? '',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                Row(
                                  children: List.generate(
                                    5,
                                    (j) => Icon(
                                      j < rating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: AppTheme.warning,
                                      size: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r['comment'] as String? ?? '',
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
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppTheme.error,
                              size: 20,
                            ),
                            onPressed: () => _deleteReview(r['id'] as String),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Activity Logs Tab ────────────────────────────────────────────────────────

class _ActivityLogsTab extends StatefulWidget {
  final SupabaseClient client;
  const _ActivityLogsTab({required this.client});

  @override
  State<_ActivityLogsTab> createState() => _ActivityLogsTabState();
}

class _ActivityLogsTabState extends State<_ActivityLogsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.client
          .from('admin_logs')
          .select('*, user_profiles!admin_id(full_name)')
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(result as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Journaux d\'activité (${_logs.length})',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.primary,
                ),
                onPressed: _loadLogs,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _logs.isEmpty
              ? Center(
                  child: Text(
                    'Aucun journal',
                    style: GoogleFonts.outfit(color: AppTheme.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final log = _logs[i];
                    final admin = log['user_profiles'] as Map<String, dynamic>?;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryMuted,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.admin_panel_settings_rounded,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log['action'] as String? ?? '',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${admin?['full_name'] ?? 'Admin'} · ${log['target_type'] ?? ''}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _formatDate(log['created_at'] as String?),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Support Tickets Admin Tab ────────────────────────────────────────────────

class _SupportTicketsAdminTab extends StatefulWidget {
  final SupabaseClient client;
  const _SupportTicketsAdminTab({required this.client});

  @override
  State<_SupportTicketsAdminTab> createState() =>
      _SupportTicketsAdminTabState();
}

class _SupportTicketsAdminTabState extends State<_SupportTicketsAdminTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tickets = [];
  String _filter = 'Tous';

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.client
          .from('support_tickets')
          .select('*, user:user_profiles!user_id(full_name, phone)')
          .order('created_at', ascending: false)
          .limit(200);
      if (mounted) {
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Tous') return _tickets;
    final statusMap = {
      'Ouverts': 'open',
      'En cours': 'in_progress',
      'Résolus': 'resolved',
    };
    return _tickets.where((t) => t['status'] == statusMap[_filter]).toList();
  }

  Future<void> _respondToTicket(Map<String, dynamic> ticket) async {
    final responseCtrl = TextEditingController();
    String selectedStatus = ticket['status'] as String? ?? 'open';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Répondre au ticket',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket['subject'] as String? ?? 'Sans sujet',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ticket['message'] as String? ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF616161),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Statut',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'open',
                      child: Text(
                        'Ouvert',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text(
                        'En cours',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text(
                        'Résolu',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'closed',
                      child: Text(
                        'Fermé',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedStatus = v);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Votre réponse',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: responseCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Rédigez votre réponse...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: GoogleFonts.outfit(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: GoogleFonts.outfit()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.client
                      .from('support_tickets')
                      .update({
                        'admin_response': responseCtrl.text.trim(),
                        'admin_reply': responseCtrl.text.trim(),
                        'status': selectedStatus,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', ticket['id']);
                  _loadTickets();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Réponse envoyée avec succès'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                } catch (_) {}
              },
              child: Text('Envoyer', style: GoogleFonts.outfit()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Tous', 'Ouverts', 'En cours', 'Résolus'].map((
                      f,
                    ) {
                      final isSelected = _filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _filter = f),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryMuted
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              f,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
                onPressed: _loadTickets,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        size: 48,
                        color: Color(0xFF9E9E9E),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Aucun ticket',
                        style: GoogleFonts.outfit(
                          color: AppTheme.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTickets,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final t = _filtered[i];
                      final status = t['status'] as String? ?? 'open';
                      final statusColors = {
                        'open': const Color(0xFFD97706),
                        'in_progress': const Color(0xFF3B82F6),
                        'resolved': const Color(0xFF10B981),
                        'closed': const Color(0xFF9E9E9E),
                      };
                      final statusLabels = {
                        'open': 'Ouvert',
                        'in_progress': 'En cours',
                        'resolved': 'Résolu',
                        'closed': 'Fermé',
                      };
                      final statusColor =
                          statusColors[status] ?? const Color(0xFFD97706);
                      final user = t['user'] as Map<String, dynamic>?;
                      final createdAt = t['created_at'] as String? ?? '';
                      String dateStr = '';
                      if (createdAt.isNotEmpty) {
                        try {
                          final dt = DateTime.parse(createdAt).toLocal();
                          dateStr =
                              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                        } catch (_) {}
                      }

                      return GestureDetector(
                        onTap: () => _respondToTicket(t),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(6),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: statusColor.withAlpha(25),
                                    child: Text(
                                      ((user?['full_name'] as String?) ??
                                              'U')[0]
                                          .toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user?['full_name'] as String? ??
                                              'Utilisateur',
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        if (user?['phone'] != null)
                                          Text(
                                            user!['phone'] as String,
                                            style: GoogleFonts.outfit(
                                              fontSize: 11,
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withAlpha(25),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          statusLabels[status] ?? status,
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dateStr,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (t['category'] != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t['category'] as String,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              Text(
                                t['subject'] as String? ?? 'Sans sujet',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                t['message'] as String? ?? '',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (t['admin_response'] != null &&
                                  (t['admin_response'] as String)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryMuted,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.reply_rounded,
                                        size: 14,
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          t['admin_response'] as String,
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            color: AppTheme.textPrimary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Répondre',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
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
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
