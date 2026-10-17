import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';

/// Bouton rond (44 px par défaut) bordé, avec pastille de quantité
/// optionnelle (ex. nombre d'articles du panier).
/// Utilisé par la page Catégories et la page G (produits d'une catégorie).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final bool bordered;
  final double size;
  final double iconSize;
  final String? semanticLabel;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.bordered = true,
    this.size = 44,
    this.iconSize = 21,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white,
      shape: CircleBorder(
        side: bordered
            ? const BorderSide(color: Color(0xFFE5DFD8))
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: AppTheme.textPrimary),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (badgeCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: IgnorePointer(
                child: Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
