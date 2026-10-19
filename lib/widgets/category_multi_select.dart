import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// Choix de plusieurs catégories pour une boutique, sous forme de « combo » :
/// un champ qu'on touche pour ouvrir la liste des catégories PRINCIPALES
/// (pas de sous-catégories), avec des cases à cocher. Les choix apparaissent
/// ensuite sous forme de pastilles.
///
/// Utilisé par tous les formulaires de demande vendeur (inscription,
/// « Devenir vendeur », correction d'une demande refusée, profil boutique).
/// Les catégories viennent de GET /api/v1/categories/tree (route publique).
/// Le choix est une simple étiquette de boutique (il ne limite pas les
/// produits que le vendeur peut publier).
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

class _Cat {
  final String id;
  final String name;
  const _Cat(this.id, this.name);
}

class _CategoryMultiSelectState extends State<CategoryMultiSelect> {
  List<_Cat> _roots = [];
  // sous-catégorie (n'importe quel niveau) → catégorie principale
  final Map<String, String> _rootOf = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _collect(dynamic node, String rootId) {
    if (node is! Map) return;
    final id = (node['id'] ?? '').toString();
    if (id.isNotEmpty) _rootOf[id] = rootId;
    final kids = node['children'];
    if (kids is List) {
      for (final k in kids) {
        _collect(k, rootId);
      }
    }
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
      final roots = <_Cat>[];
      _rootOf.clear();
      if (data is List) {
        for (final node in data) {
          if (node is! Map) continue;
          final id = (node['id'] ?? '').toString();
          final name = (node['name'] ?? '').toString().trim();
          if (id.isEmpty || name.isEmpty) continue;
          // Les sous-catégories d'une catégorie inactive restent rattachées
          // à elle ; seule la catégorie principale active est proposée.
          _collect(node, id);
          if (node['isActive'] == false) continue;
          roots.add(_Cat(id, name));
        }
      }
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _failed = roots.isEmpty;
        _loading = false;
      });
      _normaliserSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  /// Un choix ancien portant sur une sous-catégorie est ramené à sa catégorie
  /// principale (puisqu'on ne propose plus que celles-ci).
  void _normaliserSelection() {
    final rootIds = _roots.map((c) => c.id).toSet();
    final out = <String>[];
    for (final id in widget.selectedIds) {
      final r = rootIds.contains(id) ? id : _rootOf[id];
      if (r != null && rootIds.contains(r) && !out.contains(r)) out.add(r);
    }
    if (out.length > widget.maxSelection) {
      out.removeRange(widget.maxSelection, out.length);
    }
    final same = out.length == widget.selectedIds.length &&
        out.every(widget.selectedIds.contains);
    if (!same) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(out);
      });
    }
  }

  String _nameOf(String id) {
    for (final c in _roots) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  Future<void> _ouvrir() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CategorySheet(
        roots: _roots,
        initial: widget.selectedIds
            .where((id) => _roots.any((c) => c.id == id))
            .toList(),
        max: widget.maxSelection,
      ),
    );
    if (result != null && mounted) widget.onChanged(result);
  }

  void _retirer(String id) {
    widget.onChanged(widget.selectedIds.where((e) => e != id).toList());
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

    final chosen = widget.selectedIds.where((id) => _nameOf(id).isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Le « combo » : un champ qui ouvre la liste.
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _ouvrir,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.selectedIds.isEmpty
                        ? 'Choisir une ou plusieurs catégories'
                        : '${widget.selectedIds.length} catégorie(s) choisie(s)',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: widget.selectedIds.isEmpty
                          ? AppTheme.muted
                          : AppTheme.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.muted),
              ],
            ),
          ),
        ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in chosen)
                InputChip(
                  label: Text(
                    _nameOf(id),
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                  backgroundColor: AppTheme.primaryMuted,
                  side: BorderSide.none,
                  deleteIconColor: AppTheme.primary,
                  onDeleted: () => _retirer(id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '${widget.selectedIds.length}/${widget.maxSelection} choisies',
          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
        ),
      ],
    );
  }
}

/// Feuille « liste à cocher » ouverte par le combo.
class _CategorySheet extends StatefulWidget {
  final List<_Cat> roots;
  final List<String> initial;
  final int max;
  const _CategorySheet({
    required this.roots,
    required this.initial,
    required this.max,
  });

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final List<String> _sel = List<String>.from(widget.initial);

  void _toggle(String id) {
    setState(() {
      if (_sel.contains(id)) {
        _sel.remove(id);
      } else if (_sel.length >= widget.max) {
        AppToast.show(
          context,
          message: 'Vous pouvez choisir ${widget.max} catégories au maximum.',
          type: ToastType.error,
        );
      } else {
        _sel.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'Catégories de la boutique',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _sel.length >= widget.max
                  ? '${widget.max} catégories au maximum — décochez-en une pour en changer'
                  : '${_sel.length}/${widget.max} choisies',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in widget.roots)
                    CheckboxListTile(
                      value: _sel.contains(c.id),
                      activeColor: AppTheme.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(
                        c.name,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: _sel.contains(c.id)
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      onChanged: (_sel.length >= widget.max && !_sel.contains(c.id))
                          ? null
                          : (_) => _toggle(c.id),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, _sel),
                  child: Text(
                    'Valider',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
