import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/app_toast.dart';

class BoutiqueVendeurScreen extends StatefulWidget {
  final Map<String, dynamic>? shopData;

  const BoutiqueVendeurScreen({super.key, this.shopData});

  @override
  State<BoutiqueVendeurScreen> createState() => _BoutiqueVendeurScreenState();
}

class _BoutiqueVendeurScreenState extends State<BoutiqueVendeurScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFollowing = false;
  bool _isLoading = true;
  bool _hasError = false;

  Map<String, dynamic> _shop = {};
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShopData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      // Determine shop ID from passed data
      final shopId =
          widget.shopData?['id'] as String? ??
          widget.shopData?['shop_id'] as String?;
      final ownerId =
          widget.shopData?['owner_id'] as String? ??
          widget.shopData?['seller_id'] as String?;

      Map<String, dynamic>? shopResult;

      if (shopId != null && shopId.isNotEmpty) {
        try {
          final r = await ApiService.instance.client.get('/api/v1/shops/$shopId');
          shopResult = Map<String, dynamic>.from(r.data as Map);
        } catch (_) {}
      } else if (ownerId != null && ownerId.isNotEmpty) {
        try {
          final r = await ApiService.instance.client.get('/api/v1/shops/owner/$ownerId');
          shopResult = Map<String, dynamic>.from(r.data as Map);
        } catch (_) {}
      }

      if (shopResult == null && widget.shopData != null) {
        shopResult = widget.shopData;
      }

      if (shopResult == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      final resolvedShopId = shopResult['id'] as String? ?? shopId ?? '';

      List<Map<String, dynamic>> products = [];
      List<Map<String, dynamic>> reviews = [];

      if (resolvedShopId.isNotEmpty) {
        try {
          final r = await ApiService.instance.client.get(
            '/api/v1/products',
            queryParameters: {'vendeurId': resolvedShopId, 'limit': '100'},
          );
          final raw = r.data;
          final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
          products = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}

        try {
          final r = await ApiService.instance.client.get('/api/v1/shops/$resolvedShopId/reviews');
          final raw = r.data;
          final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
          reviews = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _shop = _normalizeShop(shopResult!);
          _products = products.map(_normalizeProduct).toList();
          _reviews = reviews.map(_normalizeReview).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Map<String, dynamic> _normalizeShop(Map<String, dynamic> s) {
    return {
      'id': s['id'] ?? '',
      'name': s['name'] ?? 'Boutique',
      'description': s['description'] ?? '',
      'logo':
          s['logo_url'] ??
          s['logo'] ??
          'https://images.pexels.com/photos/3622608/pexels-photo-3622608.jpeg',
      'logoSemanticLabel': 'Logo de la boutique ${s['name'] ?? ''}',
      'banner':
          s['banner_url'] ??
          s['banner'] ??
          'https://images.pexels.com/photos/6153354/pexels-photo-6153354.jpeg',
      'bannerSemanticLabel': 'Bannière de la boutique ${s['name'] ?? ''}',
      'rating': (s['rating'] as num? ?? 4.5).toDouble(),
      'reviewCount': s['review_count'] as int? ?? 0,
      'salesCount': s['sales_count'] as int? ?? 0,
      'followersCount': s['followers_count'] as int? ?? 0,
      'location': s['location'] ?? s['city'] ?? 'Bénin',
      'isVerified': s['is_verified'] as bool? ?? false,
      'isOnline': true,
      'memberSince': s['created_at'] != null
          ? DateTime.parse(s['created_at'] as String).year.toString()
          : '2024',
      'responseTime': '< 2h',
      'owner_id': s['owner_id'] ?? '',
    };
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    final images = p['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map) {
        imageUrl = first['url'] as String? ?? '';
      } else if (first is String)
        imageUrl = first;
    }
    if (imageUrl.isEmpty) {
      imageUrl =
          'https://images.pexels.com/photos/5632399/pexels-photo-5632399.jpeg';
    }
    final price = (p['price'] as num? ?? 0).toInt();
    final originalPrice = (p['original_price'] as num? ?? price).toInt();
    return {
      'id': p['id'] ?? '',
      'name': p['name'] ?? '',
      'price': price,
      'originalPrice': originalPrice,
      'rating': (p['rating'] as num? ?? 4.5).toDouble(),
      'sales': p['sold_count'] as int? ?? 0,
      'image': imageUrl,
      'semanticLabel': 'Produit ${p['name'] ?? ''} de la boutique',
      'shop_id': p['shop_id'] ?? '',
      'seller_id': p['seller_id'] ?? '',
    };
  }

  Map<String, dynamic> _normalizeReview(Map<String, dynamic> r) {
    final profile = r['user_profiles'] as Map<String, dynamic>?;
    final product = r['products'] as Map<String, dynamic>?;
    final createdAt = r['created_at'] as String?;
    String dateStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          dateStr = 'Aujourd\'hui';
        } else if (diff.inDays == 1)
          dateStr = 'Hier';
        else if (diff.inDays < 7)
          dateStr = 'Il y a ${diff.inDays} jours';
        else if (diff.inDays < 30)
          dateStr = 'Il y a ${(diff.inDays / 7).floor()} semaine(s)';
        else
          dateStr = 'Il y a ${(diff.inDays / 30).floor()} mois';
      }
    }
    return {
      'author': profile?['full_name'] as String? ?? 'Client',
      'avatar':
          profile?['avatar_url'] as String? ??
          'https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg',
      'rating': r['rating'] as int? ?? 5,
      'comment': r['comment'] as String? ?? '',
      'date': dateStr,
      'product': product?['name'] as String? ?? '',
    };
  }

  Future<void> _openChat() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!mounted) return;
    if (!isLoggedIn) {
      AppToast.show(
        context,
        message: 'Connectez-vous pour envoyer un message',
        type: ToastType.info,
      );
      return;
    }
    final sellerId = _shop['owner_id'] as String? ?? '';
    if (sellerId.isEmpty) return;

    try {
      final r = await ApiService.instance.client.post(
        '/api/v1/conversations',
        data: {'recipientId': sellerId},
      );
      if (!mounted) return;
      final convId = (r.data as Map)['id'] as String?;
      if (convId != null) {
        Navigator.pushNamed(
          context,
          AppRoutes.chat,
          arguments: {
            'conversation_id': convId,
            'other_user_name': _shop['name'],
            'other_user_avatar': _shop['logo'],
          },
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible d\'ouvrir la conversation',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (_hasError || _shop.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: EmptyStateWidget(
            icon: Icons.store_outlined,
            title: 'Boutique introuvable',
            description: 'Cette boutique n\'existe pas ou a été supprimée.',
            ctaLabel: 'Retour',
            onCtaTap: () => Navigator.pop(context),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(innerBoxIsScrolled),
          _buildShopInfoSliver(),
          _buildTabBarSliver(),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_buildProductsGrid(), _buildReviewsList()],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: AppTheme.surface,
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(60),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(60),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.share_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _shop['banner'] as String,
              fit: BoxFit.cover,
              semanticLabel: _shop['bannerSemanticLabel'] as String,
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.primaryMuted,
                child: const Icon(
                  Icons.store,
                  color: AppTheme.primary,
                  size: 48,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(40),
                    Colors.black.withAlpha(100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopInfoSliver() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surface, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        _shop['logo'] as String,
                        fit: BoxFit.cover,
                        semanticLabel: _shop['logoSemanticLabel'] as String,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppTheme.primaryMuted,
                          child: const Icon(
                            Icons.store,
                            color: AppTheme.primary,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _shop['name'] as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_shop['isVerified'] == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.verified_rounded,
                                  color: AppTheme.primary,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: AppTheme.muted,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _shop['location'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: AppTheme.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'En ligne',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if ((_shop['description'] as String).isNotEmpty)
              Text(
                _shop['description'] as String,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatChip(
                  Icons.star_rounded,
                  '${_shop['rating']}',
                  '(${_formatCount(_shop['reviewCount'] as int)} avis)',
                  AppTheme.warning,
                ),
                const SizedBox(width: 12),
                _buildStatChip(
                  Icons.shopping_bag_outlined,
                  _formatCount(_shop['salesCount'] as int),
                  'ventes',
                  AppTheme.primary,
                ),
                const SizedBox(width: 12),
                _buildStatChip(
                  Icons.people_outline_rounded,
                  _formatCount(_shop['followersCount'] as int),
                  'abonnés',
                  AppTheme.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isFollowing = !_isFollowing),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isFollowing
                            ? AppTheme.primaryMuted
                            : AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                        border: _isFollowing
                            ? Border.all(color: AppTheme.primary, width: 1.5)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          _isFollowing ? 'Abonné ✓' : 'Suivre la boutique',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isFollowing
                                ? AppTheme.primary
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.outline),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                    color: AppTheme.textSecondary,
                    onPressed: _openChat,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Répond généralement en ${_shop['responseTime']}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Membre depuis ${_shop['memberSince']}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
        ),
      ],
    );
  }

  Widget _buildTabBarSliver() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyTabBarDelegate(
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.muted,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          labelStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.grid_view_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('Produits (${_products.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('Avis (${_reviews.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    if (_products.isEmpty) {
      return const Center(
        child: EmptyStateWidget(
          icon: Icons.inventory_2_outlined,
          title: 'Aucun produit',
          description: 'Cette boutique n\'a pas encore de produits.',
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) => _buildProductCard(_products[index]),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final price = product['price'] as int;
    final originalPrice = product['originalPrice'] as int;
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.productDetail,
        arguments: product,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: Image.network(
                      product['image'] as String,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      semanticLabel: product['semanticLabel'] as String,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.surfaceVariant,
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppTheme.muted,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  if (discount > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-$discount%',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] as String,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppTheme.warning,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${product['rating']}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${product['sales']})',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatPrice(price)} FCFA',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  if (originalPrice > price)
                    Text(
                      '${_formatPrice(originalPrice)} FCFA',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsList() {
    if (_reviews.isEmpty) {
      return const Center(
        child: EmptyStateWidget(
          icon: Icons.star_outline_rounded,
          title: 'Aucun avis',
          description: 'Cette boutique n\'a pas encore d\'avis.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildRatingSummary(),
        const SizedBox(height: 16),
        ..._reviews.map((r) => _buildReviewCard(r)),
      ],
    );
  }

  Widget _buildRatingSummary() {
    final rating = _shop['rating'] as double;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                '$rating',
                style: GoogleFonts.outfit(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating.floor()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppTheme.warning,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatCount(_shop['reviewCount'] as int)} avis',
                style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final pct = star == 5
                    ? 0.72
                    : star == 4
                    ? 0.18
                    : star == 3
                    ? 0.06
                    : star == 2
                    ? 0.03
                    : 0.01;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$star',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.star_rounded,
                        color: AppTheme.warning,
                        size: 11,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: AppTheme.outlineVariant,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.warning,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(pct * 100).round()}%',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final rating = review['rating'] as int;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Image.network(
                  review['avatar'] as String,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo de profil de ${review['author']}',
                  errorBuilder: (_, __, ___) => Container(
                    width: 36,
                    height: 36,
                    color: AppTheme.primaryMuted,
                    child: const Icon(
                      Icons.person,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['author'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppTheme.warning,
                            size: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          review['date'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((review['product'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                review['product'] as String,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            review['comment'] as String,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  String _formatPrice(int price) {
    if (price >= 1000) {
      final s = price.toString();
      final result = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
        result.write(s[i]);
      }
      return result.toString();
    }
    return '$price';
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          tabBar,
          Container(height: 1, color: AppTheme.outlineVariant),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}
