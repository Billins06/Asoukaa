import 'package:supabase_flutter/supabase_flutter.dart';
import './supabase_service.dart';

/// Lightweight analytics service — logs events to `analytics_events` table.
/// All methods are fire-and-forget (errors are silently swallowed so they
/// never break the UI).
class AnalyticsService {
  static AnalyticsService? _instance;
  static AnalyticsService get instance => _instance ??= AnalyticsService._();
  AnalyticsService._();

  SupabaseClient get _client => SupabaseService.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  Future<void> _log(Map<String, dynamic> payload) async {
    try {
      await _client.from('analytics_events').insert({
        'user_id': _userId,
        ...payload,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Silent — analytics must never crash the app
    }
  }

  /// Track when a user views a product detail page.
  Future<void> trackProductView({
    required String productId,
    required String productName,
    String? shopId,
  }) => _log({
    'event_type': 'product_view',
    'product_id': productId,
    'product_name': productName,
    'shop_id': shopId,
  });

  /// Track when a user adds a product to the cart.
  Future<void> trackCartAdd({
    required String productId,
    required String productName,
    required double amount,
    int quantity = 1,
    String? shopId,
  }) => _log({
    'event_type': 'cart_add',
    'product_id': productId,
    'product_name': productName,
    'shop_id': shopId,
    'amount': amount,
    'metadata': {'quantity': quantity},
  });

  /// Track when a purchase is completed.
  Future<void> trackPurchase({
    required String orderId,
    required double amount,
    List<Map<String, dynamic>>? items,
  }) => _log({
    'event_type': 'purchase',
    'order_id': orderId,
    'amount': amount,
    'metadata': {'items': items ?? []},
  });

  /// Track when a user opens a chat conversation.
  Future<void> trackChatOpen({String? productId, String? shopId}) => _log({
    'event_type': 'chat_open',
    'product_id': productId,
    'shop_id': shopId,
  });
}
