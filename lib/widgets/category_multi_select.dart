import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Choix de plusieurs catégories (puces cochables) pour une boutique.
///
/// Utilisé par tous les formulaires de demande vendeur (inscription,
/// « Devenir vendeur », correction d'une demande refusée). Les catégories
/// viennent de GET /api/v1/categories/tree (route publique) : on garde les
/// catégories principales ACTIVES. Le choix est une simple étiquette de
/// boutique (il ne limite pas les produits que le vendeur peut publier).
class CategoryMultiSelect extends StatefulWidget {
  /// Ids actuellement choisis.
  final List<String> selectedIds;

  /// Appelé avec la nouvelle liste à chaque changement.
  final ValueChanged<List<String>> onChanged;

  /// Nombre maximum de catégories (le serveur refuse au-delà de 5).
  final int maxSelection;

  const CategoryMultiSelect({
    super.key,
    required this.selectedIds,
    required this.onChanged,
    this.maxSelection = 5,
  });

  @override
  State<CategoryMultiSelect> createState() => _CategoryMultiSelectState();
}

class _CategoryMultiSelectState extends State<CategoryMultiSelect> {
  List<Map<String, String>> _categories = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res =
          await ApiService.instance.client.get('/api/v1/categories/tree');
      final data = res.data;
      final list = <Map<String, String>>[];
      if (data is List) {
        for (final node in data) {
          if (node is! Map) continue;
          if (node['isActive'] == false) continue;
          final id = (node['id'] ?? '').toString();
          final name = (node['name'] ?? '').toString().trim();
          if (id.isEmpty || name.isEmpty) continue;
          list.add({'id': id, 'name': name});
        }
      }
      if (!mounted) return;
      setState(() {
        _categories = list;
        _failed = list.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _toggle(String id) {
    final current = List<String>.from(widget.selectedIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      if (current.length >= widget.maxSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vous pouvez choisir ${widget.maxSelection} catégories au maximum.',
              style: GoogleFonts.outfit(),
            ),
          ),
        );
        return;
      }
      current.add(id);
    }
    widget.onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        ),
      );
    }

    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Impossible de charger les catégories.',
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
              ),
            ),
            TextButton(
              onPressed: _load,
              child: Text(
                'Réessayer',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((c) {
            final id = c['id']!;
            final selected = widget.selectedIds.contains(id);
            return GestureDetector(
              onTap: () => _toggle(id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFEDE3)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : const Color(0xFFE0E0E0),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      const Icon(Icons.check,
                          size: 15, color: AppTheme.primary),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      c['name']!,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.selectedIds.length}/${widget.maxSelection} choisies',
          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
        ),
      ],
    );
  }
}
