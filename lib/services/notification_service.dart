import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './auth_service.dart';
import './supabase_service.dart';

// Conditional import for awesome_notifications (not web compatible)
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_io.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  RealtimeChannel? _notifChannel;
  bool _initialized = false;

  // ── Initialize push notifications ─────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!kIsWeb) {
      await NotificationPlatform.initialize();
    }
  }

  // ── Subscribe to real-time notifications for current user ──────────────

  void subscribeToUserNotifications() {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _notifChannel?.unsubscribe();
    _notifChannel = _client
        .channel('user_notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              _handleIncomingNotification(record);
            }
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    _notifChannel?.unsubscribe();
    _notifChannel = null;
  }

  // ── Handle incoming notification and show push ─────────────────────────

  void _handleIncomingNotification(Map<String, dynamic> record) {
    final title = record['title'] as String? ?? 'Asoukaa';
    final body = record['body'] as String? ?? '';
    final type = record['notification_type'] as String? ?? 'general';

    if (!kIsWeb) {
      NotificationPlatform.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        channelKey: _channelKeyForType(type),
      );
    }
  }

  String _channelKeyForType(String type) {
    switch (type) {
      case 'approbation':
      case 'rejection':
        return 'seller_channel';
      case 'commande':
      case 'livraison':
        return 'orders_channel';
      case 'message':
        return 'messages_channel';
      default:
        return 'general_channel';
    }
  }

  // ── Insert notification into DB (triggers real-time) ──────────────────

  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'notification_type': type,
        if (data != null) 'data': data,
        'is_read': false,
      });
    } catch (_) {}
  }

  // ── Seller approval notification ───────────────────────────────────────

  Future<void> notifySellerApproval({
    required String sellerId,
    required bool approved,
    String? reason,
  }) async {
    await sendNotification(
      userId: sellerId,
      title: approved ? '✅ Compte vendeur approuvé' : '❌ Compte rejeté',
      body: approved
          ? 'Félicitations ! Votre compte vendeur a été approuvé. Vous pouvez maintenant publier des produits.'
          : 'Votre demande de compte vendeur a été rejetée.${reason != null ? ' Raison : $reason' : ''}',
      type: approved ? 'approbation' : 'rejection',
      data: {'approved': approved, if (reason != null) 'reason': reason},
    );
  }

  // ── Product rejection notification ────────────────────────────────────

  Future<void> notifyProductRejection({
    required String sellerId,
    required String productName,
    required bool approved,
    String? reason,
  }) async {
    await sendNotification(
      userId: sellerId,
      title: approved ? '✅ Produit approuvé' : '❌ Produit rejeté',
      body: approved
          ? 'Votre produit "$productName" a été approuvé et est maintenant visible.'
          : 'Votre produit "$productName" a été rejeté.${reason != null ? ' Raison : $reason' : ''}',
      type: approved ? 'approbation' : 'rejection',
      data: {
        'product_name': productName,
        'approved': approved,
        if (reason != null) 'reason': reason,
      },
    );
  }

  // ── Order status notification ─────────────────────────────────────────

  Future<void> notifyOrderStatus({
    required String buyerId,
    required String orderNumber,
    required String status,
  }) async {
    final labels = {
      'confirme': (
        '✅ Commande confirmée',
        'Votre commande #$orderNumber a été confirmée.',
      ),
      'en_preparation': (
        '📦 En préparation',
        'Votre commande #$orderNumber est en cours de préparation.',
      ),
      'expedie': (
        '🚚 Commande expédiée',
        'Votre commande #$orderNumber a été expédiée.',
      ),
      'en_livraison': (
        '📍 Livreur en route',
        'Votre commande #$orderNumber est en route vers vous.',
      ),
      'livre': (
        '🎉 Commande livrée !',
        'Votre commande #$orderNumber a été livrée avec succès.',
      ),
      'annule': (
        '❌ Commande annulée',
        'Votre commande #$orderNumber a été annulée.',
      ),
    };
    final label = labels[status];
    if (label == null) return;
    await sendNotification(
      userId: buyerId,
      title: label.$1,
      body: label.$2,
      type: 'commande',
      data: {'order_number': orderNumber, 'status': status},
    );
  }

  // ── Chat message notification ─────────────────────────────────────────

  Future<void> notifyChatMessage({
    required String recipientId,
    required String senderName,
    required String messagePreview,
    required String conversationId,
  }) async {
    await sendNotification(
      userId: recipientId,
      title: '💬 Message de $senderName',
      body: messagePreview.length > 80
          ? '${messagePreview.substring(0, 80)}...'
          : messagePreview,
      type: 'message',
      data: {'conversation_id': conversationId, 'sender_name': senderName},
    );
  }
}