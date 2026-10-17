import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../core/session_navigator.dart';
import '../routes/app_routes.dart';

/// Gère les liens profonds asoukaa://<host>[?id=<id>].
///
/// Hôtes reconnus :
/// - product?id=...        → fiche produit (partage, product_gallery_widget)
/// - shop?id=...            → boutique (partage, boutique_vendeur_screen)
/// - order?id=...           → suivi de commande (emails de commande)
/// - delivery                → tableau de bord livreur (emails livreur)
/// - vendor-dashboard         → tableau de bord vendeur (emails vendeur)
///
/// Si la personne qui reçoit le lien a déjà l'application installée, elle
/// s'ouvre directement sur la bonne page. Si elle ne l'a pas, le lien ne
/// fait rien (pas de site web associé pour l'instant — voir la discussion
/// avec Collins sur ce sujet).
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      debugPrint('[DeepLinkService] getInitialLink error: $e');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('[DeepLinkService] uriLinkStream error: $e'),
    );
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'asoukaa') return;

    // On accepte deux formes : asoukaa://<host>?id=XXX
    // et asoukaa://<host>/XXX (au cas où).
    final id = uri.queryParameters['id'] ??
        (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null);

    switch (uri.host) {
      case 'product':
        if (id != null && id.isNotEmpty) _navigateToProduct(id);
        break;
      case 'shop':
        if (id != null && id.isNotEmpty) _navigateToShop(id);
        break;
      case 'order':
        if (id != null && id.isNotEmpty) _navigateToOrder(id);
        break;
      case 'delivery':
        // Pas d'id de livraison spécifique transmis par les mails livreur
        // pour l'instant — on ouvre le tableau de bord, la course est
        // visible depuis là.
        _navigateWithRetry(AppRoutes.delivererDashboard, null);
        break;
      case 'vendor-dashboard':
        _navigateWithRetry(AppRoutes.sellerDashboard, null);
        break;
    }
  }

  void _navigateToProduct(String productId) {
    _navigateWithRetry(AppRoutes.productDetail, {'id': productId});
  }

  void _navigateToShop(String shopId) {
    _navigateWithRetry(AppRoutes.boutiqueVendeur, {'id': shopId});
  }

  void _navigateToOrder(String orderId) {
    _navigateWithRetry(AppRoutes.orderTracking, {'orderId': orderId});
  }

  void _navigateWithRetry(String route, Map<String, dynamic>? arguments) {
    void attempt({int retriesLeft = 10}) {
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) {
        // Le Navigator n'est pas encore prêt (démarrage à froid de l'appli
        // via le lien) — on réessaie brièvement plutôt que de perdre le lien.
        if (retriesLeft <= 0) return;
        Future.delayed(
          const Duration(milliseconds: 300),
          () => attempt(retriesLeft: retriesLeft - 1),
        );
        return;
      }
      navigator.pushNamed(route, arguments: arguments);
    }

    attempt();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
