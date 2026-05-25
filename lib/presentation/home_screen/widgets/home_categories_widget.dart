import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';

class HomeCategoriesWidget extends StatelessWidget {
  const HomeCategoriesWidget({super.key});

  static const List<_Category> _categories = [
    _Category(
      label: 'Tous',
      icon: Icons.apps_rounded,
      color: Color(0xFFFF6210),
    ),
    _Category(
      label: 'Mode',
      icon: Icons.checkroom_outlined,
      color: Color(0xFF8B5CF6),
    ),
    _Category(
      label: 'Électronique',
      icon: Icons.devices_outlined,
      color: Color(0xFF3B82F6),
    ),
    _Category(
      label: 'Alimentaire',
      icon: Icons.restaurant_outlined,
      color: Color(0xFF10B981),
    ),
    _Category(
      label: 'Beauté',
      icon: Icons.spa_outlined,
      color: Color(0xFFEC4899),
    ),
    _Category(
      label: 'Auto',
      icon: Icons.directions_car_outlined,
      color: Color(0xFFF59E0B),
    ),
    _Category(
      label: 'Maison',
      icon: Icons.home_outlined,
      color: Color(0xFF06B6D4),
    ),
    _Category(
      label: 'Sports',
      icon: Icons.sports_basketball_outlined,
      color: Color(0xFFDC2626),
    ),
  ];

  void _onCategoryTap(BuildContext context, int index) {
    Navigator.pushNamed(
      context,
      AppRoutes.categories,
      arguments: index == 0 ? 'Tous' : _categories[index].label,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Catégories',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, AppRoutes.categories),
                child: Text(
                  'Voir tout',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF6210),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return GestureDetector(
                onTap: () => _onCategoryTap(context, index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: cat.color.withAlpha(20),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(10),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(cat.icon, size: 24, color: cat.color),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cat.label,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF616161),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Category {
  final String label;
  final IconData icon;
  final Color color;
  const _Category({
    required this.label,
    required this.icon,
    required this.color,
  });
}
