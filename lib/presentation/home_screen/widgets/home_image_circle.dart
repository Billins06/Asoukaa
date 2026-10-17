import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pastille ronde de l'accueil : affiche une image réseau (logo de boutique,
/// image de catégorie) et, quand il n'y a pas d'image (ou qu'elle ne se
/// charge pas), un remplacement propre : une icône sur fond teinté si
/// [icon] est fourni, sinon l'initiale de [label] en orange sur fond
/// orange clair. Jamais d'image cassée ni de bloc rouge.
class HomeImageCircle extends StatelessWidget {
  final String imageUrl;
  final String label;
  final double size;
  final IconData? icon;
  final Color accent;
  final bool withShadow;

  const HomeImageCircle({
    super.key,
    required this.imageUrl,
    required this.label,
    this.size = 54,
    this.icon,
    this.accent = const Color(0xFFFF6210),
    this.withShadow = true,
  });

  bool get _hasImage =>
      imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

  String get _initial {
    final text = label.trim();
    if (text.isEmpty) return '?';
    return String.fromCharCode(text.runes.first).toUpperCase();
  }

  Widget _buildFallback() {
    final iconData = icon;
    if (iconData != null) {
      return Container(
        width: size,
        height: size,
        color: accent.withAlpha(24),
        child: Icon(iconData, size: size * 0.44, color: accent),
      );
    }
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFFFEDE3),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: GoogleFonts.outfit(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFF6210),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF0ECE8)),
        boxShadow: withShadow
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: _hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(),
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) =>
                    Container(color: const Color(0xFFF3EEE9)),
                errorWidget: (context, url, error) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }
}
