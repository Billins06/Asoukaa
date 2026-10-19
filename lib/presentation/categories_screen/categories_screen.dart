import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/connection_error_widget.dart';
import '../../widgets/custom_image_widget.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/mode_service.dart';
import '../../services/vitrine_service.dart';
import '../category_products_screen/widgets/round_icon_button.dart';

/// Page Catégories (2 colonnes) :
/// - à gauche « Pour vous » puis les catégories racines ;
/// - à droite le bandeau + la grille de pastilles rondes (sous-catégories,
///   ou rayons de la Vitrine pour « Pour vous »).
/// Taper une pastille ouvre la page G (AppRoutes.categoryProducts).
class CategoriesScreen extends StatefulWidget {
  /// Catégorie à présélectionner (nom, slug ou id). 'Tous' ou null =>
  /// « Pour vous ». Envoyée par la page d'accueil (home_categories_widget).
  final String? initialCategory;
  const CategoriesScreen({super.key, this.initialCategory});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  int _currentNavIndex = 1;

  static const Color _railBg = Color(0xFFF5F2EF);
  static const Color _railText = Color(0xFF5C5651);
  static const Color _hairline = Color(0xFFEFEAE4);
  static const Color _skeleton = Color(0xFFEDE8E3);

  // Anciens libellés de la page d'accueil qui diffèrent du nom en base
  // (repris de l'ancien tableau _categories : label → dbValue).
  static const Map<String, String> _legacyAliases = {
    'alimentaire': 'alimentation',
  };

  final ScrollController _rightScroll = ScrollController();

  bool _isLoading = true;
  String? _error;
  // Toutes les catégories actives, par id.
  Map<String, Map<String, dynamic>> _byId = {};
  // Catégories racines (parentId null), triées sortOrder puis nom.
  List<Map<String, dynamic>> _roots = [];
  // Enfants directs de chaque catégorie, triés.
  Map<String, List<Map<String, dynamic>>> _childrenByParent = {};
  // Catégorie racine sélectionnée à gauche ; null = « Pour vous ».
  String? _selectedId;
  bool _initialApplied = false;

  // Vitrine (« Pour vous »).
  Map<String, dynamic>? _bandeau;
  List<Map<String, dynamic>> _rayons = [];

