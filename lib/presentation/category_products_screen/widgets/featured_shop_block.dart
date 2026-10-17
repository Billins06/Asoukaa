import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/price_range.dart';
import '../../../widgets/custom_image_widget.dart';
import 'product_fields.dart';

/// Bloc « boutique à la une » en tête de l'onglet Produits de la page G :
/// logo, nom, « Vérifiée · ville » (si dispo), lien « Voir plus › » et
/// défilement horizontal de produits de cette boutique.
/// (Pas de bouton « Discuter » : retiré à la demande de l'utilisateur.)
class FeaturedShopBlock extends StatelessWidget {
  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> products;
  final VoidCallback onOpenShop;
  final ValueChanged<Map<String, dynamic>> onOpenProduct;

  const FeaturedShopBlock({
    super.key,
    required this.vendor,
    required this.products,
    required this.onOpenShop,
    required this.onOpenProduct,
  });

  @override
  Widget build(BuildContext context) {
    final name = shopNameOf(vendor).isEmpty ? 'Boutique' : shopNameOf(vendor);
    final logo = shopLogoOf(vendor);
    final verified = shopIsVerified(vendor) == true;
    final location = shopLocationOf(vendor);
    final initial = name.substring(0, 1).toUpperCase();

    final initialBox = Container(
      width: 44,
      height: 44,
      color: Colors.white,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppTheme.primary,
        ),
      ),
    );

    return Container(
      color: const Color(0xFFF5F2EF),
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenShop,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEFEAE4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: logo.isEmpty
                        ? initialBox
                        : CustomImageWidget(
                            imageUrl: logo,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            semanticLabel: 'Logo de la boutique $name',
                            errorWidget: initialBox,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (verified || location.isNotEmpty)
                          Row(
                            children: [
                              if (verified) ...[
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 13,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Vérifiée',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                              if (verified && location.isNotEmpty)
                                Text(
                                  ' · ',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: const Color(0xFF8A827B),
                                  ),
                                ),
                              if (location.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: const Color(0xFF8A827B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Voir plus ›',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _MiniProductCard(
                product: products[i],
                onTap: () => onOpenProduct(products[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _MiniProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = productNameOf(product);
    final minQty = productMinQuantity(product);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductPhoto(
              url: productImageOf(product),
              width: 110,
              height: 110,
              semanticLabel: name,
              radius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                height: 1.25,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                priceRangeLabel(product, rangeCurrency: 'F'),
                maxLines: 1,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
              ),
            ),
            if (minQty != null)
              Text(
                'Dès $minQty pièces',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: const Color(0xFF8A827B),
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
