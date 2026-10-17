// Web stub — awesome_notifications is not supported on web
// All methods are no-ops on web platform

class NotificationPlatform {
  static void Function(Map<String, String?> payload)? onTap;

  static Future<Map<String, String?>?> actionInitiale() async => null;

  static Future<void> initialize() async {}

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelKey,
    Map<String, String?>? payload,
  }) async {}
}
