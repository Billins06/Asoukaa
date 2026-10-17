import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/price_range.dart';
import 'product_fields.dart';

/// Hauteur de la zone texte sous la photo d'une [CatalogProductCard].
/// La grille utilise une hauteur fixe : photo + cette valeur. La hauteur
/// totale de la carte suit le réglage commun kProductGridRatio (voir
/// lib/utils/grille_produits.dart) pour avoir la même taille que les
/// cartes de l'accueil et de la recherche.
const double kCatalogCardInfoHeight = 136;

/// Carte produit de la page G (grille 2 colonnes bord à bord) :
/// photo, badge « Boutique vérifiée » (si l'info existe), nom,
/// prix en fourchette, quantité minimale (si connue), boutique · ville et
/// bouton « ajouter au panier » 36 px.
class CatalogProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final double imageSize;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const CatalogProductCard({
    super.key,
    required this.product,
    required this.imageSize,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final vendor = productVendor(product);
    final verified = shopIsVerified(vendor) == true;
    final name = productNameOf(product);
    final minQty = productMinQuantity(product);
    final shopLine = [shopNameOf(vendor), shopLocationOf(vendor)]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    // Texte agrandi au maximum de 15 % : la zone texte a une hauteur fixe,
    // au-delà elle déborderait.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProductPhoto(
              url: productImageOf(product),
              width: double.infinity,
              height: imageSize,
              semanticLabel: name,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (verified) ...[
                      const VerifiedShopBadge(),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        // « 25 – 39 FCFA » si un palier dégressif existe,
                        // sinon le prix normal seul.
                        priceRangeLabel(product),
                        maxLines: 1,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (minQty != null)
                      Text(
                        'Quantité min. : $minQty pièces',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          color: const Color(0xFF5C5651),
                          height: 1.3,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            shopLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              color: const Color(0xFF8A827B),
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Semantics(
                          button: true,
                          label: 'Ajouter $name au panier',
                          child: Material(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: onAddToCart,
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  Icons.add_shopping_cart_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Badge « Boutique vérifiée » (fond #FFEDE3, texte orange).
class VerifiedShopBadge extends StatelessWidget {
  const VerifiedShopBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 12, color: AppTheme.primary),
          const SizedBox(width: 3),
          Text(
            'Boutique vérifiée',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
