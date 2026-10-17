import 'package:dio/dio.dart';

import '../utils/lecture_json.dart';
import 'api_service.dart';

/// Valeurs EXACTES attendues par le serveur (enum CouponType du backend).
const String kCouponTypePourcentage = 'pourcentage';
const String kCouponTypePrixFixe = 'prix fixe';

/// État d'un coupon tel que le vendeur doit le voir.
enum CouponStatut { actif, desactive, expire, epuise }

/// Un coupon de la boutique du vendeur (GET /api/v1/coupons/vendor/me).
///
/// ⚠️ Le serveur renvoie les décimaux (`value`, `minOrderAmount`) et même
/// `maxUses` en TEXTE (« 20.00 ») : tout passe par les fonctions de
/// lecture_json.dart, jamais de cast direct.
class VendorCoupon {
  final String id;
  final String code;
  final String type;
  final double value;
  final double? minOrderAmount;
  final int? maxUses;
  final int usedCount;
  final DateTime? expiresAt;
  final bool isActive;
  final DateTime? createdAt;

  const VendorCoupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.minOrderAmount,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.isActive,
    required this.createdAt,
  });

  factory VendorCoupon.fromJson(Map<String, dynamic> j) {
    return VendorCoupon(
      id: '${j['id'] ?? ''}',
      code: '${j['code'] ?? ''}',
      type: '${j['type'] ?? ''}',
      value: lireDouble(j['value']),
      minOrderAmount: lireDoubleOuNull(j['minOrderAmount']),
      maxUses: lireIntOuNull(j['maxUses']),
      usedCount: lireInt(j['usedCount']),
      expiresAt: _lireDate(j['expiresAt']),
      isActive: j['isActive'] != false,
      createdAt: _lireDate(j['createdAt']),
    );
  }

  static DateTime? _lireDate(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse('$v');
    return d?.toLocal();
  }

  bool get estPourcentage =>
      type.trim().toLowerCase() == kCouponTypePourcentage;

  /// Désactivé > expiré > épuisé > actif (même logique que le serveur, qui
  /// refuse un coupon inactif, expiré ou dont usedCount >= maxUses).
  CouponStatut get statut {
    if (!isActive) return CouponStatut.desactive;
    final exp = expiresAt;
    if (exp != null && DateTime.now().isAfter(exp)) return CouponStatut.expire;
    final max = maxUses;
    if (max != null && usedCount >= max) return CouponStatut.epuise;
    return CouponStatut.actif;
  }

  VendorCoupon copyWith({bool? isActive}) {
    return VendorCoupon(
      id: id,
      code: code,
      type: type,
      value: value,
      minOrderAmount: minOrderAmount,
      maxUses: maxUses,
      usedCount: usedCount,
      expiresAt: expiresAt,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}

/// Une page de la liste paginée { data, total, page, limit, pages }.
class CouponPage {
  final List<VendorCoupon> items;
  final int page;
  final int pages;
  final int total;

  const CouponPage({
    required this.items,
    required this.page,
    required this.pages,
    required this.total,
  });
}

/// Résultat d'un appel : soit `error` (message en français, prêt à afficher),
/// soit un succès (`data` peut rester null si le serveur ne renvoie rien).
class CouponResult<T> {
  final T? data;
  final String? error;

  const CouponResult._(this.data, this.error);

  factory CouponResult.success([T? data]) => CouponResult._(data, null);
  factory CouponResult.failure(String error) => CouponResult._(null, error);

  bool get ok => error == null;
}

/// Coupons de la boutique du vendeur connecté.
///
/// Routes serveur (module backend `coupons`) :
///   POST  /api/v1/coupons/vendor                 → crée un coupon
///   GET   /api/v1/coupons/vendor/me?page=&limit= → mes coupons (paginé)
///   PATCH /api/v1/coupons/vendor/:id/deactivate  → désactive un coupon
/// Le serveur impose lui-même la boutique du vendeur : l'appli n'envoie
/// JAMAIS de `vendorId` (le serveur le refuserait).
class CouponService {
  static CouponService? _instance;
  static CouponService get instance => _instance ??= CouponService._();
  CouponService._();

  Dio get _client => ApiService.instance.client;

  Future<CouponResult<CouponPage>> getMesCoupons({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final r = await _client.get(
        '/api/v1/coupons/vendor/me',
        queryParameters: {'page': page, 'limit': limit},
      );
      final body = r.data;
      if (body is! Map) {
        return CouponResult.failure('Réponse inattendue du serveur.');
      }
      final brut = body['data'];
      final items = <VendorCoupon>[];
      if (brut is List) {
        for (final e in brut) {
          if (e is Map) {
            final c = VendorCoupon.fromJson(Map<String, dynamic>.from(e));
            if (c.id.isNotEmpty) items.add(c);
          }
        }
      }
      return CouponResult.success(
        CouponPage(
          items: items,
          page: lireInt(body['page'], page),
          pages: lireInt(body['pages'], 1),
          total: lireInt(body['total'], items.length),
        ),
      );
    } catch (e) {
      return CouponResult.failure(
        _message(e, 'Impossible de charger vos coupons pour le moment.'),
      );
    }
  }

  Future<CouponResult<VendorCoupon>> creer({
    required String code,
    required String type,
    required double value,
    double? minOrderAmount,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    final corps = <String, dynamic>{
      'code': code.trim(),
      'type': type,
      'value': value,
    };
    if (minOrderAmount != null) corps['minOrderAmount'] = minOrderAmount;
    if (maxUses != null) corps['maxUses'] = maxUses;
    if (expiresAt != null) {
      corps['expiresAt'] = expiresAt.toUtc().toIso8601String();
    }
    try {
      final r = await _client.post('/api/v1/coupons/vendor', data: corps);
      final body = r.data;
      if (body is Map) {
        final c = VendorCoupon.fromJson(Map<String, dynamic>.from(body));
        return CouponResult.success(c.id.isNotEmpty ? c : null);
      }
      return CouponResult.success();
    } catch (e) {
      return CouponResult.failure(
        _message(e, 'Impossible de créer le coupon pour le moment.'),
      );
    }
  }

  /// Désactive un coupon. En cas de succès, `data` = message du serveur.
  Future<CouponResult<String>> desactiver(String id) async {
    try {
      final r = await _client.patch('/api/v1/coupons/vendor/$id/deactivate');
      final body = r.data;
      final msg = body is Map ? body['message'] : null;
      return CouponResult.success(
        msg is String && msg.trim().isNotEmpty
            ? msg.trim()
            : 'Coupon désactivé avec succès',
      );
    } catch (e) {
      return CouponResult.failure(
        _message(e, 'Impossible de désactiver le coupon pour le moment.'),
      );
    }
  }

  /// Message d'erreur affichable : celui du serveur tel quel (déjà en
  /// français : « code déjà utilisé », « boutique non active »...), sinon un
  /// texte générique.
  static String _message(Object e, String repli) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 429) {
        return 'Trop de tentatives. Patientez une minute puis réessayez.';
      }
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
        if (msg is List && msg.isNotEmpty) {
          return msg.map((m) => '$m').join('\n');
        }
      }
      if (e.response == null) {
        return 'Impossible de joindre le serveur. Vérifiez votre connexion internet.';
      }
    }
    return repli;
  }
}
