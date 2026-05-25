import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProductPriceTiersWidget extends StatefulWidget {
  final List<Map<String, dynamic>> priceTiers;
  final int currentQty;
  final ValueChanged<int> onQtyChanged;

  const ProductPriceTiersWidget({
    super.key,
    required this.priceTiers,
    required this.currentQty,
    required this.onQtyChanged,
  });

  @override
  State<ProductPriceTiersWidget> createState() =>
      _ProductPriceTiersWidgetState();
}

class _ProductPriceTiersWidgetState extends State<ProductPriceTiersWidget> {
  int _selectedTierIndex = 0;

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
    if (widget.priceTiers.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_offer_outlined,
                size: 16,
                color: Color(0xFFFF6210),
              ),
              const SizedBox(width: 8),
              Text(
                'Prix dégressifs',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Price tiers table
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: List.generate(widget.priceTiers.length, (index) {
                  final tier = widget.priceTiers[index];
                  final isSelected = _selectedTierIndex == index;
                  final isLast = index == widget.priceTiers.length - 1;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedTierIndex = index);
                      widget.onQtyChanged(tier['qty'] as int);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFF8F5)
                            : Colors.white,
                        border: !isLast
                            ? const Border(
                                bottom: BorderSide(
                                  color: Color(0xFFF0F0F0),
                                  width: 1,
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFF6210)
                                    : const Color(0xFFE0E0E0),
                                width: 2,
                              ),
                              color: isSelected
                                  ? const Color(0xFFFF6210)
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            tier['label'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_formatPrice(tier['price'] as int)} FCFA',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFFFF6210)
                                  : const Color(0xFF1A1A1A),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (index > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '-${_getSavingPercent(index)}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF16A34A),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quantity selector
          Row(
            children: [
              Text(
                'Quantité',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _QtyButton(
                      icon: Icons.remove_rounded,
                      onTap: () {
                        if (widget.currentQty > 1) {
                          widget.onQtyChanged(widget.currentQty - 1);
                        }
                      },
                    ),
                    Container(
                      width: 44,
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.currentQty}',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add_rounded,
                      onTap: () => widget.onQtyChanged(widget.currentQty + 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _getSavingPercent(int tierIndex) {
    if (widget.priceTiers.isEmpty || tierIndex == 0) return 0;
    final basePrice = widget.priceTiers[0]['price'] as int;
    final tierPrice = widget.priceTiers[tierIndex]['price'] as int;
    return (((basePrice - tierPrice) / basePrice) * 100).round();
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
      ),
    );
  }
}
