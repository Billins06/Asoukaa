import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../routes/app_routes.dart';
import '../../../services/nest_auth_service.dart';
import '../../../services/shops_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/custom_image_widget.dart';

/// Liste réutilisable des boutiques (annuaire des vendeurs).
///
/// Ne contient PAS de Scaffold : elle peut être placée dans un
/// TabBarView, un Expanded ou le body d'un Scaffold. Elle gère elle-même
/// le défilement, le chargement, l'état vide, l'erreur (+ Réessayer), le
/// tirer-pour-rafraîchir et la pagination infinie.
///
/// [categoryId] : limite l'annuaire aux boutiques vendant dans cette
/// catégorie (onglet « Boutiques » de la page d'une catégorie).
class ShopsListView extends StatefulWidget {
  const ShopsListView({super.key, this.categoryId, this.showSearch = true});

  final String? categoryId;
  final bool showSearch;

  @override
  State<ShopsListView> createState() => _ShopsListViewState();
}

class _ShopsListViewState extends State<ShopsListView> {
  static const int _pageSize = 20;
  static const Color _line = Color(0xFFF0ECE8);

  static const List<({String key, String label})> _filters = [
    (key: 'all', label: 'Toutes'),
    (key: 'verified', label: 'Vérifiées'),
    (key: 'new', label: 'Nouvelles'),
  ];

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _filter = 'all';
  String _search = '';

  List<Map<String, dynamic>> _shops = [];
  int _page = 1;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _needsLogin = false;
  String? _error;
  final Set<String> _followBusy = {};

  // Numéro de la requête en cours : une réponse arrivée après un
  // changement de recherche / filtre est ignorée.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShopsListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _shops = [];
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Chargement ────────────────────────────────────────────────────

