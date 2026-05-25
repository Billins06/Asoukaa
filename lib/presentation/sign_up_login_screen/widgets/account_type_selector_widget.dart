import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AccountTypeSelectorWidget extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onTypeChanged;

  const AccountTypeSelectorWidget({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
  });

  static const List<_AccountType> _types = [
    _AccountType(
      value: 'acheteur',
      label: 'Acheteur',
      icon: Icons.shopping_bag_outlined,
      description: 'Achetez des produits',
    ),
    _AccountType(
      value: 'vendeur',
      label: 'Vendeur',
      icon: Icons.storefront_outlined,
      description: 'Vendez vos produits',
    ),
    _AccountType(
      value: 'livreur',
      label: 'Livreur',
      icon: Icons.delivery_dining_outlined,
      description: 'Livrez des colis',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type de compte',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: _types
              .map(
                (type) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: type.value == _types.last.value ? 0 : 8,
                    ),
                    child: _TypeCard(
                      type: type,
                      isSelected: selectedType == type.value,
                      onTap: () => onTypeChanged(type.value),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _TypeCard extends StatefulWidget {
  final _AccountType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.isSelected ? const Color(0xFFFFEDE3) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFFF6210)
                  : const Color(0xFFE0E0E0),
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? const Color(0xFFFF6210)
                      : const Color(0xFFF5F2EF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.type.icon,
                  size: 20,
                  color: widget.isSelected
                      ? Colors.white
                      : const Color(0xFF9E9E9E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.type.label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.isSelected
                      ? const Color(0xFFFF6210)
                      : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.type.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9E9E9E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountType {
  final String value;
  final String label;
  final IconData icon;
  final String description;

  const _AccountType({
    required this.value,
    required this.label,
    required this.icon,
    required this.description,
  });
}
