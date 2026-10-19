import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session_navigator.dart';
import '../routes/app_routes.dart';
import './api_service.dart';
import './mode_service.dart';
import './nest_auth_service.dart';
import './token_storage_service.dart';
import './unread_messages_notifier.dart';

// Conditional import for awesome_notifications (not web compatible)
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_io.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  Timer? _pollingTimer;
  bool _initialized = false;

  // ── Mémoire des notifications déjà vues (sondage) ───────────────────────
  // `createdAt` de la dernière notification vue : envoyé au serveur comme
  // paramètre `since` (et re-vérifié ici, car un ancien serveur l'ignore).
  // En plus, les identifiants déjà affichés sont mémorisés : une même
  // notification n'est jamais montrée deux fois. Le tout est rangé PAR
  // COMPTE dans SharedPreferences (survit au redémarrage de l'appli).
  DateTime? _since; // null = pas encore de point de départ (1er sondage)
  final List<String> _idsAffiches = <String>[];
  String? _comptePrefs;
  bool _sondageEnCours = false;
  static const int _maxIdsMemorises = 100;

  /// Compteur de notifications non lues, partagé par tous les écrans qui
  /// affichent un badge (en-tête de l'accueil, dashboard livreur, ...).
  ///
  /// Même principe que `WishlistService.countNotifier` : une seule source de
  /// vérité, écoutée directement par les badges via ValueListenableBuilder,
  /// plutôt qu'un `int` recopié dans le state de chaque écran et vite
  /// périmé. Dès qu'un écran appelle [refreshUnreadCount], tous les badges
  /// de l'app se mettent à jour.
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  // ── Initialize push notifications ─────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!kIsWeb) {
      await NotificationPlatform.initialize();
      // Toucher une notification affichée ouvre l'écran concerné.
      NotificationPlatform.onTap = _gererToucher;
      // Appli lancée PAR un toucher sur une notification (démarrage à froid).
      try {
        final initial = await NotificationPlatform.actionInitiale();
        if (initial != null) {
          Future.delayed(
            const Duration(milliseconds: 2500),
            () => _gererToucher(initial),
          );
        }
      } catch (_) {}
    }
  }

  // ── Ouverture de l'écran lié à une notification ───────────────────────

  void _gererToucher(Map<String, String?> payload) {
    ouvrirDepuisReference(payload['referenceType'], payload['referenceId']);
  }

  /// Ouvre l'écran correspondant à une notification d'après son
  /// `referenceType` / `referenceId` (champs renvoyés par le serveur).
  ///  - order     : suivi de la commande (client) ou tableau de bord vendeur
  ///                / livreur selon le rôle actif (le suivi `orders/me/:id`
  ///                n'est accessible qu'au client propriétaire) ;
  ///  - delivery, independent_delivery : tableau de bord livreur ;
  ///  - independent_delivery_client : « Mes courses express » (client) ;
  ///  - conversation : la discussion ; support_ticket : le ticket.
  Future<void> ouvrirDepuisReference(String? type, String? id) async {
    if (type == null || type.isEmpty) return;
    String route;
    Object? arguments;
    switch (type) {
      case 'order':
        if (id == null || id.isEmpty) return;
        String role = 'acheteur';
        try {
          role = await ModeService.instance.getEffectiveRole();
        } catch (_) {}
        if (role == 'vendeur') {
          route = AppRoutes.sellerDashboard;
        } else if (role == 'livreur') {
          route = AppRoutes.delivererDashboard;
        } else {
          route = AppRoutes.orderTracking;
          arguments = {'orderId': id};
        }
        break;
      case 'delivery':
      case 'independent_delivery':
        route = AppRoutes.delivererDashboard;
        break;
      case 'independent_delivery_client':
        route = AppRoutes.myExpressDeliveries;
        break;
      case 'conversation':
        if (id == null || id.isEmpty) return;
        route = AppRoutes.chat;
        arguments = {'conversation_id': id};
        break;
      case 'support_ticket':
        if (id == null || id.isEmpty) return;
        route = AppRoutes.ticketDetail;
        arguments = id;
        break;
      default:
        return;
    }
    // Le Navigator peut ne pas être prêt juste après un démarrage à froid.
    for (var i = 0; i < 10; i++) {
      final nav = rootNavigatorKey.currentState;
      if (nav != null) {
        nav.pushNamed(route, arguments: arguments);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // ── Poll for new notifications for current user ────────────────────────

  void subscribeToUserNotifications() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _sonder();
    });
    // Premier sondage immédiat : fixe le point de départ (voir _sonder).
    _sonder();
  }

  String _cleSince(String compte) => 'notif_since_$compte';
  String _cleIds(String compte) => 'notif_ids_$compte';

  /// Charge (une fois par compte) le point de départ et les identifiants déjà
  /// affichés depuis SharedPreferences.
  Future<void> _chargerMemoire(String compte) async {
    if (_comptePrefs == compte) return;
    _comptePrefs = compte;
    _since = null;
    _idsAffiches.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_cleSince(compte));
      if (s != null && s.isNotEmpty) _since = DateTime.tryParse(s)?.toUtc();
      _idsAffiches.addAll(prefs.getStringList(_cleIds(compte)) ?? const []);
    } catch (_) {}
  }

  Future<void> _sauverMemoire() async {
    final compte = _comptePrefs;
    if (compte == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_since != null) {
        await prefs.setString(_cleSince(compte), _since!.toIso8601String());
      }
      await prefs.setStringList(_cleIds(compte), List<String>.from(_idsAffiches));
    } catch (_) {}
  }

  /// Un passage de sondage : demande les notifications plus récentes que
  /// [_since] et affiche celles qui n'ont jamais été montrées.
  ///
  /// Premier sondage d'un compte sur ce téléphone (aucun point de départ) :
  /// on se contente de mémoriser ce qui existe déjà SANS l'afficher, pour ne
  /// pas inonder l'utilisateur avec d'anciennes notifications.
  Future<void> _sonder() async {
    if (_sondageEnCours) return;
    _sondageEnCours = true;
    try {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn();
      if (!isLoggedIn) return;
      // Les comptes administrateurs n'ont pas de notifications utilisateur.
      final roleBrut = await TokenStorageService.instance.getUserRole();
      if (roleBrut == 'admin' || roleBrut == 'superadmin') return;
      final compte = (await TokenStorageService.instance.getUserId()) ?? 'anonyme';
      await _chargerMemoire(compte);

      // Le polling sert aussi à tenir les badges à jour sans que l'écran
      // affiché ait quoi que ce soit à faire.
      await refreshUnreadCount();

      final premierSondage = _since == null;
      final res = await ApiService.instance.client.get(
        '/api/v1/notifications',
        queryParameters: {
          if (_since != null) 'since': _since!.toUtc().toIso8601String(),
          'limit': '10',
        },
      );
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);

      // On convertit puis on trie du plus ancien au plus récent.
      final recues = <Map<String, dynamic>>[];
      for (final n in list as List) {
        if (n is Map) recues.add(Map<String, dynamic>.from(n));
      }
      DateTime dateDe(Map<String, dynamic> n) =>
          DateTime.tryParse('${n['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      recues.sort((a, b) => dateDe(a).compareTo(dateDe(b)));

      var plusRecent = _since;
      var aAfficher = 0;
      for (final n in recues) {
        final id = '${n['id'] ?? ''}';
        final date = dateDe(n);
        if (plusRecent == null || date.isAfter(plusRecent)) plusRecent = date;
        if (premierSondage) {
          // Simple mémorisation du point de départ.
          if (id.isNotEmpty && !_idsAffiches.contains(id)) _idsAffiches.add(id);
          continue;
        }
        // Un ancien serveur ignore `since` : on filtre aussi ici, et on
        // dédoublonne par identifiant.
        if (_since != null && !date.isAfter(_since!)) continue;
        if (id.isNotEmpty && _idsAffiches.contains(id)) continue;
        if (id.isNotEmpty) _idsAffiches.add(id);
        if (aAfficher < 5) {
          aAfficher++;
          _handleIncomingNotification(n);
        }
      }
      // Aucune notification au premier sondage : point de départ = « avant
      // tout », donc la prochaine qui arrive sera bien affichée.
      _since = plusRecent ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      while (_idsAffiches.length > _maxIdsMemorises) {
        _idsAffiches.removeAt(0);
      }
      await _sauverMemoire();
    } catch (_) {
      // Réseau coupé, serveur indisponible... : on réessaiera dans 30 s.
    } finally {
      _sondageEnCours = false;
    }
  }

  void unsubscribe() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _comptePrefs = null;
    _since = null;
    _idsAffiches.clear();
    // Déconnexion : le badge ne doit pas garder le compte de l'ancien
    // utilisateur.
    unreadCountNotifier.value = 0;
    UnreadMessagesNotifier.instance.reset();
  }

  // ── Compteur de notifications non lues ───────────────────────────

  /// Recharge le vrai compte depuis `GET /api/v1/notifications/unread-count`
  /// et notifie tous les badges. À appeler au démarrage d'un écran, quand il
  /// reprend le focus, et au retour de l'écran de notifications (pour que le
  /// badge redescende une fois les notifications lues).
  Future<void> refreshUnreadCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        unreadCountNotifier.value = 0;
        return;
      }
      final response = await ApiService.instance.client
          .get('/api/v1/notifications/unread-count');
      final data = response.data;
      final count =
          data is Map ? (data['unreadCount'] as num?)?.toInt() : null;
      if (count != null) unreadCountNotifier.value = count;
    } catch (_) {
      // En cas d'erreur réseau on garde la dernière valeur connue plutôt
      // que de faire clignoter le badge à 0.
    }
  }

  // ── Handle incoming notification and show push ─────────────────────────

  void _handleIncomingNotification(Map<String, dynamic> record) {
    // Une notification arrive (ex. nouveau message) : on remet à jour la
    // pastille de l'onglet "Messages" (appel dédupliqué côté notifieur).
    UnreadMessagesNotifier.instance.refresh();
    final title = record['title'] as String? ?? 'Asoukaa';
    final body = record['body'] as String? ?? '';
    // Le serveur renvoie le champ `type` ; les anciens noms restent lus.
    final type = (record['type'] ??
            record['notificationType'] ??
            record['notification_type'] ??
            'general')
        .toString();
    final id = '${record['id'] ?? ''}';

    if (!kIsWeb) {
      NotificationPlatform.showNotification(
        id: id.isNotEmpty
            ? (id.hashCode & 0x7FFFFFFF)
            : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        channelKey: _channelKeyForType(type),
        payload: {
          'type': type,
          if (record['referenceType'] != null)
            'referenceType': '${record['referenceType']}',
          if (record['referenceId'] != null)
            'referenceId': '${record['referenceId']}',
        },
      );
    }
  }

  String _channelKeyForType(String type) {
    switch (type) {
      case 'approbation':
      case 'rejection':
        return 'seller_channel';
      case 'validation':
        return 'seller_channel';
      case 'commande':
      case 'livraison':
      case 'paiement':
        return 'orders_channel';
      case 'message':
      case 'chat':
      case 'ticket':
        return 'messages_channel';
      default:
        return 'general_channel';
    }
  }
}
