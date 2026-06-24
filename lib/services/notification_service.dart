import 'dart:async';
import 'package:flutter/foundation.dart';

import './api_service.dart';
import './nest_auth_service.dart';

// Conditional import for awesome_notifications (not web compatible)
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_io.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  Timer? _pollingTimer;
  DateTime? _lastPolledAt;
  bool _initialized = false;

  // ── Initialize push notifications ─────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!kIsWeb) {
      await NotificationPlatform.initialize();
    }
  }

  // ── Poll for new notifications for current user ────────────────────────

  void subscribeToUserNotifications() {
    _pollingTimer?.cancel();
    _lastPolledAt = DateTime.now();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn();
      if (!isLoggedIn) return;
      try {
        final since = _lastPolledAt?.toUtc().toIso8601String() ?? '';
        final res = await ApiService.instance.client.get(
          '/api/v1/notifications',
          queryParameters: {'since': since, 'limit': '10'},
        );
        _lastPolledAt = DateTime.now();
        final raw = res.data;
        final list = raw is List
            ? raw
            : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
        for (final n in list as List) {
          final record = Map<String, dynamic>.from(n as Map);
          _handleIncomingNotification(record);
        }
      } catch (_) {}
    });
  }

  void unsubscribe() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ── Handle incoming notification and show push ─────────────────────────

  void _handleIncomingNotification(Map<String, dynamic> record) {
    final title = record['title'] as String? ?? 'Asoukaa';
    final body = record['body'] as String? ?? '';
    final type = record['notificationType'] as String?
        ?? record['notification_type'] as String?
        ?? 'general';

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
}
