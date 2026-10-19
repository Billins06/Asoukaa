import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProductActionBarWidget extends StatefulWidget {
  final Map<String, dynamic> product;
  final int quantity;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;
  // Livre déjà acheté : le bouton ouvre la Bibliothèque.
  final VoidCallback? onOpenLibrary;
  final bool isInline;

  const ProductActionBarWidget({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAddToCart,
    required this.onBuyNow,
    this.onOpenLibrary,
    this.isInline = false,
  });

  @override
  State<ProductActionBarWidget> createState() => _ProductActionBarWidgetState();
}

class _ProductActionBarWidgetState extends State<ProductActionBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  String _formatPrice(int price) {
    final s = (price * widget.quantity).toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.product['price'] as int? ?? 0;
    final isDigital = widget.product['isDigital'] == true;
    final owned = isDigital && widget.product['owned'] == true;

    Widget content = Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: widget.isInline
            ? 12
            : MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: widget.isInline
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total price display
          if (isDigital)
            Row(
              children: [
                Text(
                  owned ? 'Vous possédez ce livre' : 'Livre numérique (PDF) :',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                if (!owned) ...[
                  const SizedBox(width: 8),
                  Text(
                    price <= 0 ? 'Gratuit' : '${_formatPrice(price)} FCFA',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFF6210),
                    ),
                  ),
                ],
              ],
            )
          else
          Row(
            children: [
              Text(
                'Total (${widget.quantity} pcs):',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatPrice(price)} FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6210),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (owned)
            GestureDetector(
              onTap: widget.onOpenLibrary,
              child: Container(
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Ouvrir ma Bibliothèque',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
          Row(
            children: [
              // Add to cart button
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => _pressController.forward(),
                  onTapUp: (_) {
                    _pressController.reverse();
                    widget.onAddToCart();
                  },
                  onTapCancel: () => _pressController.reverse(),
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDE3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFF6210),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 18,
                            color: Color(0xFFFF6210),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Panier',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFF6210),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Buy now button
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: widget.onBuyNow,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6210).withAlpha(80),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isDigital && price <= 0 ? 'Obtenir gratuitement' : 'Acheter maintenant',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return content;
  }
}
