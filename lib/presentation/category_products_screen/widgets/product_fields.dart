import 'package:flutter/material.dart';

import '../../../widgets/custom_image_widget.dart';

// Lecture tolérante des champs produit / boutique pour la page G.
//
// D'où viennent les données : GET /api/v1/products (et les produits des
// rayons de la Vitrine) renvoient chaque produit avec la relation
// `vendor` (VendorProfile côté backend : id, shopName, logoUrl, bannerUrl,
// shopAddress, status…). ProductService/VitrineService les normalisent
// (name, image_url, images, tierPrices…) sans toucher à `vendor`.
// Aucune valeur n'est inventée : une donnée absente => élément masqué.

/// URL d'image exploitable (http/https), sinon chaîne vide.
/// CustomImageWidget plante sur une chaîne vide (traitée comme un asset),
/// d'où ce filtre avant tout affichage.
String validImageUrl(dynamic raw) {
  final s = (raw ?? '').toString().trim();
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  return '';
}

/// Boutique (vendeur) du produit, quelle que soit la clé utilisée.
Map<String, dynamic>? productVendor(Map<dynamic, dynamic> p) {
  for (final key in const ['vendor', 'vendeur', 'shop', 'shops', 'shop_info']) {
    final v = p[key];
    if (v is Map) return Map<String, dynamic>.from(v);
  }
  return null;
}

/// Identifiant de la boutique (VendorProfile.id) — c'est cet id que
/// BoutiqueVendeurScreen attend sous la clé 'id'.
String productShopId(Map<dynamic, dynamic> p) {
  final v = productVendor(p);
  return (v?['id'] ?? p['vendorId'] ?? p['shopId'] ?? p['shop_id'] ?? '')
      .toString()
      .trim();
}

String shopNameOf(Map<String, dynamic>? v) =>
    (v?['shopName'] ?? v?['name'] ?? '').toString().trim();

String shopLogoOf(Map<String, dynamic>? v) =>
    validImageUrl(v?['logoUrl'] ?? v?['logo']);

/// Ville / adresse de la boutique. Le backend n'a pas de champ « ville »
/// dédié : on prend 'city'/'ville' s'ils existent, sinon 'shopAddress'.
String shopLocationOf(Map<String, dynamic>? v) {
  if (v == null) return '';
  for (final key in const ['city', 'ville', 'shopAddress', 'location']) {
    final s = (v[key] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// true / false si l'information existe, null si elle est inconnue.
/// Même règle que BoutiqueVendeurScreen : statut 'approuvé' = vérifiée.
bool? shopIsVerified(Map<String, dynamic>? v) {
  if (v == null) return null;
  final b = v['isVerified'] ?? v['is_verified'];
  if (b is bool) return b;
  // Pas de déduction depuis le statut « approuvé » : « vérifiée » suit la
  // règle de l'annuaire (pièce d'identité + selfie), calculée côté serveur.
  return null;
}

/// Quantité minimale de commande si le produit la fournit (> 1), sinon null.
/// ⚠️ Le backend actuel n'a pas ce champ : la ligne reste donc masquée tant
/// qu'il n'existe pas (aucune valeur inventée).
int? productMinQuantity(Map<dynamic, dynamic> p) {
  for (final key in const [
    'minOrderQuantity',
    'minOrder',
    'min_order',
    'minQuantity',
    'moq',
  ]) {
    final n = int.tryParse('${p[key] ?? ''}');
    if (n != null && n > 1) return n;
  }
  return null;
}

String productNameOf(Map<dynamic, dynamic> p) {
  final s = (p['name'] ?? p['prod_name'] ?? '').toString().trim();
  return s.isEmpty ? 'Produit' : s;
}

/// Image principale : image_url (normalisée) puis images[0].
String productImageOf(Map<dynamic, dynamic> p) {
  final direct = validImageUrl(p['image_url'] ?? p['imageUrl']);
  if (direct.isNotEmpty) return direct;
  final images = p['images'];
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    return validImageUrl(
      first is Map ? (first['url'] ?? first['imageUrl']) : first,
    );
  }
  return '';
}

/// Photo produit sur fond #F5F2EF, avec repli propre (icône) si l'URL est
/// vide ou cassée.
class ProductPhoto extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final String semanticLabel;
  final BorderRadius? radius;

  const ProductPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.semanticLabel = 'Produit',
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: Color(0xFFBDB5AD),
        ),
      ),
    );
    final Widget content = url.isEmpty
        ? placeholder
        : CustomImageWidget(
            imageUrl: url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            semanticLabel: semanticLabel,
            errorWidget: placeholder,
          );
    final box = Container(
      width: width,
      height: height,
      color: const Color(0xFFF5F2EF),
      child: content,
    );
    if (radius == null) return box;
    return ClipRRect(borderRadius: radius!, child: box);
  }
}
