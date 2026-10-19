import 'package:dio/dio.dart';

import '../utils/lecture_json.dart';
import 'api_service.dart';

/// Bannières défilantes de l'accueil, gérées par l'admin (dashboard).
///
/// Route serveur (module backend `banners`, publique) :
///   GET /api/v1/banners → [ { id, imageUrl, titre, sousTitre,
///     durationSeconds, target: { type, id, url, label, logoUrl } } ]
/// Le serveur n'envoie que les bannières visibles maintenant (actives, dans
/// leur période, cible encore valide), déjà dans l'ordre voulu.
class BannerService {
  static BannerService? _instance;
  static BannerService get instance => _instance ??= BannerService._();
  BannerService._();

  Dio get _client => ApiService.instance.client;

  /// Durée d'affichage de repli et bornes (identiques au serveur).
  static const int defaultSeconds = 4;
  static const int minSeconds = 2;
  static const int maxSeconds = 30;

  /// Bannières normalisées : { id, imageUrl, titre, sousTitre,
  /// durationSeconds (int), targetType, targetId, targetUrl, targetLabel,
  /// targetLogo }. Liste vide en cas d'erreur (la zone disparaît alors).
  Future<List<Map<String, dynamic>>> getBanners() async {
    try {
      final r = await _client.get('/api/v1/banners');
      final body = r.data;
      if (body is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final raw in body) {
        if (raw is! Map) continue;
        final imageUrl = (raw['imageUrl'] ?? '').toString().trim();
        if (imageUrl.isEmpty) continue;
        final target = raw['target'] is Map
            ? Map<String, dynamic>.from(raw['target'] as Map)
            : const <String, dynamic>{};
        final titre = (raw['titre'] ?? '').toString().trim();
        final sousTitre = (raw['sousTitre'] ?? '').toString().trim();
        out.add({
          'id': (raw['id'] ?? '').toString(),
          'imageUrl': imageUrl,
          'titre': titre,
          'sousTitre': sousTitre,
          'durationSeconds': lireInt(raw['durationSeconds'], defaultSeconds)
              .clamp(minSeconds, maxSeconds)
              .toInt(),
          'targetType': (target['type'] ?? '').toString(),
          'targetId': (target['id'] ?? '').toString(),
          'targetUrl': (target['url'] ?? '').toString(),
          'targetLabel': (target['label'] ?? '').toString(),
          'targetLogo': (target['logoUrl'] ?? '').toString(),
        });
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
