import 'package:supabase_flutter/supabase_flutter.dart';

import './error_handler.dart';
import './supabase_service.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ══════════════════════════════════════════════════════════════════════════
  // PRODUCTS
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>> getProducts({
    String? category,
    String? searchQuery,
    int limit = 20,
    int offset = 0,
    bool featuredOnly = false,
  }) async {
    try {
      final result = await ErrorHandler.withRetry(() async {
        var query = _client
            .from('products')
            .select('*, shops(name, logo_url, rating, is_verified)')
            .eq('is_active', true);

        if (category != null && category.isNotEmpty) {
          query = query.eq('category', category);
        }
        if (featuredOnly) {
          query = query.eq('is_featured', true);
        }
        if (searchQuery != null && searchQuery.isNotEmpty) {
          query = query.ilike('name', '%$searchQuery%');
        }

        return await query
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      });

      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<Map<String, dynamic>>> getProductById(
    String productId,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('products')
            .select(
              '*, shops(name, logo_url, rating, is_verified, owner_id), reviews(rating, comment, created_at, reviewer_id, user_profiles(full_name, avatar_url))',
            )
            .eq('id', productId)
            .maybeSingle(),
      );
      if (result == null) {
        return ServiceResult.failure(
          'Produit introuvable.',
          type: SupabaseErrorType.notFound,
        );
      }
      return ServiceResult.success(result);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<List<Map<String, dynamic>>>> getSellerProducts(
    String sellerId,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('products')
            .select()
            .eq('seller_id', sellerId)
            .order('created_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<Map<String, dynamic>>> createProduct(
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client.from('products').insert(data).select().single(),
      );
      return ServiceResult.success(result);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> updateProduct(
    String productId,
    Map<String, dynamic> data,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('products').update(data).eq('id', productId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> deleteProduct(String productId) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('products')
            .update({'is_active': false})
            .eq('id', productId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHOPS
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getShopByOwnerId(String ownerId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('shops')
            .select()
            .eq('owner_id', ownerId)
            .maybeSingle(),
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getShopById(String shopId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('shops')
            .select('*, user_profiles(full_name, avatar_url)')
            .eq('id', shopId)
            .maybeSingle(),
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<ServiceResult<bool>> updateShop(
    String shopId,
    Map<String, dynamic> data,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('shops').update(data).eq('id', shopId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── User Profiles ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('user_profiles')
            .select()
            .eq('id', userId)
            .maybeSingle(),
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<ServiceResult<bool>> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('user_profiles').update(data).eq('id', userId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ORDERS
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>> getBuyerOrders(
    String buyerId,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('orders')
            .select('*, shops(name, logo_url)')
            .eq('buyer_id', buyerId)
            .order('created_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<Map<String, dynamic>>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client.from('orders').insert(orderData).select().single(),
      );
      return ServiceResult.success(Map<String, dynamic>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMMISSIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Get commission rate (default 10%, modifiable by admin)
  Future<double> getCommissionRate() async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('commission_settings')
            .select('rate')
            .eq('is_active', true)
            .maybeSingle(),
      );
      if (result != null) {
        return (result['rate'] as num? ?? 10.0).toDouble();
      }
      return 10.0;
    } catch (_) {
      return 10.0;
    }
  }

  /// Calculate and record commission for an order
  Future<ServiceResult<bool>> recordOrderCommission({
    required String orderId,
    required String sellerId,
    required double orderAmount,
  }) async {
    try {
      final rate = await getCommissionRate();
      final commissionAmount = orderAmount * (rate / 100);
      final sellerNet = orderAmount - commissionAmount;

      await ErrorHandler.withRetry(
        () => _client.from('commissions').upsert({
          'order_id': orderId,
          'seller_id': sellerId,
          'order_amount': orderAmount,
          'commission_rate': rate,
          'commission_amount': commissionAmount,
          'seller_net_amount': sellerNet,
          'status': 'pending',
        }, onConflict: 'order_id'),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  /// Record delivery commission
  Future<ServiceResult<bool>> recordDeliveryCommission({
    required String missionId,
    required String delivererId,
    required double deliveryFee,
  }) async {
    try {
      final rate = await getCommissionRate();
      final commissionAmount = deliveryFee * (rate / 100);
      final delivererNet = deliveryFee - commissionAmount;

      await ErrorHandler.withRetry(
        () => _client.from('delivery_commissions').upsert({
          'mission_id': missionId,
          'deliverer_id': delivererId,
          'delivery_fee': deliveryFee,
          'commission_rate': rate,
          'commission_amount': commissionAmount,
          'deliverer_net_amount': delivererNet,
          'status': 'pending',
        }, onConflict: 'mission_id'),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  /// Update commission rate (admin only)
  Future<ServiceResult<bool>> updateCommissionRate(double rate) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('commission_settings').upsert({
          'rate': rate,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BANNERS (Admin)
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>> getBanners() async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('banners')
            .select()
            .order('created_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> upsertBanner(Map<String, dynamic> data) async {
    try {
      await ErrorHandler.withRetry(() => _client.from('banners').upsert(data));
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> deleteBanner(String bannerId) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('banners').delete().eq('id', bannerId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REFUNDS (Admin)
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>> getRefundRequests() async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('refund_requests')
            .select(
              '*, orders(order_number, total_amount), user_profiles!buyer_id(full_name, email)',
            )
            .order('created_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> updateRefundStatus(
    String refundId,
    String status,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('refund_requests')
            .update({'status': status})
            .eq('id', refundId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WITHDRAWALS (Admin)
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>>
  getWithdrawalRequests() async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('withdrawals')
            .select('*, user_profiles!seller_id(full_name, email, phone)')
            .order('created_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> updateWithdrawalStatus(
    String withdrawalId,
    String status,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('withdrawals')
            .update({'status': status})
            .eq('id', withdrawalId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN LOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<ServiceResult<List<Map<String, dynamic>>>> getAdminLogs() async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('admin_logs')
            .select('*, user_profiles!admin_id(full_name)')
            .order('created_at', ascending: false)
            .limit(100),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<void> logAdminAction({
    required String adminId,
    required String action,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('admin_logs').insert({
          'admin_id': adminId,
          'action': action,
          'target_type': targetType,
          if (targetId != null) 'target_id': targetId,
          if (details != null) 'details': details,
        }),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(50),
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (_) {
      return [];
    }
  }

  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('is_read', false),
      );
      return result.length;
    } catch (_) {
      return 0;
    }
  }

  Future<ServiceResult<bool>> markNotificationRead(
    String notificationId,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('notifications')
            .update({'is_read': true})
            .eq('id', notificationId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> markAllNotificationsRead(String userId) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', userId),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REVIEWS
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getProductReviews(String productId) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('reviews')
            .select('*, user_profiles(full_name, avatar_url)')
            .eq('product_id', productId)
            .order('created_at', ascending: false),
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (_) {
      return [];
    }
  }

  Future<ServiceResult<bool>> addReview({
    required String productId,
    required String reviewerId,
    required int rating,
    String comment = '',
    String? orderId,
  }) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.from('reviews').insert({
          'product_id': productId,
          'reviewer_id': reviewerId,
          'rating': rating,
          'comment': comment,
          if (orderId != null) 'order_id': orderId,
        }),
      );
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DELIVERY PROOFS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> updateDeliveryProof(
    String orderId,
    Map<String, dynamic> proofData,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('deliverer_missions')
            .update({
              'proof_photo_url': proofData['proof_photo_url'],
              'delivery_notes': proofData['delivery_notes'] ?? '',
              'status': 'livre',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('order_id', orderId),
      );
    } catch (_) {}
  }
}
