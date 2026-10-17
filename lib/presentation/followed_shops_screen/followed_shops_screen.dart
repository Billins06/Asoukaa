import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/custom_image_widget.dart';
import '../../widgets/empty_state_widget.dart';

// "Boutiques suivies" (côté acheteur) : liste des boutiques que
// l'utilisateur connecté suit — GET /api/v1/vendors/me/following
// (paginé : { data, total, page, limit, pages }). Balayer vers la gauche
// ou toucher l'icône pour ne plus suivre (DELETE /vendors/:id/follow).
class FollowedShopsScreen extends StatefulWidget {
  const FollowedShopsScreen({super.key});

  @override
  State<FollowedShopsScreen> createState() => _FollowedShopsScreenState();
}

class _FollowedShopsScreenState extends State<FollowedShopsScreen> {
  static const int _pageSize = 20;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _notLoggedIn = false;
  String? _error;
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  List<Map<String, dynamic>> _shops = [];
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetchPage(int page) async {
    final r = await ApiService.instance.client.get(
      '/api/v1/vendors/me/following',
      queryParameters: {'page': page, 'limit': _pageSize},
    );
    final raw = r.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _parseList(Map<String, dynamic> body) {
    final list = body['data'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _shops.isEmpty;
      _error = null;
    });

    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!mounted) return;
    if (!isLoggedIn) {
      setState(() {
        _notLoggedIn = true;
        _isLoading = false;
        _shops = [];
      });
      return;
    }

    try {
      final body = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        _notLoggedIn = false;
        _shops = _parseList(body);
        _page = 1;
        _pages = int.tryParse(body['pages']?.toString() ?? '') ?? 1;
        _total = int.tryParse(body['total']?.toString() ?? '') ?? _shops.length;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message =
          _extractMessage(e, 'Impossible de charger vos boutiques suivies');
      setState(() {
        _isLoading = false;
        _error = message;
      });
      // Liste déjà affichée (pull-to-refresh) : on la garde et on prévient.
      if (_shops.isNotEmpty) {
        AppToast.show(context, message: message, type: ToastType.error);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || _page >= _pages) return;
    setState(() => _isLoadingMore = true);
    try {
      final body = await _fetchPage(_page + 1);
      if (!mounted) return;
      final more = _parseList(body);
      setState(() {
        final knownIds = _shops.map((s) => s['id']).toSet();
        _shops.addAll(more.where((s) => !knownIds.contains(s['id'])));
        _page += 1;
        _pages = int.tryParse(body['pages']?.toString() ?? '') ?? _pages;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  String _extractMessage(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    }
    return fallback;
  }

  // Appel DELETE uniquement (la liste est mise à jour par l'appelant) :
  // renvoie true si le désabonnement a réussi.
  Future<bool> _unfollowRequest(Map<String, dynamic> shop) async {
    final id = (shop['id'] ?? '').toString();
    if (id.isEmpty || _removing.contains(id)) return false;
    setState(() => _removing.add(id));
    try {
      await ApiService.instance.client.delete('/api/v1/vendors/$id/follow');
      if (!mounted) return true;
      AppToast.show(
        context,
        message: 'Vous ne suivez plus ${shop['shopName'] ?? 'cette boutique'}',
        type: ToastType.success,
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      AppToast.show(
        context,
        message: _extractMessage(e, 'Impossible de ne plus suivre cette boutique'),
        type: ToastType.error,
      );
      return false;
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  void _removeLocally(Map<String, dynamic> shop) {
    setState(() {
      _shops.removeWhere((s) => s['id'] == shop['id']);
      if (_total > 0) _total -= 1;
    });
  }

  Future<void> _unfollowFromButton(Map<String, dynamic> shop) async {
    final ok = await _unfollowRequest(shop);
    if (ok && mounted) _removeLocally(shop);
  }

  void _openShop(Map<String, dynamic> shop) {
    final name = (shop['shopName'] ?? 'Boutique').toString();
    Navigator.pushNamed(
      context,
      AppRoutes.boutiqueVendeur,
      arguments: {
        'id': shop['id'],
        'name': name,
        'logo': shop['logoUrl'],
        'logoSemanticLabel': 'Logo de la boutique $name',
        'banner': shop['bannerUrl'],
        'location': shop['shopAddress'],
      },
    ).then((_) {
      // L'utilisateur a pu se désabonner depuis la page boutique.
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Boutiques suivies',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_total boutique${_total > 1 ? 's' : ''}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_notLoggedIn) {
      return EmptyStateWidget(
        icon: Icons.lock_outline_rounded,
        title: 'Connexion requise',
        description: 'Connectez-vous pour voir les boutiques que vous suivez',
        ctaLabel: 'Se connecter',
        onCtaTap: () => Navigator.pushNamed(context, AppRoutes.signUpLogin),
      );
    }

    if (_error != null && _shops.isEmpty) {
      return _buildScrollableFill(
        EmptyStateWidget(
          icon: Icons.wifi_off_rounded,
          title: 'Erreur de chargement',
          description: _error!,
          ctaLabel: 'Réessayer',
          onCtaTap: _load,
        ),
      );
    }

    if (_shops.isEmpty) {
      return _buildScrollableFill(
        EmptyStateWidget(
          icon: Icons.storefront_outlined,
          title: 'Vous ne suivez encore aucune boutique',
          description:
              'Touchez « Suivre la boutique » sur la page d\'une boutique pour la retrouver ici',
          ctaLabel: 'Explorer les produits',
          onCtaTap: () => Navigator.pushNamed(context, AppRoutes.home),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _shops.length + (_isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index >= _shops.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
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
            return Dismissible(
              key: ValueKey('followed-shop-$id'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _unfollowRequest(shop),
              onDismissed: (_) => _removeLocally(shop),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ne plus suivre',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.person_remove_outlined,
                      color: AppTheme.error,
                      size: 20,
                    ),
                  ],
                ),
              ),
              child: _buildShopCard(shop, id),
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
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(Map<String, dynamic> shop, String id) {
    final name = (shop['shopName'] ?? 'Boutique').toString();
    final logo = (shop['logoUrl'] ?? '').toString();
    final address = (shop['shopAddress'] ?? '').toString().trim();
    final isRemoving = _removing.contains(id);

    return GestureDetector(
      onTap: () => _openShop(shop),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: logo.isNotEmpty
                    ? CustomImageWidget(
                        imageUrl: logo,
                        fit: BoxFit.cover,
                        semanticLabel: 'Logo de la boutique $name',
                      )
                    : Container(
                        color: AppTheme.primaryMuted,
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          address.isNotEmpty
                              ? address
                              : 'Localisation non précisée',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            isRemoving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Ne plus suivre',
                    icon: const Icon(
                      Icons.person_remove_outlined,
                      size: 20,
                    ),
                    color: AppTheme.muted,
                    onPressed: () => _unfollowFromButton(shop),
                  ),
          ],
        ),
      ),
    );
  }
}
