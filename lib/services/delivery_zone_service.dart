import 'api_service.dart';

/// Frais de livraison par commune (77 communes du Bénin), configurés côté
/// admin via /api/v1/delivery-zones. Mis en cache en mémoire pour la durée
/// de la session de l'app (liste rarement modifiée en cours d'usage).
class DeliveryZoneService {
  static DeliveryZoneService? _instance;
  static DeliveryZoneService get instance =>
      _instance ??= DeliveryZoneService._();
  DeliveryZoneService._();

  List<Map<String, dynamic>>? _cache;

  /// Retourne la liste des zones ({id, commune, departement,
  /// fraisLivraison, isActive}). Utilise le cache sauf si [forceRefresh].
  /// Retourne une liste vide en cas d'erreur réseau (les écrans doivent
  /// alors se rabattre sur un simple champ texte libre).
  Future<List<Map<String, dynamic>>> getZones({
    bool forceRefresh = false,
  }) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final r = await ApiService.instance.client.get('/api/v1/delivery-zones');
      final raw = r.data;
      final list = raw is List ? raw : <dynamic>[];
      _cache = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return _cache!;
    } catch (_) {
      return [];
    }
  }

  /// Noms de communes actives, triés, pour un champ de sélection.
  Future<List<String>> communeNames() async {
    final zones = await getZones();
    final active = zones.where((z) => z['isActive'] != false).toList();
    final names = active.map((z) => z['commune'] as String? ?? '').where((s) => s.isNotEmpty).toList();
    names.sort();
    return names;
  }

  /// Frais de livraison pour une commune donnée (0 si commune inconnue ou
  /// zone désactivée — comportement identique au calcul serveur, qui reste
  /// dans tous les cas la source de vérité au moment de la commande).
  Future<num> feeForCommune(String? commune) async {
    if (commune == null || commune.trim().isEmpty) return 0;
    final zones = await getZones();
    final target = commune.trim().toLowerCase();
    for (final z in zones) {
      final name = (z['commune'] as String? ?? '').trim().toLowerCase();
      if (name == target && z['isActive'] != false) {
        final fee = z['fraisLivraison'];
        if (fee is num) return fee;
        return num.tryParse(fee?.toString() ?? '') ?? 0;
      }
    }
    return 0;
  }
}
