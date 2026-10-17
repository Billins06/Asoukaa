import 'package:dio/dio.dart';

import 'api_service.dart';

/// Une page de l'annuaire des boutiques.
class ShopsPage {
  final List<Map<String, dynamic>> shops;
  final int total;
  final int page;
  final bool hasMore;

  const ShopsPage({
    required this.shops,
    required this.total,
    required this.page,
    required this.hasMore,
  });
}

/// Annuaire public des boutiques (vendeurs) — écran « Boutiques » et
/// onglet « Boutiques » de la page des produits d'une catégorie.
///
/// Route serveur (authentifiée, jeton ajouté par l'intercepteur) :
///   GET /api/v1/vendors/directory
///       ?search=&filter=all|verified|new&categoryId=&page=1&limit=20
///   → { data: [ { id, shopName, logoUrl, zone, isVerified, rating,
///                 reviewCount, createdAt, isFollowing,
///                 previewProducts: [ { id, name, imageUrl } ] } ],
///       meta: { total, page, limit, totalPages } }
///
/// Suivre / ne plus suivre : POST / DELETE /api/v1/vendors/:id/follow
/// (mêmes routes que la page boutique et « Boutiques suivies »).
class ShopsService {
  static ShopsService? _instance;
  static ShopsService get instance => _instance ??= ShopsService._();
  ShopsService._();

  Dio get _client => ApiService.instance.client;

  /// Lève une exception (DioException...) en cas d'échec : l'appelant
  /// affiche l'erreur et le bouton « Réessayer ».
  Future<ShopsPage> getDirectory({
    String search = '',
    String filter = 'all',
    String? categoryId,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'filter': filter,
      'page': page,
      'limit': limit,
    };
    final q = search.trim();
    if (q.isNotEmpty) params['search'] = q;
    if (categoryId != null && categoryId.isNotEmpty) {
      params['categoryId'] = categoryId;
    }

    final r = await _client.get(
      '/api/v1/vendors/directory',
      queryParameters: params,
    );
    final body = r.data;
    final List raw = body is List
        ? body
        : (body is Map ? (body['data'] as List? ?? const []) : const []);
    final shops = raw
        .whereType<Map>()
        .map((e) => normalizeShop(Map<String, dynamic>.from(e)))
        .where((s) => (s['id'] as String).isNotEmpty)
        .toList();

    final meta = body is Map && body['meta'] is Map
        ? Map<String, dynamic>.from(body['meta'] as Map)
        : const <String, dynamic>{};
    final total = int.tryParse(meta['total']?.toString() ?? '') ?? shops.length;
    final currentPage = int.tryParse(meta['page']?.toString() ?? '') ?? page;
    final totalPages = int.tryParse(meta['totalPages']?.toString() ?? '');
    final hasMore = totalPages != null
        ? currentPage < totalPages
        : raw.length >= limit;

    return ShopsPage(
      shops: shops,
      total: total,
      page: currentPage,
      hasMore: hasMore,
    );
  }

  /// Suivre (follow = true) ou ne plus suivre une boutique.
  /// Renvoie l'état final confirmé par le serveur. Lève en cas d'échec.
  Future<bool> setFollowing(String vendorId, bool follow) async {
    final path = '/api/v1/vendors/$vendorId/follow';
    final r = follow ? await _client.post(path) : await _client.delete(path);
    final data = r.data;
    if (data is Map && data['following'] is bool) {
      return data['following'] as bool;
    }
    return follow;
  }

  /// Message lisible tiré d'une erreur serveur, sinon [fallback].
  static String errorMessage(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    }
    return fallback;
  }

  static bool isUnauthorized(Object e) =>
      e is DioException && e.response?.statusCode == 401;

  /// Normalisation tolérante (champs manquants, types inattendus).
  static Map<String, dynamic> normalizeShop(Map<String, dynamic> s) {
    String? cleanString(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty || t == 'null' ? null : t;
    }

    final name = cleanString(s['shopName']) ?? cleanString(s['name']) ?? 'Boutique';
    final logo = cleanString(s['logoUrl']) ?? cleanString(s['logo_url']);
    final previewsRaw = s['previewProducts'];
    final previews = <Map<String, dynamic>>[];
    if (previewsRaw is List) {
      for (final p in previewsRaw) {
        if (p is! Map) continue;
        final id = cleanString(p['id']);
        if (id == null) continue;
        previews.add({
          'id': id,
          'name': cleanString(p['name']) ?? '',
          'imageUrl': cleanString(p['imageUrl']) ?? '',
        });
      }
    }

    return {
      'id': cleanString(s['id']) ?? '',
      'shopName': name,
      'logoUrl': logo,
      'zone': cleanString(s['zone']) ??
          cleanString(s['shopAddress']) ??
          cleanString(s['city']),
      'isVerified': s['isVerified'] == true || s['status'] == 'approuvé',
      'rating': double.tryParse(s['rating']?.toString() ?? ''),
      'reviewCount': int.tryParse(s['reviewCount']?.toString() ?? '') ?? 0,
      'createdAt': cleanString(s['createdAt']),
      'isFollowing': s['isFollowing'] == true,
      'previewProducts': previews,
    };
  }
}
