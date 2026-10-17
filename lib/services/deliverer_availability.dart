import 'package:flutter/foundation.dart';

import './api_service.dart';

/// État partagé « le livreur est-il disponible (en service) ? ».
///
/// Source unique pour le badge « En ligne / Hors ligne » du tableau de bord
/// livreur. Alimenté par :
///  - le tableau de bord, au chargement ([refresh], via
///    `GET /api/v1/delivery-agents/me` -> `isAvailableNow`) ;
///  - le profil livreur, après un `PATCH .../availability` réussi
///    ([setAvailable]).
///
/// `null` = pas encore connu : le badge ne montre alors rien plutôt qu'un
/// faux « En ligne ».
class DelivererAvailability {
  static DelivererAvailability? _instance;
  static DelivererAvailability get instance =>
      _instance ??= DelivererAvailability._();
  DelivererAvailability._();

  final ValueNotifier<bool?> isAvailable = ValueNotifier<bool?>(null);

  /// Met à jour la valeur (après un changement confirmé par le serveur).
  void setAvailable(bool value) {
    if (isAvailable.value != value) isAvailable.value = value;
  }

  /// Oublie la valeur (déconnexion : ne pas montrer l'état du compte précédent).
  void reset() {
    isAvailable.value = null;
  }

  /// Relit l'état réel sur le serveur. Silencieux en cas d'échec : on garde
  /// la dernière valeur connue.
  Future<void> refresh() async {
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/delivery-agents/me');
      final data = res.data;
      if (data is Map && data['isAvailableNow'] is bool) {
        setAvailable(data['isAvailableNow'] as bool);
      }
    } catch (_) {}
  }
}
