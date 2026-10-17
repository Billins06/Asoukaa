import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/grille_produits.dart';
import '../../utils/lecture_json.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../home_screen/widgets/home_product_card.dart';

/// Page « Tous les produits » : tous les produits actifs de la place de
/// marché, les plus récents d'abord, chargés par pages de 20
/// (GET /api/v1/products?page=N&limit=20) au fil du défilement.
///
/// Le serveur ne propose pas de choix de tri (il renvoie toujours les plus
/// récents d'abord) : cette page n'affiche donc pas de menu de tri.
///
/// Les cartes sont celles de l'accueil (HomeProductCard) et la grille suit
/// les réglages communs de lib/utils/grille_produits.dart.
class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  // Le serveur accepte jusqu'à 50 produits par page.
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  final Set<String> _ids = <String>{};

  int _page = 0; // dernière page reçue
  int _total = 0; // nombre total de produits annoncé par le serveur
  bool _hasMore = true;
  bool _loading = false; // une requête est en cours
  String? _error; // message d'erreur de la dernière requête échouée

  // Incrémenté à chaque actualisation : la réponse tardive d'une requête
  // plus ancienne est alors ignorée.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  // Charge la page suivante, ou la première page si [reset] (ouverture,
  // tirer pour actualiser, bouton Réessayer).
  Future<void> _loadPage({bool reset = false}) async {
    if (!reset && (_loading || !_hasMore)) return;
    final gen = reset ? ++_gen : _gen;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ProductService.instance.getProductsPage(
      page: page,
      limit: _pageSize,
    );
    if (!mounted || gen != _gen) return; // réponse périmée : on l'ignore

    final data = result.data;
    if (!result.success || data == null) {
      final hadItems = _items.isNotEmpty;
      setState(() {
        _loading = false;
        // Actualisation ratée alors que la liste est déjà affichée : on la
        // garde et on prévient par un message, sans bloc d'erreur.
        _error = (reset && hadItems)
            ? null
            : (result.error ?? 'Impossible de charger les produits.');
      });
      if (reset && hadItems) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Actualisation impossible. Réessayez.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      if (reset) {
        _items.clear();
        _ids.clear();
      }
      for (final product in data.items) {
        final id = (product['id'] ?? '').toString();
        if (id.isEmpty || !_ids.add(id)) continue; // pas de doublon
        _items.add(product);
      }
      _page = page;
      _total = lireInt(data.total);
      _hasMore = data.hasMore;
      _loading = false;
    });

    // Si la page n'a pas rempli l'écran, on enchaîne sans attendre un geste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });
  }

  // Appelé à chaque défilement : charge la suite quand on approche du bas.
  void _maybeLoadMore() {
    if (_loading || _error != null || !_hasMore || _items.isEmpty) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels <= 600) {
      _loadPage();
    }
  }

  Future<void> _refresh() => _loadPage(reset: true);

  void _openProduct(Map<String, dynamic> product) {
    Navigator.pushNamed(context, AppRoutes.productDetail, arguments: product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Tous les produits',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Panier',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      if (_error != null) {
        return _scrollableMessage(_buildError(_error!));
      }
      if (_loading) return _buildSkeleton();
      return _scrollableMessage(
        EmptyStateWidget(
          icon: Icons.inventory_2_outlined,
          title: 'Aucun produit pour le moment',
          description:
              'De nouveaux produits arrivent régulièrement. Revenez bientôt !',
          ctaLabel: 'Actualiser',
          onCtaTap: _refresh,
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = productGridColumns(constraints.maxWidth);
          return CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildCount()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kProductGridPadding,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: kProductGridRatio,
                    crossAxisSpacing: kProductGridSpacing,
                    mainAxisSpacing: kProductGridSpacing,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = _items[index];
                      return HomeProductCard(
                        key: ValueKey('tous-${product['id']}'),
                        product: product,
                        onTap: _openProduct,
                      );
                    },
                    childCount: _items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildFooter()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCount() {
    final shown = _total > _items.length ? _total : _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Text(
        shown <= 1 ? '$shown produit' : '$shown produits',
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  // Bas de la grille : chargement, « Réessayer », ou fin de liste.
  Widget _buildFooter() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          children: [
            Text(
              'Impossible de charger la suite.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _loadPage,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Réessayer',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }
    if (_loading || _hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          'Vous avez tout vu',
          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppTheme.primaryMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Chargement impossible',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Message centré qui reste « tirable » pour actualiser.
  Widget _scrollableMessage(Widget child) {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: constraints.maxHeight, child: child),
          );
        },
      ),
    );
  }

  // Cartes « fantômes » pendant le premier chargement (même grille que les
  // vraies cartes).
  Widget _buildSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = productGridColumns(constraints.maxWidth);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            kProductGridPadding,
            12,
            kProductGridPadding,
            12,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: kProductGridRatio,
            crossAxisSpacing: kProductGridSpacing,
            mainAxisSpacing: kProductGridSpacing,
          ),
          itemCount: columns * 3,
          itemBuilder: (_, __) => const _ProductSkeletonCard(),
        );
      },
    );
  }
}

// Carte fantôme : une grande zone pour la photo (elle prend la hauteur
// restante, donc rien ne déborde) puis trois lignes de texte.
class _ProductSkeletonCard extends StatelessWidget {
  const _ProductSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox.expand(
              child: LoadingSkeletonWidget(
                width: 10,
                height: 10,
                borderRadius: 16,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingSkeletonWidget(
                  width: double.infinity,
                  height: 11,
                  borderRadius: 4,
                ),
                SizedBox(height: 6),
                LoadingSkeletonWidget(width: 70, height: 10, borderRadius: 4),
                SizedBox(height: 8),
                LoadingSkeletonWidget(width: 50, height: 14, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
