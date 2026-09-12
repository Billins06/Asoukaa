import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';

import '../../theme/app_theme.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../widgets/empty_state_widget.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final response =
          await ApiService.instance.client.get('/api/v1/notifications');
      final rawData = response.data;
      final rawList = rawData is List
          ? rawData
          : (rawData is Map ? (rawData['data'] ?? rawData['items'] ?? []) as List : []);
      if (mounted) {
        setState(() {
          _notifications = rawList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredNotifs {
    switch (_tabController.index) {
      case 1:
        // Commandes tab: order and delivery notifications
        return _notifications
            .where(
              (n) =>
                  n['notification_type'] == 'commande' ||
                  n['notification_type'] == 'livraison',
            )
            .toList();
      case 2:
        // Promos tab
        return _notifications
            .where((n) => n['notification_type'] == 'promo')
            .toList();
      case 3:
        // Messages tab
        return _notifications
            .where((n) => n['notification_type'] == 'message')
            .toList();
      default:
        return _notifications;
    }
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] == false).length;

  Future<void> _markAllRead() async {
    try {
      await ApiService.instance.client.patch('/api/v1/notifications/read-all');
    } catch (_) {}
    if (mounted) {
      setState(() {
        for (final n in _notifications) {
          n['is_read'] = true;
        }
      });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await ApiService.instance.client.patch('/api/v1/notifications/$id/read');
    } catch (_) {}
    if (mounted) {
      setState(() {
        final idx = _notifications.indexWhere((n) => n['id'] == id);
        if (idx != -1) _notifications[idx]['is_read'] = true;
      });
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'commande':
        return Icons.shopping_bag_outlined;
      case 'livraison':
        return Icons.local_shipping_outlined;
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      case 'promo':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'commande':
        return const Color(0xFF3B82F6);
      case 'livraison':
        return const Color(0xFF16A34A);
      case 'message':
        return AppTheme.primary;
      case 'promo':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              'Notifications',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_unreadCount',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Tout lire',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.muted,
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          tabs: const [
            Tab(text: 'Toutes'),
            Tab(text: 'Commandes'),
            Tab(text: 'Promos'),
            Tab(text: 'Messages'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredNotifs.isEmpty
          ? EmptyStateWidget(
              icon: Icons.notifications_none_rounded,
              title: 'Aucune notification',
              description: 'Vous n\'avez pas encore de notifications.',
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _loadNotifications,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filteredNotifs.length,
                itemBuilder: (_, index) {
                  final notif = _filteredNotifs[index];
                  final isRead = notif['is_read'] == true;
                  final type =
                      notif['notification_type'] as String? ?? 'systeme';
                  final color = _colorForType(type);

                  return GestureDetector(
                    onTap: () => _markRead(notif['id'] as String),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isRead ? Colors.white : const Color(0xFFFFF8F5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isRead
                              ? AppTheme.outline
                              : AppTheme.primary.withAlpha(60),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _iconForType(type),
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notif['title'] as String? ?? '',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: isRead
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                          color: AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notif['body'] as String? ?? '',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatDate(notif['created_at'] as String?),
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
      if (diff.inDays == 1) return 'Hier';
      return 'Il y a ${diff.inDays} jours';
    } catch (_) {
      return '';
    }
  }
}