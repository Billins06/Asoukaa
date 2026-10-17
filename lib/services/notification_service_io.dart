import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationPlatform {
  /// Appelé quand l'utilisateur touche une notification (charge utile =
  /// `type`, `referenceType`, `referenceId`).
  static void Function(Map<String, String?> payload)? onTap;

  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    final p = action.payload;
    if (p != null) onTap?.call(p);
  }

  /// Charge utile de la notification qui a LANCÉ l'appli (démarrage à froid),
  /// ou null.
  static Future<Map<String, String?>?> actionInitiale() async {
    try {
      final a = await AwesomeNotifications()
          .getInitialNotificationAction(removeFromActionEvents: true);
      return a?.payload;
    } catch (_) {
      return null;
    }
  }

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

    await AwesomeNotifications()
        .setListeners(onActionReceivedMethod: _onActionReceived);

    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelKey,
    Map<String, String?>? payload,
  }) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: channelKey,
          title: title,
          body: body,
          payload: payload,
          notificationLayout: NotificationLayout.Default,
          autoDismissible: true,
        ),
      );
    } catch (_) {}
  }
}