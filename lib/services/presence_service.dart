import 'dart:async';
import 'package:flutter/widgets.dart';

import './api_service.dart';
import './nest_auth_service.dart';
import './token_storage_service.dart';

/// Signale au serveur que l'utilisateur est actif (présence « En ligne »).
///
/// - Tant que l'application est au premier plan ET qu'un utilisateur est
///   connecté : `POST /api/v1/presence/ping` tout de suite, puis toutes les
///   45 secondes (le serveur considère « en ligne » = vu il y a moins de
///   2 minutes).
/// - En arrière-plan : plus aucun ping. Au retour au premier plan : ping
///   immédiat.
/// - À la déconnexion : les pings s'arrêtent d'eux-mêmes ; à la connexion,
///   le premier ping part dès que la session est détectée.
/// - Les échecs sont silencieux : aucune erreur n'est jamais affichée.
///
/// Un seul démarrage suffit ([start], appelé dans main.dart).
class PresenceService with WidgetsBindingObserver {
  static PresenceService? _instance;
  static PresenceService get instance => _instance ??= PresenceService._();
  PresenceService._();

  static const Duration _pingPeriod = Duration(seconds: 45);

  // Surveillance légère de l'état de connexion (lecture du stockage local,
  // aucun appel réseau) : permet de pinger dès la connexion et de s'arrêter
  // dès la déconnexion sans dépendre des écrans de connexion.
  static const Duration _watchPeriod = Duration(seconds: 10);

  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _wasLoggedIn = false;
  bool _checking = false;
  DateTime? _lastPing;

  /// Démarre le service (idempotent). À appeler une fois, après runApp.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    if (_foreground) _startTimer();
  }

  /// Arrête complètement le service.
  void stop() {
    if (!_started) return;
    _started = false;
    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// À appeler juste après une connexion réussie : le premier ping part tout
  /// de suite, même si un autre compte vient de se déconnecter il y a moins de
  /// 10 s (la surveillance n'aurait pas vu la déconnexion).
  void pingNow() {
    if (!_started || !_foreground) return;
    _wasLoggedIn = false;
    _lastPing = null;
    unawaited(_tick());
  }

  void _startTimer() {
    _timer?.cancel();
    _wasLoggedIn = false;
    _lastPing = null;
    _timer = Timer.periodic(_watchPeriod, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!_foreground || _checking) return;
    _checking = true;
    try {
      final loggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      // L'app a pu passer en arrière-plan pendant la vérification.
      if (!_foreground) return;
      if (!loggedIn) {
        _wasLoggedIn = false;
        _lastPing = null;
        return;
      }
      // Version de test : une session admin (table des administrateurs) n'a
      // pas de présence « En ligne » : on n'envoie aucun ping.
      if (kAdminLoginActif) {
        final roleStocke =
            (await TokenStorageService.instance.getUserRole() ?? '')
                .toLowerCase();
        if (roleStocke == 'admin' || roleStocke == 'superadmin') return;
      }
      final last = _lastPing;
      final due = !_wasLoggedIn ||
          last == null ||
          DateTime.now().difference(last) >= _pingPeriod;
      _wasLoggedIn = true;
      if (due) await _ping();
    } catch (_) {
      // Silencieux : la présence ne doit jamais gêner l'utilisateur.
    } finally {
      _checking = false;
    }
  }

  Future<void> _ping() async {
    _lastPing = DateTime.now();
    try {
      await ApiService.instance.client.post('/api/v1/presence/ping');
    } catch (_) {
      // Silencieux : on réessaiera au prochain cycle.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Ping immédiat au retour au premier plan.
      _startTimer();
    } else {
      _foreground = false;
      _stopTimer();
    }
  }
}
