import 'package:dio/dio.dart';
import 'api_service.dart';

class LibraryResult<T> {
  final bool success;
  final String? error;
  final T? data;

  const LibraryResult._({required this.success, this.error, this.data});

  factory LibraryResult.success([T? data]) =>
      LibraryResult._(success: true, data: data);

  factory LibraryResult.failure(String error) =>
      LibraryResult._(success: false, error: error);
}

/// Ma Bibliothèque : livres numériques (PDF) achetés par le client.
class LibraryService {
  static LibraryService? _instance;
  static LibraryService get instance => _instance ??= LibraryService._();
  LibraryService._();

  Dio get _client => ApiService.instance.client;

  /// GET /library → liste des livres possédés (titre, auteur, couverture…).
  Future<LibraryResult<List<Map<String, dynamic>>>> getMyBooks() async {
    try {
      final response = await _client.get('/api/v1/library');
      final body = response.data;
      final raw = body is List
          ? body
          : (body is Map ? (body['data'] ?? body['items'] ?? []) as List : []);
      final books = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return LibraryResult.success(books);
    } on DioException catch (e) {
      return LibraryResult.failure(_extractError(e));
    } catch (_) {
      return LibraryResult.failure('Impossible de charger votre Bibliothèque.');
    }
  }

  /// GET /library/:productId/download → lien court (2 minutes) à ouvrir tout de suite.
  Future<LibraryResult<String>> getDownloadUrl(String productId) async {
    try {
      final response = await _client.get('/api/v1/library/$productId/download');
      final data = response.data;
      final url = data is Map ? (data['url'] ?? '').toString() : '';
      if (url.isEmpty) {
        return LibraryResult.failure('Lien de téléchargement indisponible.');
      }
      return LibraryResult.success(url);
    } on DioException catch (e) {
      return LibraryResult.failure(_extractError(e));
    } catch (_) {
      return LibraryResult.failure('Téléchargement impossible pour le moment.');
    }
  }

  /// POST /payments/free → valide les commandes de livres à 0 F (aucun paiement).
  Future<LibraryResult<void>> claimFreeOrders(List<String> orderIds) async {
    try {
      await _client.post('/api/v1/payments/free', data: {'orderIds': orderIds});
      return LibraryResult.success();
    } on DioException catch (e) {
      return LibraryResult.failure(_extractError(e));
    } catch (_) {
      return LibraryResult.failure("Impossible d'ajouter ces livres gratuits.");
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
        if (e.response?.statusCode == 401) {
          return 'Session expirée. Reconnectez-vous.';
        }
        return 'Erreur serveur. Veuillez réessayer.';
    }
  }
}
