import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _showShareSheet(BuildContext context) {
    final productName = product['name'] as String? ?? 'Produit';
    final price = product['price'] as int? ?? 0;
    final productId = product['id'] as String? ?? '';
    final shareUrl =
        'https://asoukaa3389.builtwithrocket.new/product/$productId';
    final shareText =
        '🛍 $productName — ${_formatPrice(price)} FCFA\n\nDécouvrez ce produit sur Asoukaa !\n$shareUrl';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ShareSheet(
        shareText: shareText,
        shareUrl: shareUrl,
        productName: productName,
      ),
    );
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
              // Share button
              GestureDetector(
                onTap: () => _showShareSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDE3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.share_rounded,
                        size: 14,
                        color: Color(0xFFFF6210),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Partager',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF6210),
                        ),
                      ),
                    ],
                  ),
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
                '${_formatPrice((product['price'] as num?)?.toInt() ?? 0)} FCFA',
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
        ],
      ),
    );
  }
}

// ─── Share Sheet ─────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String shareText;
  final String shareUrl;
  final String productName;

  const _ShareSheet({
    required this.shareText,
    required this.shareUrl,
    required this.productName,
  });

  @override
  Widget build(BuildContext context) {
    final networks = [
      _ShareNetwork(
        name: 'WhatsApp',
        icon: Icons.chat_rounded,
        color: const Color(0xFF25D366),
        url: 'https://wa.me/?text=${Uri.encodeComponent(shareText)}',
      ),
      _ShareNetwork(
        name: 'Facebook',
        icon: Icons.facebook_rounded,
        color: const Color(0xFF1877F2),
        url:
            'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(shareUrl)}',
      ),
      _ShareNetwork(
        name: 'Messenger',
        icon: Icons.messenger_rounded,
        color: const Color(0xFF0084FF),
        url:
            'https://www.facebook.com/dialog/send?link=${Uri.encodeComponent(shareUrl)}',
      ),
      _ShareNetwork(
        name: 'Telegram',
        icon: Icons.telegram_rounded,
        color: const Color(0xFF2AABEE),
        url:
            'https://t.me/share/url?url=${Uri.encodeComponent(shareUrl)}&text=${Uri.encodeComponent(productName)}',
      ),
      _ShareNetwork(
        name: 'Instagram',
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFFE1306C),
        url: shareUrl,
      ),
      _ShareNetwork(
        name: 'TikTok',
        icon: Icons.music_note_rounded,
        color: const Color(0xFF000000),
        url: shareUrl,
      ),
      _ShareNetwork(
        name: 'LinkedIn',
        icon: Icons.work_rounded,
        color: const Color(0xFF0A66C2),
        url:
            'https://www.linkedin.com/sharing/share-offsite/?url=${Uri.encodeComponent(shareUrl)}',
      ),
      _ShareNetwork(
        name: 'Copier lien',
        icon: Icons.link_rounded,
        color: const Color(0xFF6B7280),
        url: shareUrl,
        isCopy: true,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Partager ce produit',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            productName,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: const Color(0xFF9E9E9E),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.85,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: networks.length,
            itemBuilder: (_, i) {
              final n = networks[i];
              return GestureDetector(
                onTap: () {
                  if (n.isCopy) {
                    Clipboard.setData(ClipboardData(text: shareUrl));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Lien copié !',
                          style: GoogleFonts.outfit(color: Colors.white),
                        ),
                        backgroundColor: const Color(0xFF1A1A1A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Ouverture de ${n.name}...',
                          style: GoogleFonts.outfit(color: Colors.white),
                        ),
                        backgroundColor: n.color,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: n.color.withAlpha(20),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: n.color.withAlpha(60)),
                      ),
                      child: Icon(n.icon, color: n.color, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n.name,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF616161),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShareNetwork {
  final String name;
  final IconData icon;
  final Color color;
  final String url;
  final bool isCopy;
  const _ShareNetwork({
    required this.name,
    required this.icon,
    required this.color,
    required this.url,
    this.isCopy = false,
  });
}