  /// Recharge la première page. Si la liste est vide, affiche le
  /// chargement plein écran ; sinon (pull-to-refresh) garde la liste.
  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = _shops.isEmpty;
      _isLoadingMore = false;
      _error = null;
      _needsLogin = false;
    });

    try {
      final result = await ShopsService.instance.getDirectory(
        search: _search,
        filter: _filter,
        categoryId: widget.categoryId,
        page: 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _shops = result.shops;
        _page = result.page;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      final message = ShopsService.errorMessage(
        e,
        'Impossible de charger les boutiques',
      );
      final hadShops = _shops.isNotEmpty;
      setState(() {
        _isLoading = false;
        if (ShopsService.isUnauthorized(e)) {
          _needsLogin = true;
          _shops = [];
        } else {
          _error = message;
        }
      });
      // Liste déjà affichée (pull-to-refresh) : on la garde et on prévient.
      if (hadShops && !_needsLogin) {
        AppToast.show(context, message: message, type: ToastType.error);
      }
    }
  }

  /// Nouvelle recherche / nouveau filtre : on repart d'une liste vide.
  void _restart() {
    _shops = [];
    _load();
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _error != null) return;
    final seq = _requestSeq;
    setState(() => _isLoadingMore = true);
    try {
      final result = await ShopsService.instance.getDirectory(
        search: _search,
        filter: _filter,
        categoryId: widget.categoryId,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        final known = _shops.map((s) => s['id']).toSet();
        _shops.addAll(result.shops.where((s) => !known.contains(s['id'])));
        _page = result.page;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      // On n'insiste pas en boucle : la pagination reprendra au
      // prochain rafraîchissement (tirer vers le bas).
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
      AppToast.show(
        context,
        message: 'Impossible de charger plus de boutiques',
        type: ToastType.error,
      );
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _applySearch(value);
    });
    // Affiche / masque la croix d'effacement.
    setState(() {});
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (!mounted || q == _search) return;
    _search = q;
    _restart();
  }

  void _clearSearch() {
    _searchController.clear();
    _applySearch('');
    setState(() {});
  }

  void _selectFilter(String key) {
    if (key == _filter) return;
    setState(() => _filter = key);
    _restart();
  }

  // ── Actions ───────────────────────────────────────────────────────

  Future<void> _toggleFollow(Map<String, dynamic> shop) async {
    final id = (shop['id'] ?? '').toString();
    if (id.isEmpty || _followBusy.contains(id)) return;

    final isLoggedIn = await NestAuthService.instance
        .isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!mounted) return;
    if (!isLoggedIn) {
      AppToast.show(
        context,
        message: 'Connectez-vous pour suivre cette boutique',
        type: ToastType.info,
      );
      return;
    }

    final wasFollowing = shop['isFollowing'] == true;
    // Mise à jour optimiste : le bouton bascule tout de suite.
    setState(() {
      _followBusy.add(id);
      shop['isFollowing'] = !wasFollowing;
    });

    try {
      final following =
          await ShopsService.instance.setFollowing(id, !wasFollowing);
      if (!mounted) return;
      setState(() => shop['isFollowing'] = following);
    } catch (e) {
      if (!mounted) return;
      // Retour arrière.
      setState(() => shop['isFollowing'] = wasFollowing);
      AppToast.show(
        context,
        message: ShopsService.errorMessage(
          e,
          wasFollowing
              ? 'Impossible de ne plus suivre cette boutique'
              : 'Impossible de suivre cette boutique',
        ),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _followBusy.remove(id));
    }
  }

  void _openShop(Map<String, dynamic> shop) {
    final name = (shop['shopName'] ?? 'Boutique').toString();
    // Mêmes clés que « Boutiques suivies » : BoutiqueVendeurScreen lit
    // 'id' (String) pour charger /vendors/:id/public, le reste sert de
    // repli si ce chargement échoue.
    Navigator.pushNamed(
      context,
      AppRoutes.boutiqueVendeur,
      arguments: <String, dynamic>{
        'id': (shop['id'] ?? '').toString(),
        'name': name,
        'logo': shop['logoUrl'],
        'logoSemanticLabel': 'Logo de la boutique $name',
        'location': shop['zone'],
        'is_verified': shop['isVerified'] == true,
        'isOnline': shop['isOnline'] == true,
      },
    );
  }

  void _openProduct(Map<String, dynamic> product) {
    // La fiche produit recharge le produit complet à partir de 'id'
    // (comme les liens profonds) ; nom et image servent d'aperçu.
    Navigator.pushNamed(
      context,
      AppRoutes.productDetail,
      arguments: <String, dynamic>{
        'id': (product['id'] ?? '').toString(),
        'name': (product['name'] ?? '').toString(),
        'imageUrl': (product['imageUrl'] ?? '').toString(),
      },
    );
  }

  // ── Construction ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildSearchField(),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _buildFilters(),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _line,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, size: 20, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: _applySearch,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.outfit(
                fontSize: 14.5,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher une boutique',
                hintStyle: GoogleFonts.outfit(
                  fontSize: 14.5,
                  color: AppTheme.muted,
                ),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = _filters[index];
          final selected = f.key == _filter;
          return GestureDetector(
            onTap: () => _selectFilter(f.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppTheme.textPrimary : _line,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                f.label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildSkeleton();

    if (_needsLogin) {
      return _buildScrollableFill(
        _StateMessage(
          icon: Icons.lock_outline_rounded,
          title: 'Connexion requise',
          description: 'Connectez-vous pour découvrir les boutiques d\'Asoukaa',
          actionLabel: 'Se connecter',
          actionIcon: Icons.login_rounded,
          onAction: () async {
            await Navigator.pushNamed(context, AppRoutes.signUpLogin);
            if (mounted) _load();
          },
        ),
      );
    }

    if (_error != null && _shops.isEmpty) {
      return _buildScrollableFill(
        _StateMessage(
          icon: Icons.wifi_off_rounded,
          title: 'Erreur de chargement',
          description: _error!,
          actionLabel: 'Réessayer',
          actionIcon: Icons.refresh_rounded,
          onAction: _load,
        ),
      );
    }

    if (_shops.isEmpty) {
      final filtered = _search.isNotEmpty || _filter != 'all';
      return _buildScrollableFill(
        _StateMessage(
          icon: Icons.storefront_outlined,
          title: filtered ? 'Aucune boutique trouvée' : 'Aucune boutique pour le moment',
          description: filtered
              ? 'Essayez un autre nom ou un autre filtre'
              : 'Les boutiques apparaîtront ici dès leur ouverture',
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _shops.length + (_isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            thickness: 1,
            color: _line,
          ),
          itemBuilder: (context, index) {
            if (index >= _shops.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              );
            }
            final shop = _shops[index];
            final id = (shop['id'] ?? '').toString();
            return _ShopCard(
              key: ValueKey('shop-$id'),
              shop: shop,
              followBusy: _followBusy.contains(id),
              onOpen: () => _openShop(shop),
              onToggleFollow: () => _toggleFollow(shop),
              onProductTap: _openProduct,
            );
          },
        ),
      ),
    );
  }

  // Permet le pull-to-refresh même quand il n'y a rien à afficher.
  Widget _buildScrollableFill(Widget child) {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget box(double? w, double? h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: _line,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, thickness: 1, color: _line),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                box(56, 56, 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(140, 14, 6),
                      const SizedBox(height: 8),
                      box(90, 11, 6),
                    ],
                  ),
                ),
                box(84, 40, 20),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: AspectRatio(aspectRatio: 1, child: box(null, null, 8))),
                const SizedBox(width: 8),
                Expanded(child: AspectRatio(aspectRatio: 1, child: box(null, null, 8))),
                const SizedBox(width: 8),
                Expanded(child: AspectRatio(aspectRatio: 1, child: box(null, null, 8))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Carte boutique ──────────────────────────────────────────────────

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    super.key,
    required this.shop,
    required this.followBusy,
    required this.onOpen,
    required this.onToggleFollow,
    required this.onProductTap,
  });

  final Map<String, dynamic> shop;
  final bool followBusy;
  final VoidCallback onOpen;
  final VoidCallback onToggleFollow;
  final void Function(Map<String, dynamic>) onProductTap;

  static String _formatRating(double rating) =>
      rating.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final name = (shop['shopName'] ?? 'Boutique').toString();
    final logo = (shop['logoUrl'] ?? '').toString();
    final zone = (shop['zone'] ?? '').toString();
    final isVerified = shop['isVerified'] == true;
    final rating = shop['rating'] is num ? (shop['rating'] as num).toDouble() : null;
    final reviewCount = shop['reviewCount'] is int ? shop['reviewCount'] as int : 0;
    final isFollowing = shop['isFollowing'] == true;
    final previews = (shop['previewProducts'] is List)
        ? (shop['previewProducts'] as List)
            .whereType<Map<String, dynamic>>()
            .take(3)
            .toList()
        : <Map<String, dynamic>>[];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onOpen,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      _ShopLogo(name: name, logoUrl: logo),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified_user_rounded,
                                    size: 13,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Vérifiée',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: AppTheme.muted,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    zone.isNotEmpty
                                        ? zone
                                        : 'Localisation non précisée',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (rating != null) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 15,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      reviewCount > 0
                                          ? '${_formatRating(rating)} sur 5 ($reviewCount avis)'
                                          : '${_formatRating(rating)} sur 5',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _FollowButton(
                isFollowing: isFollowing,
                busy: followBusy,
                onTap: onToggleFollow,
              ),
            ],
          ),
          if (previews.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: i < previews.length
                        ? _PreviewThumb(
                            product: previews[i],
                            onTap: () => onProductTap(previews[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopLogo extends StatelessWidget {
  const _ShopLogo({required this.name, required this.logoUrl});

  final String name;
  final String logoUrl;

  Widget _initialBox() {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty
        ? String.fromCharCode(trimmed.runes.first).toUpperCase()
        : 'B';
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      color: AppTheme.primaryMuted,
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl.startsWith('http');
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasLogo
            ? CustomImageWidget(
                imageUrl: logoUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                semanticLabel: 'Logo de la boutique $name',
                errorWidget: _initialBox(),
              )
            : _initialBox(),
      ),
    );
  }
}

class _PreviewThumb extends StatelessWidget {
  const _PreviewThumb({required this.product, required this.onTap});

  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = (product['imageUrl'] ?? '').toString();
    final name = (product['name'] ?? '').toString();
    final placeholder = Container(
      color: const Color(0xFFF0ECE8),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 22,
        color: AppTheme.muted,
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url.startsWith('http')
              ? CustomImageWidget(
                  imageUrl: url,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  semanticLabel: name.isNotEmpty ? name : 'Produit de la boutique',
                  errorWidget: placeholder,
                )
              : placeholder,
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.isFollowing,
    required this.busy,
    required this.onTap,
  });

  final bool isFollowing;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isFollowing ? AppTheme.primary : AppTheme.textPrimary;
    return Semantics(
      button: true,
      label: isFollowing ? 'Ne plus suivre la boutique' : 'Suivre la boutique',
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isFollowing ? AppTheme.primaryMuted : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFollowing ? AppTheme.primary : AppTheme.textPrimary,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFollowing) ...[
                Icon(Icons.check_rounded, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                isFollowing ? 'Suivi' : 'Suivre',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── États vide / erreur / connexion ─────────────────────────────────

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 34, color: AppTheme.primary),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              color: AppTheme.muted,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  textStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
