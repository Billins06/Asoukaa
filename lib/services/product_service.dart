import 'package:dio/dio.dart';
import 'api_service.dart';

class ProductResult<T> {
  final bool success;
  final String? error;
  final T? data;

  const ProductResult._({required this.success, this.error, this.data});

  factory ProductResult.success([T? data]) =>
      ProductResult._(success: true, data: data);

  factory ProductResult.failure(String error) =>
      ProductResult._(success: false, error: error);
}

/// Une page de GET /products (défilement infini de l'accueil).
class ProductsPage {
  final List<Map<String, dynamic>> items;
  final int page;
  final int total;
  final bool hasMore;

  const ProductsPage({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
  });
}

class ProductService {
  static ProductService? _instance;
  static ProductService get instance => _instance ??= ProductService._();
  ProductService._();

  Dio get _client => ApiService.instance.client;

  Future<ProductResult<List<Map<String, dynamic>>>> getProducts({
    String? categoryId,
    String? search,
    int limit = 20,
    int page = 1,
    bool isFeatured = false,
    bool onlyDigital = false,
  }) async {
    try {
      final params = <String, dynamic>{'limit': limit, 'page': page};
      if (onlyDigital) params['isDigital'] = 'true';
      if (categoryId != null && categoryId.isNotEmpty) {
        params['categoryId'] = categoryId;
      }
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (isFeatured) params['isFeatured'] = true;

      final response = await _client.get(
        '/api/v1/products',
        queryParameters: params,
      );

      List<dynamic> rawList;
      final body = response.data;
      if (body is List) {
        rawList = body;
      } else if (body is Map && body.containsKey('data')) {
        rawList = body['data'] as List<dynamic>? ?? [];
      } else {
        rawList = [];
      }

      final products = rawList
          .whereType<Map>()
          .map((e) => _normalize(Map<String, dynamic>.from(e)))
          .toList();

      return ProductResult.success(products);
    } on DioException catch (e) {
      return ProductResult.failure(_extractError(e));
    } catch (_) {
      return ProductResult.failure('Erreur lors du chargement des produits.');
    }
  }

  Future<ProductResult<Map<String, dynamic>>> getProductById(
    String productId,
  ) async {
    try {
      final response = await _client.get('/api/v1/products/$productId');
      return ProductResult.success(
        _normalize(Map<String, dynamic>.from(response.data as Map)),
      );
    } on DioException catch (e) {
      return ProductResult.failure(_extractError(e));
    } catch (_) {
      return ProductResult.failure('Produit introuvable.');
    }
  }

  /// Une page de produits pour le défilement infini de l'accueil
  /// (GET /products?page=N&limit=20 → { data, total, page, limit, pages,
  /// hasMore }). Les produits sont normalisés comme ceux de getProducts().
  Future<ProductResult<ProductsPage>> getProductsPage({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _client.get(
        '/api/v1/products',
        queryParameters: <String, dynamic>{'page': page, 'limit': limit},
      );

      final body = response.data;
      List<dynamic> rawList = const [];
      var total = 0;
      var hasMore = false;
      if (body is List) {
        rawList = body;
        hasMore = rawList.length >= limit;
      } else if (body is Map) {
        final data = body['data'];
        if (data is List) rawList = data;
        total = int.tryParse('${body['total'] ?? ''}') ?? 0;
        final more = body['hasMore'];
        hasMore = more is bool ? more : rawList.length >= limit;
      }
      // Une page vide met fin au défilement, quoi que dise le serveur
      // (évite de redemander indéfiniment la même page vide).
      if (rawList.isEmpty) hasMore = false;

      final items = rawList
          .whereType<Map>()
          .map((e) => _normalize(Map<String, dynamic>.from(e)))
          .toList();

      return ProductResult.success(
        ProductsPage(
          items: items,
          page: page,
          total: total,
          hasMore: hasMore,
        ),
      );
    } on DioException catch (e) {
      return ProductResult.failure(_extractError(e));
    } catch (_) {
      return ProductResult.failure('Erreur lors du chargement des produits.');
    }
  }

  /// Version publique de la normalisation, pour les autres services
  /// (Vitrine, boutiques) qui reçoivent des produits du serveur.
  static Map<String, dynamic> normalizeProduct(Map<String, dynamic> raw) =>
      _normalize(raw);

