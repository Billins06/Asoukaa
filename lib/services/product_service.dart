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
          .map((e) => Map<String, dynamic>.from(e))
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
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      return ProductResult.failure(_extractError(e));
    } catch (_) {
      return ProductResult.failure('Produit introuvable.');
    }
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