  int _cartCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadCartCount();
  }

  @override
  void dispose() {
    _rightScroll.dispose();
    super.dispose();
  }

  // ─── Chargement ──────────────────────────────────────────────────────

  Future<void> _loadAll({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    final categoriesFuture = _fetchCategories();
    final vitrineFuture = VitrineService.instance.getVitrine();
    final categories = await categoriesFuture;
    final vitrine = await vitrineFuture;
    if (!mounted) return;

    if (categories == null) {
      if (showLoader || _roots.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'Impossible de charger les catégories. '
              'Vérifiez votre connexion puis réessayez.';
        });
      } else {
        // Pull-to-refresh raté : on garde ce qui est affiché.
        setState(() => _isLoading = false);
        _showErrorSnack('Actualisation impossible. Réessayez plus tard.');
      }
      return;
    }

    setState(() {
      _indexCategories(categories);
      _bandeau = vitrine.bandeau;
      _rayons = vitrine.rayons
          .where((r) => _str(r['id']).isNotEmpty)
          .toList();
      _isLoading = false;
      _error = null;
      if (!_initialApplied) {
        _initialApplied = true;
        _selectedId = _matchInitialCategory();
      } else if (_selectedId != null && !_byId.containsKey(_selectedId)) {
        _selectedId = null;
      }
    });
  }

  /// Catégories actives à plat (avec parentId, imageUrl, sortOrder).
  /// GET /categories/tree renvoie les entités complètes (dont imageUrl et
  /// sortOrder, absents de /categories/flat) mais AUSSI les inactives :
  /// on les écarte (avec leur sous-arbre). Repli sur /categories/flat.
  /// Retourne null en cas d'échec réseau.
  Future<List<Map<String, dynamic>>?> _fetchCategories() async {
    try {
      final res = await ApiService.instance.client.get('/api/v1/categories/tree');
      final data = res.data;
      if (data is List) {
        final flat = <Map<String, dynamic>>[];
        void walk(List<dynamic> nodes, String? parentId) {
          for (final node in nodes) {
            if (node is! Map) continue;
            if (node['isActive'] == false) continue;
            final category = Map<String, dynamic>.from(node);
            final children = category.remove('children');
            category['parentId'] ??= parentId;
            flat.add(category);
            if (children is List) walk(children, _str(category['id']));
          }
        }

        walk(data, null);
        return flat;
      }
    } catch (_) {}
    try {
      final res = await ApiService.instance.client.get('/api/v1/categories/flat');
      final data = res.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return null;
  }

  void _indexCategories(List<Map<String, dynamic>> all) {
    final byId = <String, Map<String, dynamic>>{};
    final position = <String, int>{};
    for (var i = 0; i < all.length; i++) {
      final id = _str(all[i]['id']);
      if (id.isEmpty || byId.containsKey(id)) continue;
      byId[id] = all[i];
      position[id] = i;
    }

    // Tri : sortOrder puis nom. Sans sortOrder (repli /flat), on garde
    // l'ordre du serveur (déjà trié sortOrder, nom).
    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      if (a.containsKey('sortOrder') && b.containsKey('sortOrder')) {
        final byOrder = _sortOrderOf(a).compareTo(_sortOrderOf(b));
        if (byOrder != 0) return byOrder;
        return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      }
      return (position[_str(a['id'])] ?? 0)
          .compareTo(position[_str(b['id'])] ?? 0);
    }

    final roots = <Map<String, dynamic>>[];
    final children = <String, List<Map<String, dynamic>>>{};
    for (final category in byId.values) {
      final parentId = _str(category['parentId']);
      if (parentId.isEmpty) {
        roots.add(category);
      } else if (byId.containsKey(parentId)) {
        children
            .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
            .add(category);
      }
      // Parent absent (inactif) : la sous-catégorie n'est pas affichée.
    }
    roots.sort(compare);
    for (final list in children.values) {
      list.sort(compare);
    }

    _byId = byId;
    _roots = roots;
    _childrenByParent = children;
  }

  /// Compatibilité avec l'existant : initialCategory peut être un nom
  /// (« Mode », « Électronique », « Alimentaire »…), un slug ou un id.
  /// Une sous-catégorie sélectionne sa catégorie racine.
  String? _matchInitialCategory() {
    final raw = (widget.initialCategory ?? '').trim();
    if (raw.isEmpty) return null;
    var wanted = _normalize(raw);
    if (wanted == 'tous' || wanted == 'pour vous') return null;
    wanted = _legacyAliases[wanted] ?? wanted;

    Map<String, dynamic>? found;
    final candidates = [..._roots, ..._byId.values];
    for (final c in candidates) {
      if (_str(c['id']) == raw ||
          _normalize(_nameOf(c)) == wanted ||
          _normalize(_str(c['slug'])) == wanted) {
        found = c;
        break;
      }
    }
    if (found == null) {
      for (final c in _roots) {
        if (_normalize(_nameOf(c)).startsWith(wanted)) {
          found = c;
          break;
        }
      }
    }
    if (found == null) return null;

    Map<String, dynamic> current = found;
    for (var guard = 0; guard < 10; guard++) {
      final parentId = _str(current['parentId']);
      final parent = parentId.isEmpty ? null : _byId[parentId];
      if (parent == null) break;
      current = parent;
    }
    // Les catégories numériques n'ont pas de ligne propre à gauche (entrée fixe).
    if (current['isDigital'] == true) return null;
    final id = _str(current['id']);
    return id.isEmpty ? null : id;
  }

  Future<void> _loadCartCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) setState(() => _cartCount = 0);
        return;
      }
      final response = await ApiService.instance.client.get('/api/v1/cart');
      final data = response.data;
      final count = (data is Map)
          ? (data['itemCount'] as int? ??
              (data['items'] as List?)?.length ??
              0)
          : 0;
      if (mounted) setState(() => _cartCount = count);
    } catch (_) {
      if (mounted) setState(() => _cartCount = 0);
    }
  }

  Future<void> _refresh() async {
    await Future.wait<void>([
      _loadAll(showLoader: false),
      _loadCartCount(),
    ]);
  }

  // ─── Utilitaires ─────────────────────────────────────────────────────

  static String _str(dynamic value) => (value ?? '').toString().trim();

  static String _nameOf(Map<String, dynamic> c) => _str(c['name']);

  static int _sortOrderOf(Map<String, dynamic> c) =>
      int.tryParse(_str(c['sortOrder'])) ?? 0;

  /// URL d'image exploitable (http/https), sinon '' (=> repli visuel).
  static String _imageUrl(dynamic value) {
    final s = _str(value);
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return '';
  }

  /// Minuscules sans accents, tirets remplacés par des espaces.
  static String _normalize(String input) {
    const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy';
    final buffer = StringBuffer();
    for (final ch in input.toLowerCase().trim().split('')) {
      final index = from.indexOf(ch);
      buffer.write(index >= 0 ? to[index] : ch);
    }
    return buffer.toString().replaceAll('-', ' ');
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────

  void _openSearch() {
    Navigator.pushNamed(
      context,
      AppRoutes.searchResults,
      arguments: '',
    ).then((_) => _loadCartCount());
  }

  void _openCart() {
    Navigator.pushNamed(context, AppRoutes.cart).then((_) => _loadCartCount());
  }

  /// Ouvre la page G. mode : 'category' ou 'rayon'.
  void _openProducts({
    required String mode,
    required String id,
    required String title,
    String? parentTitle,
  }) {
    if (id.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppRoutes.categoryProducts,
      arguments: <String, dynamic>{
        'mode': mode,
        'id': id,
        'title': title,
        'parentTitle': parentTitle,
      },
    ).then((_) => _loadCartCount());
  }

  void _scrollRightToTop() {
    if (_rightScroll.hasClients) _rightScroll.jumpTo(0);
  }

  void _selectPourVous() {
    if (_selectedId == null) return;
    setState(() => _selectedId = null);
    _scrollRightToTop();
  }

  /// Entrée fixe « Livres numériques » : ouvre directement tous les livres.
  void _onDigitalTap() {
    _openProducts(
      mode: 'digital',
      id: 'digital',
      title: 'Livres numériques',
      parentTitle: 'Catégories',
    );
  }

  /// Catégories racines affichées dans la colonne de gauche : les catégories
  /// numériques sont regroupées dans l'entrée fixe « Livres numériques ».
  List<Map<String, dynamic>> get _railRoots =>
      _roots.where((c) => c['isDigital'] != true).toList();

  /// Catégorie avec sous-catégories → affichées à droite.
  /// Catégorie sans sous-catégorie → page G directement (la sélection ne
  /// change pas).
  void _onRootTap(Map<String, dynamic> category) {
    final id = _str(category['id']);
    if (id.isEmpty) return;
    final children = _childrenByParent[id] ?? const <Map<String, dynamic>>[];
    if (children.isEmpty) {
      _openProducts(
        mode: 'category',
        id: id,
        title: _nameOf(category),
        parentTitle: 'Catégories',
      );
      return;
    }
    if (_selectedId == id) return;
    setState(() => _selectedId = id);
    _scrollRightToTop();
  }

  // ─── Barre de navigation du bas (reprise telle quelle) ──────────────

  Future<void> _navigateToProfile() async {
    final loggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!mounted) return;
    if (!loggedIn) {
      Navigator.pushNamed(context, AppRoutes.signUpLogin);
    } else {
      Navigator.pushNamed(context, AppRoutes.buyerProfile);
    }
  }

  Future<void> _navigateToDashboard() async {
    try {
      // Rôle effectif : un vendeur en « mode client » reste côté client.
      final role = await ModeService.instance.getEffectiveRole()
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      switch (role) {
        case 'vendeur':
          Navigator.pushNamed(context, AppRoutes.sellerDashboard);
        case 'livreur':
          Navigator.pushNamed(context, AppRoutes.delivererDashboard);
        default:
          Navigator.pushNamed(context, AppRoutes.buyerDashboard);
      }
    } catch (_) {
      if (mounted) Navigator.pushNamed(context, AppRoutes.buyerDashboard);
    }
  }

  Future<void> _navigateToMessages() async {
    try {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn()
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      if (!isLoggedIn) {
        Navigator.pushNamed(context, AppRoutes.signUpLogin);
        return;
      }
      Navigator.pushNamed(context, AppRoutes.conversationsInbox);
    } catch (_) {
      if (mounted) Navigator.pushNamed(context, AppRoutes.signUpLogin);
    }
  }

  // ─── Construction de l'écran ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, thickness: 1, color: _hairline),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: AsoukaaBottomNav(
        currentIndex: _currentNavIndex,
        onTap: (i) {
          setState(() => _currentNavIndex = i);
          switch (i) {
            case 0:
              Navigator.pushReplacementNamed(context, AppRoutes.home);
              break;
            case 1:
              break;
            case 2:
              _navigateToMessages();
              break;
            case 3:
              _navigateToDashboard();
              break;
            case 4:
              _navigateToProfile();
              break;
          }
        },
      ),
    );
  }

  Widget _buildHeader() {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 16, 10, 16, 10),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              tooltip: 'Retour',
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.maybePop(context),
            ),
          Expanded(
            child: Text(
              'Catégories',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1.15,
              ),
            ),
          ),
          RoundIconButton(
            icon: Icons.search_rounded,
            semanticLabel: 'Rechercher',
            onTap: _openSearch,
          ),
          const SizedBox(width: 10),
          RoundIconButton(
            icon: Icons.shopping_cart_outlined,
            badgeCount: _cartCount,
            semanticLabel: 'Panier',
            onTap: _openCart,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildSkeleton();
    if (_error != null) {
      return ConnectionErrorScreen(
        onRetry: () => _loadAll(),
        title: 'Catégories indisponibles',
        message: _error,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 104, child: _buildRail()),
        Expanded(child: _buildRightPanel()),
      ],
    );
  }

  // ─── Colonne gauche ──────────────────────────────────────────────────

  Widget _buildRail() {
    final railRoots = _railRoots;
    return ColoredBox(
      color: _railBg,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: railRoots.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _railItem(
              label: 'Pour vous',
              selected: _selectedId == null,
              onTap: _selectPourVous,
            );
          }
          if (i == 1) {
            return _railItem(
              label: 'Livres numériques',
              selected: false,
              onTap: _onDigitalTap,
            );
          }
          final category = railRoots[i - 2];
          return _railItem(
            label: _nameOf(category),
            selected: _selectedId == _str(category['id']),
            onTap: () => _onRootTap(category),
          );
        },
      ),
    );
  }

  Widget _railItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 15, color: AppTheme.primary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? AppTheme.textPrimary : _railText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Colonne droite ──────────────────────────────────────────────────

  Widget _buildRightPanel() {
    final selectedId = _selectedId;
    final selected = selectedId == null ? null : _byId[selectedId];
    final children =
        selected == null ? _pourVousContent() : _categoryContent(selected);

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        controller: _rightScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: children,
      ),
    );
  }

  List<Widget> _pourVousContent() {
    final bandeau = _bandeau;
    final title = _str(bandeau?['titre']);
    final subtitle = _str(bandeau?['sousTitre']);
    final hasBandeau = title.isNotEmpty || subtitle.isNotEmpty;

    return [
      _buildBanner(
        title: hasBandeau ? title : 'La sélection du moment',
        subtitle: hasBandeau ? subtitle : 'Choisie pour vous',
        imageUrl: _imageUrl(bandeau?['imageUrl']),
      ),
      const SizedBox(height: 18),
      _sectionHeader('La Vitrine'),
      const SizedBox(height: 12),
      if (_rayons.isEmpty)
        _emptyMessage(
          'La vitrine se prépare',
          'Nos sélections arrivent très bientôt. En attendant, '
              'explorez les catégories à gauche.',
        )
      else
        _bubbleGrid([
          for (final rayon in _rayons)
            _Bubble(
              label: _str(rayon['nom']).isEmpty ? 'Rayon' : _str(rayon['nom']),
              imageUrl: _imageUrl(rayon['imageUrl']),
              onTap: () => _openProducts(
                mode: 'rayon',
                id: _str(rayon['id']),
                title: _str(rayon['nom']).isEmpty
                    ? 'Rayon'
                    : _str(rayon['nom']),
                parentTitle: 'La Vitrine',
              ),
            ),
        ]),
    ];
  }

  List<Widget> _categoryContent(Map<String, dynamic> category) {
    final id = _str(category['id']);
    final name = _nameOf(category);
    final subs = _childrenByParent[id] ?? const <Map<String, dynamic>>[];

    void openAll() => _openProducts(
          mode: 'category',
          id: id,
          title: name,
          parentTitle: 'Catégories',
        );

    return [
      _buildBanner(
        title: name,
        subtitle: subs.isEmpty
            ? 'Tous les produits'
            : '${subs.length} sous-catégorie${subs.length > 1 ? 's' : ''}',
        imageUrl: _imageUrl(category['imageUrl']),
      ),
      const SizedBox(height: 18),
      _sectionHeader(
        subs.isEmpty ? 'Produits' : 'Sous-catégories',
        onSeeAll: openAll,
      ),
      const SizedBox(height: 12),
      _bubbleGrid([
        _Bubble(label: 'Tout voir', seeAll: true, onTap: openAll),
        for (final sub in subs)
          _Bubble(
            label: _nameOf(sub),
            imageUrl: _imageUrl(sub['imageUrl']),
            // Même si la sous-catégorie a ses propres enfants (niveau 3),
            // on ouvre la page G : le serveur inclut les descendants.
            onTap: () => _openProducts(
              mode: 'category',
              id: _str(sub['id']),
              title: _nameOf(sub),
              parentTitle: name,
            ),
          ),
      ]),
    ];
  }

  Widget _buildBanner({
    required String title,
    required String subtitle,
    required String imageUrl,
  }) {
    return Container(
      height: 92,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (imageUrl.isNotEmpty)
            SizedBox(
              width: 96,
              height: 92,
              child: CustomImageWidget(
                imageUrl: imageUrl,
                width: 96,
                height: 92,
                fit: BoxFit.cover,
                semanticLabel: title,
                errorWidget: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (onSeeAll != null)
          InkWell(
            onTap: onSeeAll,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                'Tout voir',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Grille de 3 colonnes de pastilles rondes (76 px, réduites si l'écran
  /// est trop étroit).
  Widget _bubbleGrid(List<_Bubble> bubbles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth = ((constraints.maxWidth - spacing * 2) / 3)
            .floorToDouble();
        final circle = itemWidth - 4 < 76 ? itemWidth - 4 : 76.0;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            for (final bubble in bubbles)
              SizedBox(
                width: itemWidth,
                child: _buildBubble(bubble, circle),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBubble(_Bubble bubble, double circle) {
    final initial = bubble.label.isEmpty
        ? '?'
        : bubble.label.substring(0, 1).toUpperCase();
    final fallback = Center(
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          fontSize: circle * 0.34,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );

    final Widget inner;
    if (bubble.seeAll) {
      inner = Icon(
        Icons.grid_view_rounded,
        size: circle * 0.36,
        color: AppTheme.primary,
      );
    } else if (bubble.imageUrl.isEmpty) {
      inner = fallback;
    } else {
      inner = CustomImageWidget(
        imageUrl: bubble.imageUrl,
        width: circle,
        height: circle,
        fit: BoxFit.cover,
        semanticLabel: bubble.label,
        errorWidget: fallback,
      );
    }

    return Semantics(
      button: true,
      label: bubble.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bubble.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: circle,
              height: circle,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryMuted,
              ),
              foregroundDecoration: bubble.seeAll
                  ? null
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _hairline),
                    ),
              child: Center(child: inner),
            ),
            const SizedBox(height: 6),
            Text(
              bubble.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                height: 1.25,
                fontWeight: bubble.seeAll ? FontWeight.w700 : FontWeight.w500,
                color: bubble.seeAll ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMessage(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: _railBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 32,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 12.5, color: _railText),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget block(double width, double height, {double radius = 8}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _skeleton,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 104,
          color: _railBg,
          child: ListView(
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 0),
            children: [
              for (var i = 0; i < 10; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: block(i.isEven ? 64 : 50, 12),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              block(double.infinity, 92, radius: 14),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: block(120, 16),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (var i = 0; i < 6; i++) block(64, 64, radius: 32),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pastille ronde de la grille de droite.
class _Bubble {
  final String label;
  final String imageUrl;
  final bool seeAll;
  final VoidCallback onTap;

  const _Bubble({
    required this.label,
    required this.onTap,
    this.imageUrl = '',
    this.seeAll = false,
  });
}
