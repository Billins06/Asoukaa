import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationPlatform {
  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, // use default app icon
      [
        NotificationChannel(
          channelKey: 'general_channel',
          channelName: 'Notifications générales',
          channelDescription: 'Notifications générales Asoukaa',
          defaultColor: const Color(0xFFFF6210),
          ledColor: const Color(0xFFFF6210),
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'orders_channel',
          channelName: 'Commandes',
          channelDescription: 'Mises à jour de vos commandes',
          defaultColor: const Color(0xFF3B82F6),
          ledColor: const Color(0xFF3B82F6),
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'messages_channel',
          channelName: 'Messages',
          channelDescription: 'Nouveaux messages reçus',
          defaultColor: const Color(0xFFFF6210),
          ledColor: const Color(0xFFFF6210),
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'seller_channel',
          channelName: 'Vendeur',
          channelDescription: 'Approbations et rejets vendeur',
          defaultColor: const Color(0xFF16A34A),
          ledColor: const Color(0xFF16A34A),
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
      ],
      debug: false,
    );

    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelKey,
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: channelKey,
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          autoDismissible: true,
        ),
      );
    } catch (_) {}
  }
}