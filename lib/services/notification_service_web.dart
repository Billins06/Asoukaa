// Web stub — awesome_notifications is not supported on web
// All methods are no-ops on web platform

class NotificationPlatform {
  static Future<void> initialize() async {}

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelKey,
  }) async {}
}
