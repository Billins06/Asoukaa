import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';
import '../../../services/api_service.dart';
import './home_image_circle.dart';

class HomeCategoriesWidget extends StatefulWidget {
  const HomeCategoriesWidget({super.key});

  @override
  State<HomeCategoriesWidget> createState() => _HomeCategoriesWidgetState();
}

class _HomeCategoriesWidgetState extends State<HomeCategoriesWidget> {
  // Liste d'origine (icônes) : « Tous » en tête, et repli si les catégories
  // du serveur ne peuvent pas être chargées.
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

  // Catégories racines actives du serveur (avec leur image). Vide tant que
  // rien n'est chargé ou si l'appel échoue : on affiche alors la liste
  // d'origine, sans aucun message d'erreur.
  List<_Category> _remote = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  static String _textOf(dynamic value) => (value ?? '').toString().trim();

  static int _sortOrderOf(Map<String, dynamic> c) =>
      int.tryParse(_textOf(c['sortOrder'])) ?? 0;

  /// GET /api/v1/categories/tree : entités complètes (imageUrl, sortOrder,
  /// isActive), racines au premier niveau. Les inactives sont écartées.
  Future<void> _loadCategories() async {
    final loaded = <_Category>[];
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/categories/tree');
      final data = res.data;
      if (data is List) {
        final roots = <Map<String, dynamic>>[
          for (final node in data)
            if (node is Map && node['isActive'] != false)
              Map<String, dynamic>.from(node),
        ];
        roots.sort((a, b) {
          final byOrder = _sortOrderOf(a).compareTo(_sortOrderOf(b));
          if (byOrder != 0) return byOrder;
          return _textOf(a['name'])
              .toLowerCase()
              .compareTo(_textOf(b['name']).toLowerCase());
        });
        for (final c in roots) {
          final label = _textOf(c['name']);
          if (label.isEmpty) continue;
          final image = _textOf(c['imageUrl']);
          loaded.add(
            _Category(
              label: label,
              color: const Color(0xFFFF6210),
              id: _textOf(c['id']),
              imageUrl: (image.startsWith('http://') ||
                      image.startsWith('https://'))
                  ? image
                  : '',
            ),
          );
        }
      }
    } catch (_) {
      // Repli silencieux sur la liste d'origine.
    }
    if (!mounted) return;
    setState(() {
      _remote = loaded;
      _loading = false;
    });
  }

  List<_Category> get _items =>
      _remote.isEmpty ? _categories : [_categories.first, ..._remote];

  void _onCategoryTap(_Category cat, int index) {
    // L'écran Catégories accepte un nom, un slug ou un id : l'id est le plus
    // exact pour une catégorie du serveur.
    Navigator.pushNamed(
      context,
      AppRoutes.categories,
      arguments: index == 0
          ? 'Tous'
          : (cat.id.isNotEmpty ? cat.id : cat.label),
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
          child: _loading ? _buildSkeleton() : _buildList(),
        ),
      ],
    );
  }

  // Cercles gris pendant le chargement (évite un clignotement d'icônes).
  Widget _buildSkeleton() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 68,
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFEDE8E3),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE8E3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildList() {
    final items = _items;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final cat = items[index];
        return GestureDetector(
          onTap: () => _onCategoryTap(cat, index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  HomeImageCircle(
                    imageUrl: cat.imageUrl,
                    label: cat.label,
                    size: 54,
                    icon: cat.icon,
                    accent: cat.color,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF616161),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Category {
  final String label;
  final IconData? icon;
  final Color color;
  final String imageUrl;
  final String id;
  const _Category({
    required this.label,
    this.icon,
    required this.color,
    this.imageUrl = '',
    this.id = '',
  });
}
