import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';
import './home_image_circle.dart';
import './home_product_card.dart';

/// Un bloc « Meilleures boutiques » : une ligne (logo rond, nom,
/// « Voir la boutique ») puis une rangée horizontale défilante des
/// produits de la boutique.
///
/// [shop] est un élément de VitrineService.getBestShops() :
/// { id, position, vendor: { id, shopName, logoUrl, bannerUrl },
///   products: [...], productCount }.
class HomeBestShopRow extends StatelessWidget {
  final Map<String, dynamic> shop;
  final void Function(Map<String, dynamic>) onProductTap;
  final VoidCallback? onCartUpdated;

  const HomeBestShopRow({
    super.key,
    required this.shop,
    required this.onProductTap,
    this.onCartUpdated,
  });

  // Même proportion que les grilles de produits (kProductGridRatio) :
  // 160 / 0.72 = 222 de carte + 12 de marge verticale de la liste.
  static const double _cardWidth = 160;
  static const double _listHeight = 234;

  static String _text(dynamic v) => (v ?? '').toString().trim();

  void _openShop(BuildContext context, Map<String, dynamic> vendor) {
    final vendorId = _text(vendor['id']);
    if (vendorId.isEmpty) return;
    final name = _text(vendor['shopName']).isEmpty
        ? 'Boutique'
        : _text(vendor['shopName']);
    // Écran boutique existant : il lit 'id' (identifiant du VENDEUR) pour
    // charger /vendors/:id/public ; le reste sert de repli visuel.
    Navigator.pushNamed(
      context,
      AppRoutes.boutiqueVendeur,
      arguments: <String, dynamic>{
        'id': vendorId,
        'name': name,
        'logo': _text(vendor['logoUrl']),
        'banner': _text(vendor['bannerUrl']),
        'logoSemanticLabel': 'Logo de la boutique $name',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendorRaw = shop['vendor'];
    if (vendorRaw is! Map) return const SizedBox.shrink();
    final vendor = Map<String, dynamic>.from(vendorRaw);

    final productsRaw = shop['products'];
    final products = <Map<String, dynamic>>[
      if (productsRaw is List)
        for (final p in productsRaw)
          if (p is Map) Map<String, dynamic>.from(p),
    ];
    if (products.isEmpty) return const SizedBox.shrink();

    final shopName = _text(vendor['shopName']).isEmpty
        ? 'Boutique'
        : _text(vendor['shopName']);
    final count = int.tryParse(_text(shop['productCount'])) ?? products.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.only(top: 12, bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0ECE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openShop(context, vendor),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  HomeImageCircle(
                    imageUrl: _text(vendor['logoUrl']),
                    label: shopName,
                    size: 44,
                    withShadow: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          count > 1 ? '$count produits' : '$count produit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Voir la boutique',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFF6210),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFFFF6210),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _listHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              // Marge verticale : l'ombre des cartes n'est pas rognée.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final product = products[index];
                return SizedBox(
                  width: _cardWidth,
                  child: HomeProductCard(
                    key: ValueKey('shop-${shop['id']}-${product['id']}'),
                    product: product,
                    onTap: onProductTap,
                    onCartUpdated: onCartUpdated,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
