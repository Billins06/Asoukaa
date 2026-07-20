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
  }) async {
    try {
      final params = <String, dynamic>{'limit': limit, 'page': page};
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

    // Image : variants[0].imageUrl > images[0] > vide
    final imagesList = raw['images'] as List? ?? [];
    String imageUrl = '';
    if (firstVariant != null && firstVariant['imageUrl'] != null) {
      imageUrl = firstVariant['imageUrl'].toString();
    } else if (imagesList.isNotEmpty) {
      final first = imagesList.first;
      imageUrl = first is Map
          ? (first['url'] ?? first['imageUrl'] ?? '').toString()
          : first.toString();
    }

    return {
      ...raw,
      'name': raw['prod_name'] ?? raw['name'] ?? raw['title'] ?? '',
      'price': price,
      'image_url': imageUrl,
      'images': imageUrl.isNotEmpty ? [imageUrl] : imagesList,
      'sold_count': raw['totalVentes'] ?? raw['sold_count'] ?? 0,
      'rating': double.tryParse(raw['noteMoyenne']?.toString() ?? '0') ?? 0,
      'reviews_count': raw['nbreAvis'] ?? raw['reviews_count'] ?? 0,
      'variantId': firstVariant?['id'],
      'stock': firstVariant?['stockQuantity'] ?? raw['stock'] ?? 0,
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
