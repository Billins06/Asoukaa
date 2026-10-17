import 'api_service.dart';

/// Frais de livraison par commune (77 communes du Bénin), configurés côté
/// admin via /api/v1/delivery-zones. Mis en cache en mémoire quelques
/// minutes seulement (voir _cacheTtl) : assez pour éviter de re-interroger
/// le serveur en boucle, assez court pour reprendre rapidement un prix
/// modifié depuis le dashboard admin.
class DeliveryZoneService {
  static DeliveryZoneService? _instance;
  static DeliveryZoneService get instance =>
      _instance ??= DeliveryZoneService._();
  DeliveryZoneService._();

  List<Map<String, dynamic>>? _cache;
  DateTime? _cachedAt;

  // Durée de vie du cache : assez courte pour qu'un changement de prix fait
  // par l'admin (dashboard "Livraison par commune") soit repris par l'appli
  // sans que le client ait besoin de la fermer/rouvrir completement, mais
  // assez longue pour ne pas re-interroger le serveur a chaque frappe dans
  // le champ commune du panier/paiement.
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Retourne la liste des zones ({id, commune, departement,
  /// fraisLivraison, isActive}). Utilise le cache sauf si [forceRefresh] ou
  /// si le cache a depasse [_cacheTtl].
  /// Retourne une liste vide en cas d'erreur réseau (les écrans doivent
  /// alors se rabattre sur un simple champ texte libre).
  Future<List<Map<String, dynamic>>> getZones({
    bool forceRefresh = false,
  }) async {
    final isFresh = _cache != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl;
    if (isFresh && !forceRefresh) return _cache!;
    try {
      final r = await ApiService.instance.client.get('/api/v1/delivery-zones');
      final raw = r.data;
      final list = raw is List ? raw : <dynamic>[];
      _cache = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _cachedAt = DateTime.now();
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

  // Départements du Nord du Bénin : aucun livreur Asoukaa n'y opère, la
  // livraison se fait par bus ou taxi inter-urbain (choix laissé au client
  // au paiement, voir CheckoutScreen). Doit rester cohérent avec le
  // regroupement appliqué côté admin sur /api/v1/delivery-zones.
  static const Set<String> _nordDepartements = {
    'Alibori',
    'Atacora',
    'Borgou',
    'Donga',
  };

  /// true si la commune appartient à un département du Nord (voir
  /// _nordDepartements) — déclenche le choix "Bus / Taxi" au paiement.
  /// false si la commune est inconnue ou hors zone Nord.
  Future<bool> isNordCommune(String? commune) async {
    if (commune == null || commune.trim().isEmpty) return false;
    final zones = await getZones();
    final target = commune.trim().toLowerCase();
    for (final z in zones) {
      final name = (z['commune'] as String? ?? '').trim().toLowerCase();
      if (name == target) {
        final dep = z['departement'] as String? ?? '';
        return _nordDepartements.contains(dep);
      }
    }
    return false;
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
