import 'package:dio/dio.dart';

import 'api_service.dart';
import 'product_service.dart';

/// Accès aux données de la « Vitrine » gérée par l'admin (site web) :
/// bandeau de « Pour vous », rayons (Ventes flash, Tendances, Ventes à
/// succès, rayons libres) et produits de chaque rayon.
///
/// Routes serveur (module backend `vitrine`) :
///   GET /api/v1/vitrine                          → { bandeau, rayons }
///   GET /api/v1/vitrine/rayons/:id/products      → { data, meta }
///   GET /api/v1/vitrine/by-type/:type?limit=10   → { rayon, products }
class VitrineService {
  static VitrineService? _instance;
  static VitrineService get instance => _instance ??= VitrineService._();
  VitrineService._();

  Dio get _client => ApiService.instance.client;

  /// Bandeau (peut être null) + rayons actifs, déjà triés par le serveur.
  /// Chaque rayon : { id, nom, type, imageUrl, sortOrder, startsAt,
  /// endsAt, productCount }.
  Future<({Map<String, dynamic>? bandeau, List<Map<String, dynamic>> rayons})>
      getVitrine() async {
    try {
      final r = await _client.get('/api/v1/vitrine');
      final body = r.data;
      if (body is! Map) return (bandeau: null, rayons: <Map<String, dynamic>>[]);
      final b = body['bandeau'];
      final list = (body['rayons'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return (
        bandeau: b is Map ? Map<String, dynamic>.from(b) : null,
        rayons: list,
      );
    } catch (_) {
      return (bandeau: null, rayons: <Map<String, dynamic>>[]);
    }
  }

  /// Produits d'un rayon, normalisés comme ceux de ProductService.
  Future<ProductResult<List<Map<String, dynamic>>>> getRayonProducts(
    String rayonId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final r = await _client.get(
        '/api/v1/vitrine/rayons/$rayonId/products',
        queryParameters: {'page': page, 'limit': limit},
      );
      final body = r.data;
      final raw = body is Map ? (body['data'] as List? ?? const []) : const [];
      return ProductResult.success(_normalizeList(raw));
    } on DioException catch (e) {
      return ProductResult.failure(
        e.response?.statusCode == 404
            ? 'Ce rayon n\'existe plus.'
            : 'Impossible de charger les produits du rayon.',
      );
    } catch (_) {
      return ProductResult.failure('Impossible de charger les produits du rayon.');
    }
  }

  /// Premier rayon actif d'un type donné ('flash', 'tendance', 'succes')
  /// avec ses produits — utilisé par la page d'accueil.
  /// Retourne rayon = null s'il n'existe pas.
  Future<({Map<String, dynamic>? rayon, List<Map<String, dynamic>> products})>
      getByType(String type,
          {int limit = 10, bool throwOnError = false}) async {
    try {
      final r = await _client.get(
        '/api/v1/vitrine/by-type/$type',
        queryParameters: {'limit': limit},
      );
      final body = r.data;
      if (body is! Map) {
        return (rayon: null, products: <Map<String, dynamic>>[]);
      }
      final rayon = body['rayon'];
      return (
        rayon: rayon is Map ? Map<String, dynamic>.from(rayon) : null,
        products: _normalizeList(body['products'] as List? ?? const []),
      );
    } catch (e) {
      // L'accueil veut savoir si le serveur est injoignable (pour afficher
      // l'écran d'erreur de connexion). Seule une absence de réponse
      // (pas de réseau, délai dépassé) remonte : une réponse d'erreur du
      // serveur (ex. 500) laisse simplement le bloc vide, sans bloquer
      // tout l'accueil.
      if (throwOnError && e is DioException && e.response == null) rethrow;
      return (rayon: null, products: <Map<String, dynamic>>[]);
    }
  }

  /// « Meilleures boutiques » choisies par l'admin, avec leurs produits :
  ///   GET /api/v1/vitrine/best-shops → [{ id, position,
  ///   vendor: { id, shopName, logoUrl, bannerUrl }, products: [...],
  ///   productCount }]
  /// Les produits sont normalisés comme ceux de GET /products. Ne lève
  /// JAMAIS d'exception : en cas d'échec ou de liste vide, retourne []
  /// (la section n'apparait alors pas sur l'accueil, sans message d'erreur).
  /// Une boutique sans identifiant vendeur ou sans produit est écartée.
  Future<List<Map<String, dynamic>>> getBestShops() async {
    try {
      final r = await _client.get('/api/v1/vitrine/best-shops');
      final body = r.data;
      final raw = body is List
          ? body
          : (body is Map && body['data'] is List
              ? body['data'] as List
              : const []);
      final shops = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final shop = Map<String, dynamic>.from(item);
        final vendorRaw = shop['vendor'];
        if (vendorRaw is! Map) continue;
        final vendor = Map<String, dynamic>.from(vendorRaw);
        if ((vendor['id'] ?? '').toString().trim().isEmpty) continue;
        final productsRaw = shop['products'];
        final products =
            _normalizeList(productsRaw is List ? productsRaw : const []);
        if (products.isEmpty) continue;
        shop['vendor'] = vendor;
        // 6 cartes au plus par boutique (le serveur en envoie déjà 6).
        shop['products'] = products.take(6).toList();
        shops.add(shop);
      }
      return shops;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static List<Map<String, dynamic>> _normalizeList(List raw) => raw
      .whereType<Map>()
      .map((e) => ProductService.normalizeProduct(Map<String, dynamic>.from(e)))
      .toList();
}
