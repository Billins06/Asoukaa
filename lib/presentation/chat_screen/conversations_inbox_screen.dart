import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
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
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await ChatService.instance.getConversations(user.id);
      if (mounted && result.isSuccess) {
        final convs = result.data ?? [];
        int unread = 0;
        for (final c in convs) {
          final isBuyer = c['buyer_id'] == user.id;
          unread += isBuyer
              ? (c['buyer_unread'] as int? ?? 0)
              : (c['seller_unread'] as int? ?? 0);
        }
        setState(() {
          _conversations = convs;
          _totalUnread = unread;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToUpdates() {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    _subscription = ChatService.instance.subscribeToConversations(
      userId: user.id,
      onUpdate: _loadConversations,
    );
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
    final user = AuthService.instance.currentUser;

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
                  final isBuyer = conv['buyer_id'] == user?.id;
                  final other = isBuyer ? conv['seller'] : conv['buyer'];
                  final otherName = other is Map
                      ? (other['full_name'] as String? ?? 'Utilisateur')
                      : 'Utilisateur';
                  final otherAvatar = other is Map
                      ? (other['avatar_url'] as String?)
                      : null;
                  final unread = isBuyer
                      ? (conv['buyer_unread'] as int? ?? 0)
                      : (conv['seller_unread'] as int? ?? 0);
                  final lastMsg = conv['last_message'] as String? ?? '';
                  final lastMsgAt = conv['last_message_at'] as String?;
                  final product = conv['products'] as Map<String, dynamic>?;

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
                      final otherId = isBuyer
                          ? (conv['seller_id'] as String? ?? '')
                          : (conv['buyer_id'] as String? ?? '');
                      Navigator.pushNamed(
                        context,
                        AppRoutes.chat,
                        arguments: {
                          'conversation_id': conv['id'],
                          'other_user_id': otherId,
                          'other_user_name': otherName,
                          'other_user_avatar': otherAvatar ?? '',
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
