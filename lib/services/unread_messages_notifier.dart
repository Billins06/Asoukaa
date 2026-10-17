import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import './api_service.dart';
import './nest_auth_service.dart';

/// Compteur global du nombre de DISCUSSIONS contenant au moins un message
/// non lu (3 discussions avec des messages non lus = 3, quel que soit le
/// nombre de messages dans chacune). Il alimente la pastille de l'onglet
/// "Messages" de la barre du bas, pour les trois rôles (client, vendeur,
/// livreur).
///
/// Source de vérité unique, comme `NotificationService.unreadCountNotifier` :
/// les écrans écoutent [count] avec un ValueListenableBuilder, et n'importe
/// quel écran peut appeler [refresh] pour le remettre à jour.
///
/// Le rafraîchissement périodique (toutes les 30 s) ne tourne que tant que
/// au moins une barre du bas est affichée ([attach]/[detach]) ET que
/// l'application est au premier plan.
class UnreadMessagesNotifier with WidgetsBindingObserver {
  static UnreadMessagesNotifier? _instance;
  static UnreadMessagesNotifier get instance =>
      _instance ??= UnreadMessagesNotifier._();
  UnreadMessagesNotifier._();

  static const Duration _period = Duration(seconds: 30);

  /// Nombre de discussions avec au moins un message non lu.
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  Timer? _timer;
  int _attached = 0;
  bool _observing = false;
  bool _foreground = true;
  bool _inFlight = false;
  bool _pendingRefresh = false;

  /// Appelle `GET /api/v1/chat/unread-count`. Renvoie le nombre de
  /// discussions non lues, ou null en cas d'erreur / si personne n'est
  /// connecté (aucun appel réseau dans ce cas).
  Future<int?> getUnreadConversationCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) return 0;
      final res = await ApiService.instance.client
          .get('/api/v1/chat/unread-count');
      final data = res.data;
      if (data is Map) {
        return (data['conversations'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Recharge le compteur et notifie les badges. En cas d'erreur réseau on
  /// garde la dernière valeur connue (pas de clignotement à 0).
  Future<void> refresh() async {
    if (_inFlight) {
      // Une requête est déjà en cours : on en refera une juste après, pour
      // ne pas rater un changement survenu entre-temps (ex. lecture d'une
      // discussion), sans empiler les appels.
      _pendingRefresh = true;
      return;
    }
    _inFlight = true;
    try {
      final n = await getUnreadConversationCount();
      if (n != null && n != count.value) count.value = n;
    } finally {
      _inFlight = false;
    }
    if (_pendingRefresh) {
      _pendingRefresh = false;
      unawaited(refresh());
    }
  }

  /// Remet le compteur à zéro (déconnexion).
  void reset() {
    count.value = 0;
  }

  /// À appeler dans initState d'une barre du bas : démarre le rafraîchissement
  /// périodique (une seule minuterie partagée, quel que soit le nombre de
  /// barres affichées en même temps dans la pile de navigation).
  void attach() {
    _attached++;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_attached == 1) _startTimer();
    unawaited(refresh());
  }

  /// À appeler dans dispose de la barre du bas.
  void detach() {
    if (_attached > 0) _attached--;
    if (_attached == 0) _stopTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_foreground) return;
    _timer = Timer.periodic(_period, (_) => unawaited(refresh()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_attached > 0) {
        _startTimer();
        unawaited(refresh());
      }
    } else {
      _foreground = false;
      _stopTimer();
    }
  }
}
