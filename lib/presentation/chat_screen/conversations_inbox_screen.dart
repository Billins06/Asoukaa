import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/unread_messages_notifier.dart';
import '../../widgets/empty_state_widget.dart';

class ConversationsInboxScreen extends StatefulWidget {
  const ConversationsInboxScreen({super.key});

  @override
  State<ConversationsInboxScreen> createState() =>
      _ConversationsInboxScreenState();
}

class _ConversationsInboxScreenState extends State<ConversationsInboxScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _conversations = [];
  int _totalUnread = 0;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initUser() async {
    try {
      final res = await ApiService.instance.client.get('/api/v1/users/me');
      _myUserId = res.data['id'] as String?;
    } catch (_) {}
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn();
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      // Le backend expose /chat/conversations (pas /conversations), et
      // renvoie des clés camelCase (clientId/vendorId/client/vendor/...),
      // pas les anciennes clés snake_case buyer_id/seller_id/etc.
      final res = await ApiService.instance.client.get('/api/v1/chat/conversations');
      final raw = res.data;
      final rawList = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
      if (mounted) {
        final convs = (rawList as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        int unread = 0;
        int unreadConversations = 0;
        for (final c in convs) {
          final n = (c['unreadCount'] as int?) ?? 0;
          unread += n;
          if (n > 0) unreadConversations++;
        }
        // Met la pastille de l'onglet "Messages" à jour tout de suite, sans
        // attendre le prochain rafraîchissement (même définition : nombre de
        // discussions avec au moins un message non lu). La liste étant
        // paginée, on ne l'applique que si elle est complète.
        if (raw is! Map || raw['pages'] is! num || (raw['pages'] as num) <= 1) {
          UnreadMessagesNotifier.instance.count.value = unreadConversations;
        } else {
          UnreadMessagesNotifier.instance.refresh();
        }
        setState(() {
          _conversations = convs;
          _totalUnread = unread;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inHours < 1) return '${diff.inMinutes}min';
      if (diff.inDays < 1) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}j';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
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
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Messages',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (_totalUnread > 0)
              Text(
                '$_totalUnread non lu(s)',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _loadConversations,
          ),
        ],
      ),
      body: _isLoading
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          : _conversations.isEmpty
          ? Center(
              child: EmptyStateWidget(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Aucun message',
                description:
                    'Vos conversations avec les vendeurs apparaîtront ici.',
              ),
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _loadConversations,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _conversations.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isClient = conv['clientId'] == _myUserId;
                  final vendor = conv['vendor'] as Map?;
                  final client = conv['client'] as Map?;
                  final otherName = isClient
                      ? (vendor != null
                            ? (vendor['shopName'] as String? ?? 'Boutique')
                            : 'Boutique')
                      : (client != null
                            ? ('${client['prenom'] ?? ''} ${client['name'] ?? ''}')
                                  .trim()
                            : 'Client');
                  final otherAvatar = isClient
                      ? (vendor != null ? vendor['logoUrl'] as String? : null)
                      : (client != null ? client['avatarUrl'] as String? : null);
                  final unread = (conv['unreadCount'] as int?) ?? 0;
                  final lastMessage = conv['lastMessage'] as Map?;
                  final lastMsg = lastMessage != null
                      ? (lastMessage['content'] as String? ??
                            (lastMessage['imageUrl'] != null ? '📷 Photo' : ''))
                      : '';
                  final lastMsgAt = lastMessage != null
                      ? lastMessage['createdAt'] as String?
                      : conv['updatedAt'] as String?;
                  final product = conv['product'] as Map<String, dynamic>?;
                  // Présence de l'interlocuteur fournie par le serveur.
                  final otherPresence = conv['otherUser'];
                  final otherIsOnline =
                      otherPresence is Map && otherPresence['isOnline'] == true;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: Stack(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryMuted,
                          ),
                          child: otherAvatar != null && otherAvatar.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    otherAvatar,
                                    fit: BoxFit.cover,
                                    semanticLabel: 'Photo de $otherName',
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(
                                        otherName.isNotEmpty
                                            ? otherName[0].toUpperCase()
                                            : 'U',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    otherName.isNotEmpty
                                        ? otherName[0].toUpperCase()
                                        : 'U',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                        ),
                        if (otherIsOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        if (unread > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  unread > 9 ? '9+' : '$unread',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherName,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTime(lastMsgAt),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: unread > 0
                                ? AppTheme.primary
                                : AppTheme.muted,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product != null)
                          Container(
                            margin: const EdgeInsets.only(top: 2, bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryMuted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              product['name'] as String? ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        Text(
                          lastMsg.isEmpty ? 'Nouvelle conversation' : lastMsg,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: unread > 0
                                ? AppTheme.textPrimary
                                : AppTheme.muted,
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    onTap: () {
                      final otherId = isClient
                          ? (vendor != null ? vendor['userId'] as String? : null)
                          : (client != null ? client['id'] as String? : null);
                      Navigator.pushNamed(
                        context,
                        AppRoutes.chat,
                        arguments: {
                          'conversation_id': conv['id'],
                          if (isClient && vendor != null) 'vendor_id': vendor['id'],
                          'seller_id': otherId,
                          'seller_name': otherName,
                          'seller_avatar': otherAvatar ?? '',
                          if (product != null) 'product_name': product['name'],
                        },
                      ).then((_) => _loadConversations());
                    },
                  );
                },
              ),
            ),
    );
  }
}
