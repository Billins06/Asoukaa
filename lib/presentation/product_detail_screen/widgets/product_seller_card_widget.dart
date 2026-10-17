import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../routes/app_routes.dart';
import '../../../utils/last_seen_format.dart';

class ProductSellerCardWidget extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductSellerCardWidget({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    // Présence réelle du vendeur : tant qu'elle n'est pas connue (chargement
    // ou échec), on n'affiche rien plutôt qu'un faux « Hors ligne ».
    final presenceKnown = product['shopPresenceKnown'] == true;
    final isOnline = presenceKnown && product['shopIsOnline'] == true;
    final lastSeenAt = product['shopLastSeenAt'] as String?;
    final shopRating = product['shopRating'] as double? ?? 4.5;
    final shopSales = product['shopSales'] as int? ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La boutique',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Shop logo with online indicator
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildShopLogo(product),
                  ),
                  if (presenceKnown)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF9E9E9E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['shop'] as String? ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$shopRating',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·  ${_formatSales(shopSales)} ventes',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                    if (presenceKnown) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF9E9E9E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              formatLastSeen(lastSeenAt, isOnline: isOnline),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: isOnline
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF9E9E9E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final sellerId = product['seller_id']?.toString() ?? '';
                    final vendorId = product['shopId']?.toString() ?? '';
                    if (sellerId.isEmpty || vendorId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vendeur introuvable pour ce produit',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pushNamed(
                      context,
                      AppRoutes.chat,
                      arguments: {
                        'seller_id': sellerId,
                        'vendor_id': vendorId,
                        'seller_name': product['shop'],
                        'seller_avatar': product['shopLogo'],
                        'product_id': product['id'],
                        'product_name': product['name'],
                        'product_price': product['price'],
                        'product_image': product['imageUrl'],
                      },
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Contacter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6210),
                    side: const BorderSide(
                      color: Color(0xFFFF6210),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.boutiqueVendeur,
                    arguments: {
                      // 'id' manquait ici : sans lui, BoutiqueVendeurScreen
                      // ne pouvait JAMAIS appeler le serveur pour les vraies
                      // infos boutique (ni produits, ni avis) — elle
                      // retombait systématiquement sur ces quelques champs.
                      'id': product['shopId'] ?? product['shop_id'],
                      'name': product['shop'],
                      'logo': product['shopLogo'],
                      'logoSemanticLabel': product['shopLogoSemanticLabel'],
                      'rating': product['shopRating'],
                      'salesCount': product['shopSales'],
                    },
                  ),
                  icon: const Icon(Icons.storefront_outlined, size: 16),
                  label: const Text('Boutique'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    side: const BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShopLogo(Map<String, dynamic> product) {
    final logo = (product['shopLogo'] as String? ?? '').trim();
    final shopName = (product['shop'] as String? ?? 'B');
    if (logo.isNotEmpty) {
      return CustomImageWidget(
        imageUrl: logo,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        semanticLabel: product['shopLogoSemanticLabel'] as String? ?? 'Logo de la boutique',
      );
    }
    return Container(
      width: 52,
      height: 52,
      color: const Color(0xFFFF6210),
      child: Center(
        child: Text(
          shopName.isNotEmpty ? shopName[0].toUpperCase() : 'B',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatSales(int sales) {
    if (sales >= 1000) {
      return '${(sales / 1000).toStringAsFixed(1)}k';
    }
    return sales.toString();
  }
}
