import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'nest_auth_service.dart';

/// Source unique du compte "liste de souhaits", partagée par tout
/// l'écran d'accueil et les endroits où on peut ajouter/retirer un
/// produit (fiche produit, cartes produit sur les listings, etc.).
///
/// Avant : chaque écran gardait son propre `int _wishlistCount` en state
/// local, mis à jour uniquement au chargement de CET écran (initState /
/// didChangeDependencies / retour au premier plan). Résultat : après un
/// ajout/retrait fait depuis la fiche produit, le badge cœur en haut de
/// l'accueil restait affiché avec l'ancienne valeur jusqu'à ce que
/// l'accueil se recharge pour une tout autre raison (ex : l'app revient
/// au premier plan après avoir consulté les notifications).
///
/// Ce singleton expose un `ValueNotifier<int>` que le badge écoute
/// directement (ValueListenableBuilder) : dès qu'un écran ajoute/retire
/// un produit avec succès, il appelle `refreshCount()` ici, et le badge
/// se met à jour instantanément, peu importe où l'action a eu lieu.
class WishlistService {
  WishlistService._();
  static final WishlistService instance = WishlistService._();

  final ValueNotifier<int> countNotifier = ValueNotifier<int>(0);

  /// Recharge le vrai compte depuis le serveur et notifie tous les
  /// écouteurs (le badge, etc.). À appeler juste après un ajout/retrait
  /// réussi, et au démarrage de l'app.
  Future<void> refreshCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        countNotifier.value = 0;
        return;
      }
      final response =
          await ApiService.instance.client.get('/api/v1/wishlist');
      final data = response.data;
      final count = data is List
          ? data.length
          : (data is Map
              ? ((data['data'] as List?)?.length ??
                  (data['items'] as List?)?.length ??
                  0)
              : 0);
      countNotifier.value = count;
    } catch (_) {
      // En cas d'erreur réseau on garde la dernière valeur connue plutôt
      // que de faire clignoter le badge à 0.
    }
  }

  // ---------------------------------------------------------------------------
  // Ids des produits favoris, partagés par toutes les cartes produit de
  // l'accueil. Avant : chaque carte appelait GET /wishlist/check/:id à sa
  // création (~20 appels par page de la grille infinie) et faisait dépasser
  // la limite de requêtes du serveur. Maintenant : un seul chargement (le
  // plus souvent une seule requête) pour toute la session.
  // ---------------------------------------------------------------------------
  Set<String>? _favoriteIds;
  Future<Set<String>?>? _favoriteIdsLoad;
  int _favoriteIdsGen = 0;
  DateTime? _favoriteIdsFailedAt;

  /// Ids déjà chargés, ou null s'ils ne le sont pas encore.
  Set<String>? get cachedFavoriteIds => _favoriteIds;

  /// Charge (une seule fois) l'ensemble des ids de produits favoris de
  /// l'utilisateur connecté. Renvoie null si non connecté ou en cas d'erreur
  /// (pas de nouvelle tentative avant 30 s, pour ne pas surcharger le
  /// serveur).
  Future<Set<String>?> favoriteIds() {
    final cached = _favoriteIds;
    if (cached != null) return Future<Set<String>?>.value(cached);
    final failedAt = _favoriteIdsFailedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
      return Future<Set<String>?>.value(null);
    }
    return _favoriteIdsLoad ??= _loadFavoriteIds();
  }

  Future<Set<String>?> _loadFavoriteIds() async {
    final gen = _favoriteIdsGen;
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) return null;
      final ids = <String>{};
      var page = 1;
      var pages = 1;
      // Le serveur plafonne à 100 éléments par page ; 10 pages au maximum.
      while (page <= pages && page <= 10) {
        final response = await ApiService.instance.client.get(
          '/api/v1/wishlist',
          queryParameters: {'page': page, 'limit': 100},
        );
        final data = response.data;
        final list = data is List ? data : (data is Map ? data['data'] : null);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final id = (item['productId'] ??
                      (item['product'] is Map ? item['product']['id'] : null))
                  ?.toString();
              if (id != null && id.isNotEmpty) ids.add(id);
            }
          }
        }
        if (data is Map && data['pages'] is num) {
          pages = (data['pages'] as num).toInt();
        }
        page++;
      }
      // Si une invalidation (déconnexion, rechargement) est survenue pendant
      // le chargement, ce résultat est périmé : on ne le garde pas.
      if (gen == _favoriteIdsGen) _favoriteIds = ids;
      return ids;
    } catch (_) {
      _favoriteIdsFailedAt = DateTime.now();
      return null;
    } finally {
      if (gen == _favoriteIdsGen) _favoriteIdsLoad = null;
    }
  }

  /// Met à jour l'ensemble partagé après un ajout / retrait réussi.
  void markFavorite(String productId, bool isFavorite) {
    final ids = _favoriteIds;
    if (ids == null || productId.isEmpty) return;
    if (isFavorite) {
      ids.add(productId);
    } else {
      ids.remove(productId);
    }
  }

  /// Oublie les ids chargés (rechargement de l'accueil, déconnexion) : le
  /// prochain affichage de carte les redemande au serveur.
  void invalidateFavoriteIds() {
    _favoriteIdsGen++;
    _favoriteIds = null;
    _favoriteIdsLoad = null;
    _favoriteIdsFailedAt = null;
  }

  void reset() {
    countNotifier.value = 0;
    invalidateFavoriteIds();
  }
}
