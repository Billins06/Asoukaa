import './api_service.dart';

/// Préférences de notification du compte (réelles, côté serveur).
///
/// `GET  /api/v1/users/me/notification-preferences` -> 6 booléens
///   {orders, messages, payments, promotions, newOrders, newDeliveries}
/// `PUT  /api/v1/users/me/notification-preferences` avec un corps PARTIEL
///   (ex. {"orders": false}) -> renvoie les 6 préférences. Une clé inconnue
///   est refusée (400).
///
/// Les deux méthodes laissent remonter l'exception en cas d'échec : l'écran
/// appelant décide du message à afficher.
class NotificationPreferencesService {
  static NotificationPreferencesService? _instance;
  static NotificationPreferencesService get instance =>
      _instance ??= NotificationPreferencesService._();
  NotificationPreferencesService._();

  static const String _path = '/api/v1/users/me/notification-preferences';

  /// Clés connues du serveur.
  static const String orders = 'orders';
  static const String messages = 'messages';
  static const String payments = 'payments';
  static const String promotions = 'promotions';
  static const String newOrders = 'newOrders';
  static const String newDeliveries = 'newDeliveries';

  /// Lit les préférences actuelles.
  Future<Map<String, bool>> load() async {
    final res = await ApiService.instance.client.get(_path);
    return _toBoolMap(res.data);
  }

  /// Modifie UNE préférence et renvoie l'ensemble des préférences du serveur.
  Future<Map<String, bool>> update(String key, bool value) async {
    final res = await ApiService.instance.client.put(
      _path,
      data: {key: value},
    );
    return _toBoolMap(res.data);
  }

  static Map<String, bool> _toBoolMap(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Réponse inattendue du serveur');
    }
    final out = <String, bool>{};
    data.forEach((k, v) {
      if (k is String && v is bool) out[k] = v;
    });
    return out;
  }
}
