import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Titre de section de l'accueil (pastille orange clair + intitulé), même
/// style que « Tendances » : utilisé par « Meilleures boutiques » et
/// « Tous les produits ».
class HomeSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  /// Si fourni, affiche le lien orange « Voir tout » à droite du titre.
  final VoidCallback? onSeeAll;

  const HomeSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDE3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFFF6210)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
          if (onSeeAll != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Voir tout',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF6210),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
