import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import './error_handler.dart';
import './supabase_service.dart';

class ChatService {
  static ChatService? _instance;
  static ChatService get instance => _instance ??= ChatService._();
  ChatService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<ServiceResult<List<Map<String, dynamic>>>> getConversations(
    String userId,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('conversations')
            .select('''
              *,
              buyer:user_profiles!buyer_id(id, full_name, avatar_url),
              seller:user_profiles!seller_id(id, full_name, avatar_url),
              products(id, name, images)
            ''')
            .or('buyer_id.eq.$userId,seller_id.eq.$userId')
            .order('last_message_at', ascending: false),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<Map<String, dynamic>>> getOrCreateConversation({
    required String buyerId,
    required String sellerId,
    String? productId,
  }) async {
    try {
      // Check if conversation already exists
      final existing = await ErrorHandler.withRetry(() async {
        var query = _client
            .from('conversations')
            .select()
            .eq('buyer_id', buyerId)
            .eq('seller_id', sellerId);

        if (productId != null) {
          query = query.eq('product_id', productId);
        }

        return await query.maybeSingle();
      });

      if (existing != null) return ServiceResult.success(existing);

      // Create new conversation
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('conversations')
            .insert({
              'buyer_id': buyerId,
              'seller_id': sellerId,
              if (productId != null) 'product_id': productId,
            })
            .select()
            .single(),
      );

      return ServiceResult.success(result);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<ServiceResult<List<Map<String, dynamic>>>> getMessages(
    String conversationId,
  ) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('messages')
            .select('*, user_profiles(id, full_name, avatar_url)')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: true),
      );
      return ServiceResult.success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<Map<String, dynamic>>> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? productData,
    String? imageUrl,
  }) async {
    try {
      final result = await ErrorHandler.withRetry(
        () => _client
            .from('messages')
            .insert({
              'conversation_id': conversationId,
              'sender_id': senderId,
              'content': content,
              'message_type': messageType,
              if (productData != null) 'product_data': productData,
              if (imageUrl != null) 'image_url': imageUrl,
            })
            .select()
            .single(),
      );
      return ServiceResult.success(result);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  Future<ServiceResult<bool>> markMessagesRead(
    String conversationId,
    String userId,
  ) async {
    try {
      await ErrorHandler.withRetry(
        () => _client
            .from('messages')
            .update({'is_read': true})
            .eq('conversation_id', conversationId)
            .neq('sender_id', userId),
      );

      // Reset unread count
      final conv = await ErrorHandler.withRetry(
        () => _client
            .from('conversations')
            .select('buyer_id, seller_id')
            .eq('id', conversationId)
            .maybeSingle(),
      );

      if (conv != null) {
        if (conv['buyer_id'] == userId) {
          await ErrorHandler.withRetry(
            () => _client
                .from('conversations')
                .update({'buyer_unread': 0})
                .eq('id', conversationId),
          );
        } else {
          await ErrorHandler.withRetry(
            () => _client
                .from('conversations')
                .update({'seller_unread': 0})
                .eq('id', conversationId),
          );
        }
      }
      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── Real-time subscriptions ───────────────────────────────────────────────

  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> message) onMessage,
    void Function(Object error)? onError,
  }) {
    return _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              onMessage(Map<String, dynamic>.from(payload.newRecord));
            } catch (e) {
              onError?.call(e);
            }
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            onError?.call(error);
          }
        });
  }

  RealtimeChannel subscribeToConversations({
    required String userId,
    required void Function() onUpdate,
    void Function(Object error)? onError,
  }) {
    return _client
        .channel('conversations:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            try {
              onUpdate();
            } catch (e) {
              onError?.call(e);
            }
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            onError?.call(error);
          }
        });
  }

  RealtimeChannel subscribeToNotifications({
    required String userId,
    required void Function(Map<String, dynamic> notification) onNotification,
    void Function(Object error)? onError,
  }) {
    return _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            try {
              onNotification(Map<String, dynamic>.from(payload.newRecord));
            } catch (e) {
              onError?.call(e);
            }
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            onError?.call(error);
          }
        });
  }
}
