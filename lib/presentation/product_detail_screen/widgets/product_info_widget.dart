import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/status_badge_widget.dart';

class ProductInfoWidget extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductInfoWidget({super.key, required this.product});

  String _formatPrice(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final discount = product['discount'] as int? ?? 0;
    final stockLeft = product['stockLeft'] as int? ?? 0;
    final soldCount =
        (product['sold_count'] as num?)?.toInt() ??
        (product['soldCount'] as int?) ??
        0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category + Location row
          Row(
            children: [
              StatusBadgeWidget.custom(
                label: product['category'] as String? ?? 'Général',
                backgroundColor: const Color(0xFFFFEDE3),
                textColor: const Color(0xFFFF6210),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.location_on_outlined,
                size: 12,
                color: Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  product['location'] as String? ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9E9E9E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Product name
          Text(
            product['name'] as String? ?? '',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          // Rating row
          Row(
            children: [
              ...List.generate(5, (i) {
                final rating = (product['rating'] as double? ?? 0);
                return Icon(
                  i < rating.floor()
                      ? Icons.star_rounded
                      : (i < rating
                            ? Icons.star_half_rounded
                            : Icons.star_outline_rounded),
                  size: 16,
                  color: const Color(0xFFD97706),
                );
              }),
              const SizedBox(width: 6),
              Text(
                (product['rating'] as num? ?? 0.0).toStringAsFixed(1),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${product['reviewCount'] ?? product['reviews_count'] ?? 0} avis)',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
              const Spacer(),
              if (stockLeft > 0 && stockLeft <= 10)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⚠ Plus que $stockLeft en stock',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
            ],
          ),
          // Sold count badge
          if (soldCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF10B981).withAlpha(60),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 14,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$soldCount vendus à Cotonou',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Price row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (product['isDigital'] == true &&
                        ((product['price'] as num?)?.toInt() ?? 0) <= 0)
                    ? 'Gratuit'
                    : '${_formatPrice((product['price'] as num?)?.toInt() ?? 0)} FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6210),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (discount > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${_formatPrice(product['originalPrice'] as int? ?? 0)} FCFA',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9E9E9E),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '-$discount%',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Description — affichée directement sur la fiche produit (pas
          // seulement dans l'onglet "Description" plus bas, pour qu'elle
          // soit visible sans avoir à chercher).
          if ((product['description'] as String? ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 16),
            Text(
              'Description',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (product['description'] as String).trim(),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF616161),
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