  static Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    final variants = raw['variants'] as List? ?? [];
    final firstVariant = variants.isNotEmpty ? (variants.first as Map?) : null;

    // Prix : basePrice au niveau produit, sinon variants[0].price
    double price = 0;
    final rawPrice = raw['basePrice'] ?? raw['price'];
    if (rawPrice != null) {
      price = double.tryParse(rawPrice.toString()) ?? 0;
    } else if (firstVariant != null) {
      price = double.tryParse(firstVariant['price']?.toString() ?? '0') ?? 0;
    }

    // Galerie : toutes les images du produit (les vidéos, isVideo: true,
    // sont exclues), image principale d'abord puis sortOrder.
    // ⚠️ Avant : 'images' était remplacé par [imageUrl] dès qu'une image
    // existait → la fiche produit n'affichait qu'UNE photo même quand le
    // vendeur en avait publié 5 (GET /products/:id les renvoie toutes).
    final imagesList = raw['images'] as List? ?? [];
    int byPrimaryThenOrder(dynamic a, dynamic b) {
      final aPrimary = a is Map && a['isPrimary'] == true ? 0 : 1;
      final bPrimary = b is Map && b['isPrimary'] == true ? 0 : 1;
      if (aPrimary != bPrimary) return aPrimary - bPrimary;
      final aOrder = a is Map ? (a['sortOrder'] as num? ?? 0) : 0;
      final bOrder = b is Map ? (b['sortOrder'] as num? ?? 0) : 0;
      return aOrder.compareTo(bOrder);
    }

    List<String> urlsOf(List<dynamic> entries) {
      final urls = <String>[];
      for (final e in entries) {
        final url = (e is Map ? (e['url'] ?? e['imageUrl'] ?? '') : e)
            .toString()
            .trim();
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
      return urls;
    }

    final photoEntries = imagesList
        .where((e) => !(e is Map && e['isVideo'] == true))
        .toList()
      ..sort(byPrimaryThenOrder);
    final galleryUrls = urlsOf(photoEntries);

    // Vidéos du produit (isVideo: true), même ordre que les photos. Liste
    // séparée : 'images' reste une liste de photos pour les cartes produit,
    // seule la galerie de la fiche produit lit 'videos'.
    final videoEntries = imagesList
        .where((e) => e is Map && e['isVideo'] == true)
        .toList()
      ..sort(byPrimaryThenOrder);
    final videoUrls = urlsOf(videoEntries);

    // Image principale (cartes produit) : variants[0].imageUrl > images[0] > vide
    String imageUrl = '';
    if (firstVariant != null && firstVariant['imageUrl'] != null) {
      imageUrl = firstVariant['imageUrl'].toString();
    } else if (galleryUrls.isNotEmpty) {
      imageUrl = galleryUrls.first;
    }
    // L'image de la variante reste en tête de galerie si elle n'y est pas déjà
    if (imageUrl.isNotEmpty && !galleryUrls.contains(imageUrl)) {
      galleryUrls.insert(0, imageUrl);
    }

    return {
      ...raw,
      'name': raw['prod_name'] ?? raw['name'] ?? raw['title'] ?? '',
      'price': price,
      'image_url': imageUrl,
      // Liste d'URL (String) : les écrans lisent images.first comme String
      // ou Map, les deux formats restent supportés partout.
      'images': galleryUrls,
      // Liste d'URL (String) des vidéos du produit, affichées après les
      // photos dans la galerie de la fiche produit.
      'videos': videoUrls,
      'sold_count': raw['totalVentes'] ?? raw['sold_count'] ?? 0,
      'rating': double.tryParse(raw['noteMoyenne']?.toString() ?? '0') ?? 0,
      'reviews_count': raw['nbreAvis'] ?? raw['reviews_count'] ?? 0,
      // Livre numérique (PDF) : pas de stock, pas de livraison.
      'isDigital': raw['isDigital'] == true,
      'variantId': firstVariant?['id'],
      'stock': raw['isDigital'] == true
          ? 1
          : (firstVariant?['stockQuantity'] ?? raw['stock'] ?? 0),
    };
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Délai dépassé. Vérifiez votre connexion.';
      case DioExceptionType.connectionError:
        return 'Impossible de joindre le serveur.';
      default:
        final status = e.response?.statusCode;
        if (status == 401) return 'Session expirée. Reconnectez-vous.';
        return 'Erreur serveur. Veuillez réessayer.';
    }
  }
}
