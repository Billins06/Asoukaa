import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/token_storage_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/app_toast.dart';
import '../../utils/price_range.dart';
import '../../utils/last_seen_format.dart';

class BoutiqueVendeurScreen extends StatefulWidget {
  final Map<String, dynamic>? shopData;

  const BoutiqueVendeurScreen({super.key, this.shopData});

  @override
  State<BoutiqueVendeurScreen> createState() => _BoutiqueVendeurScreenState();
}

class _BoutiqueVendeurScreenState extends State<BoutiqueVendeurScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Abonnement réel (table shop_follows côté serveur) — voir
  // _toggleFollow et POST/DELETE /api/v1/vendors/:id/follow.
  bool _isFollowing = false;
  bool _followBusy = false;
  // true si l'utilisateur connecté est le propriétaire de la boutique :
  // on ne peut pas suivre sa propre boutique (le serveur renvoie 400).
  bool _isOwnShop = false;
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

  // Partage natif (WhatsApp, SMS, etc.) : nom + description + lien profond
  // asoukaa://shop?id=... (ouvre directement la boutique chez qui a déjà
  // l'app ; sans l'app, le lien ne fait rien pour l'instant, pas de page
  // web de secours — même limite que le partage produit).
  void _shareShop() {
    final name = (_shop['name'] as String? ?? '').trim();
    final description = (_shop['description'] as String? ?? '').trim();
    final shopId = (_shop['id'] as String? ?? '').toString();

    final buffer = StringBuffer();
    buffer.writeln('Découvre cette boutique sur Asoukaa :');
    buffer.writeln(name.isNotEmpty ? name : 'Boutique Asoukaa');
    if (description.isNotEmpty) {
      buffer.writeln(description);
    }
    if (shopId.isNotEmpty) {
      buffer.writeln('asoukaa://shop?id=$shopId');
    }

    Share.share(
      buffer.toString().trim(),
      subject: name.isNotEmpty ? name : 'Boutique Asoukaa',
    );
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
      // La présence (En ligne / Vu à …) n'est fiable que si elle vient du
      // serveur (GET /vendors/:id/public), pas des données de repli.
      var presenceFromServer = false;

      // '/api/v1/shops/...' ne correspondait à AUCUNE route côté serveur
      // (404 silencieux) — c'est maintenant '/api/v1/vendors/:id/public',
      // qui renvoie les vraies infos boutique et incrémente au passage le
      // compteur de visites réel (voir vendors.service.ts → getPublicShop).
      if (shopId != null && shopId.isNotEmpty) {
        try {
          final r =
              await ApiService.instance.client.get('/api/v1/vendors/$shopId/public');
          shopResult = Map<String, dynamic>.from(r.data as Map);
          presenceFromServer = true;
        } catch (_) {}
      } else if (ownerId != null && ownerId.isNotEmpty) {
        // Pas d'équivalent "par owner" pour l'instant côté serveur : on se
        // rabat sur les données déjà en mémoire (widget.shopData) plus bas.
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
            // Le backend attend 'vendorId' (anglais) — 'vendeurId' (français)
            // était silencieusement ignoré, d'où la liste vide.
            queryParameters: {'vendorId': resolvedShopId, 'limit': '100'},
          );
          final raw = r.data;
          final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
          products = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}

        try {
          // '/api/v1/shops/:id/reviews' n'existait pas côté serveur (même
          // famille de routes fantômes que pour la boutique elle-même) —
          // c'est maintenant '/api/v1/reviews/shop/:vendorId'.
          final r = await ApiService.instance.client.get('/api/v1/reviews/shop/$resolvedShopId');
          final raw = r.data;
          final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
          reviews = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }

      // État d'abonnement initial : 'isFollowing' est renvoyé par
      // GET /vendors/:id/public pour l'utilisateur connecté (absent dans
      // le repli widget.shopData => false).
      final normalizedShop = _normalizeShop(shopResult);
      normalizedShop['presenceKnown'] = presenceFromServer;
      final isFollowing = shopResult['isFollowing'] == true;
      String? currentUserId;
      try {
        currentUserId = await TokenStorageService.instance.getUserId();
      } catch (_) {}
      final ownerIdResolved = (normalizedShop['owner_id'] ?? '').toString();
      final isOwnShop = currentUserId != null &&
          currentUserId.isNotEmpty &&
          ownerIdResolved.isNotEmpty &&
          currentUserId == ownerIdResolved;

      if (mounted) {
        setState(() {
          _shop = normalizedShop;
          _isFollowing = isFollowing;
          _isOwnShop = isOwnShop;
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
    // Le serveur (GET /vendors/:id/public) renvoie du camelCase
    // (shopName, logoUrl, bannerUrl, createdAt, visitCount...), comme
    // partout ailleurs dans ce backend. Les clés snake_case restent en
    // repli pour le cas où on retombe sur les données déjà en mémoire
    // (widget.shopData, transmises par la fiche produit).
    final name = s['shopName'] ?? s['name'] ?? 'Boutique';
    // Vraies statistiques renvoyées par GET /vendors/:id/public dans
    // 'stats' (VendorsService.getShopStats) : salesCount (commandes
    // livrées), productsCount (produits publiés), rating / reviewsCount /
    // ratingBreakdown (avis approuvés). Donnée absente => 0, jamais un
    // chiffre inventé (l'ancien repli 4.5 affichait une fausse note).
    final stats = s['stats'] is Map
        ? Map<String, dynamic>.from(s['stats'] as Map)
        : const <String, dynamic>{};
    int asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final breakdownRaw = stats['ratingBreakdown'];
    final ratingBreakdown = <int, int>{
      for (var star = 1; star <= 5; star++)
        star: breakdownRaw is Map ? asInt(breakdownRaw['$star']) : 0,
    };
    final createdAtRaw = (s['createdAt'] ?? s['created_at'])?.toString();
    final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;
    return {
      'id': s['id'] ?? '',
      'name': name,
      'description': s['description'] ?? '',
      // Categories choisies par le vendeur (etiquettes) ; sinon on retombe
      // sur l'ancien texte libre activityType.
      'categoryNames': s['categories'] is List
          ? (s['categories'] as List)
              .whereType<Map>()
              .map((c) => (c['name'] ?? '').toString().trim())
              .where((n) => n.isNotEmpty)
              .toList()
          : <String>[],
      'activityType': (s['activityType'] ?? '').toString().trim(),
      'logo':
          s['logoUrl'] ??
          s['logo_url'] ??
          s['logo'] ??
          'https://images.pexels.com/photos/3622608/pexels-photo-3622608.jpeg',
      'logoSemanticLabel': 'Logo de la boutique $name',
      'banner':
          s['bannerUrl'] ??
          s['banner_url'] ??
          s['banner'] ??
          'https://images.pexels.com/photos/6153354/pexels-photo-6153354.jpeg',
      'bannerSemanticLabel': 'Bannière de la boutique $name',
      'rating':
          double.tryParse((stats['rating'] ?? s['rating'])?.toString() ?? '') ?? 0.0,
      'reviewCount': asInt(stats['reviewsCount'] ?? s['review_count']),
      'salesCount': asInt(stats['salesCount'] ?? s['salesCount'] ?? s['sales_count']),
      // Nombre réel d'abonnés (table shop_follows, stats.followersCount).
      'followersCount': asInt(stats['followersCount']),
      // Vrai nombre de produits publiés.
      // null => stats absentes (repli widget.shopData) : on retombera sur
      // la liste de produits réellement chargée.
      'productsCount':
          stats.containsKey('productsCount') ? asInt(stats['productsCount']) : null,
      'ratingBreakdown': ratingBreakdown,
      'visitCount': s['visitCount'] as int? ?? 0,
      'location': [s['shopAddress'], s['location'], s['city']]
              .map((v) => (v ?? '').toString().trim())
              .firstWhere((v) => v.isNotEmpty,
                  orElse: () => 'Localisation non précisée'),
      // /vendors/:id/public ne renvoie que des boutiques approuvées
      // ('status' = 'approuvé') — même règle que le badge "Vérifié" du
      // profil vendeur.
      'isVerified': s['status'] == 'approuvé' || s['is_verified'] == true,
      // Présence réelle du vendeur (calculée par le serveur).
      'isOnline': s['isOnline'] == true,
      'lastSeenAt': s['lastSeenAt'] is String ? s['lastSeenAt'] : null,
      'memberSince': createdAt != null ? createdAt.year.toString() : '',
      // Aucun temps de réponse réel n'est calculé côté serveur : l'ancien
      // "< 2h" était inventé. null => la mention est masquée.
      'responseTime': null,
      // ownerId (nouveau, renvoyé par /vendors/:id/public) = id utilisateur
      // du vendeur, nécessaire pour le bouton "Message". owner_id reste en
      // repli pour widget.shopData.
      'owner_id': s['ownerId'] ?? s['owner_id'] ?? '',
    };
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    // Le serveur (GET /api/v1/products) renvoie l'entité Product brute :
    // 'prod_name' (pas 'name'), 'basePrice' (decimal -> arrive souvent en
    // chaîne), 'noteMoyenne' (note), 'totalVentes' (ventes), 'vendorId',
    // et images[].url. Il n'existe aucun champ 'original_price' côté
    // serveur pour l'instant -> pas de fausse réduction inventée.
    final images = p['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map) {
        imageUrl = (first['url'] ?? first['imageUrl'] ?? '').toString();
      } else if (first is String) {
        imageUrl = first;
      }
    }
    if (imageUrl.isEmpty) {
      imageUrl =
          'https://images.pexels.com/photos/5632399/pexels-photo-5632399.jpeg';
    }

    final variants = p['variants'] as List? ?? [];
    final firstVariant = variants.isNotEmpty ? (variants.first as Map?) : null;
    final rawPrice = p['basePrice'] ?? p['price'] ?? firstVariant?['price'];
    final price = (double.tryParse(rawPrice?.toString() ?? '') ?? 0).round();

    final name = (p['prod_name'] ?? p['name'] ?? '').toString();

    return {
      'id': p['id'] ?? '',
      'name': name,
      'price': price,
      // Paliers dégressifs bruts, conservés pour que la carte affiche la
      // fourchette « meilleur palier – prix normal » (priceRangeLabel).
      'tierPrices':
          p['tierPrices'] ?? p['price_tiers'] ?? p['priceTiers'],
      'originalPrice': price,
      'rating': double.tryParse(p['noteMoyenne']?.toString() ?? '') ?? 0.0,
      'sales': int.tryParse(p['totalVentes']?.toString() ?? '') ?? 0,
      'image': imageUrl,
      'semanticLabel': 'Produit $name de la boutique',
      'shop_id': p['vendorId'] ?? '',
      'seller_id': p['vendorId'] ?? '',
    };
  }

  Map<String, dynamic> _normalizeReview(Map<String, dynamic> r) {
    // Le serveur (GET /api/v1/reviews/shop/:vendorId) renvoie l'entité
    // Review réelle : 'user' (id, prenom, name — pas d'avatar exposé),
    // 'product' (id, prod_name), 'notation' (pas 'rating'), 'createdAt'
    // en camelCase.
    final user = r['user'] as Map<String, dynamic>?;
    final product = r['product'] as Map<String, dynamic>?;
    final createdAt = r['createdAt'] as String?;
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
    final authorName = (user?['prenom'] ?? user?['name'] ?? '').toString().trim();
    return {
      'author': authorName.isNotEmpty ? authorName : 'Client',
      'avatar': 'https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg',
      'rating': int.tryParse(r['notation']?.toString() ?? '') ?? 5,
      'comment': r['comment'] as String? ?? '',
      'date': dateStr,
      'product': product?['prod_name'] as String? ?? '',
    };
  }

  // Suivre / ne plus suivre la boutique : UI optimiste (bouton et
  // compteur basculent tout de suite), puis rollback si le serveur refuse.
  Future<void> _toggleFollow() async {
    if (_followBusy || _isOwnShop) return;
    final shopId = (_shop['id'] ?? '').toString();
    if (shopId.isEmpty) return;

    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
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

    final wasFollowing = _isFollowing;
    final previousCount = _shop['followersCount'] as int? ?? 0;
    final optimisticCount = previousCount + (wasFollowing ? -1 : 1);
    setState(() {
      _followBusy = true;
      _isFollowing = !wasFollowing;
      _shop['followersCount'] = optimisticCount < 0 ? 0 : optimisticCount;
    });

    try {
      final client = ApiService.instance.client;
      final path = '/api/v1/vendors/$shopId/follow';
      final r = wasFollowing ? await client.delete(path) : await client.post(path);
      final data = r.data is Map
          ? Map<String, dynamic>.from(r.data as Map)
          : const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _isFollowing = data['following'] is bool
            ? data['following'] as bool
            : !wasFollowing;
        final serverCount = int.tryParse(data['followersCount']?.toString() ?? '');
        if (serverCount != null) _shop['followersCount'] = serverCount;
      });
      AppToast.show(
        context,
        message: wasFollowing
            ? 'Vous ne suivez plus cette boutique'
            : 'Vous suivez maintenant cette boutique',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      // Rollback de l'état optimiste
      setState(() {
        _isFollowing = wasFollowing;
        _shop['followersCount'] = previousCount;
      });
      String message = wasFollowing
          ? 'Impossible de ne plus suivre cette boutique'
          : 'Impossible de suivre cette boutique';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final msg = body['message'];
          if (msg is String && msg.isNotEmpty) {
            message = msg;
          } else if (msg is List && msg.isNotEmpty) {
            message = msg.first.toString();
          }
        }
      }
      AppToast.show(context, message: message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
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
    // L'API de conversation attend l'ID de la BOUTIQUE (VendorProfile.id,
    // meme valeur que _shop['id']), pas l'ID utilisateur du vendeur
    // (owner_id) -- voir ChatService.createConversation cote serveur, qui
    // fait vendorRepo.findOne({ where: { id: dto.vendorId } }).
    final shopId = _shop['id'] as String? ?? '';
    if (shopId.isEmpty) return;

    try {
      // Route reelle : /chat/conversations (pas /conversations -- 404
      // systematique avant ce correctif, d'ou "Impossible d'ouvrir la
      // conversation" au clic). Champ attendu : vendorId.
      final r = await ApiService.instance.client.post(
        '/api/v1/chat/conversations',
        data: {'vendorId': shopId},
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
          onPressed: _shareShop,
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
                          ],
                        ),
                        if (_shop['presenceKnown'] == true) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _shop['isOnline'] == true
                                      ? AppTheme.success
                                      : AppTheme.muted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  formatLastSeen(
                                    _shop['lastSeenAt'] as String?,
                                    isOnline: _shop['isOnline'] == true,
                                  ),
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _shop['isOnline'] == true
                                        ? AppTheme.success
                                        : AppTheme.muted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
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
            if ((_shop['categoryNames'] as List?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (_shop['categoryNames'] as List)
                    .map((n) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEDE3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            n.toString(),
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ] else if ((_shop['activityType'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _shop['activityType'] as String,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Wrap (et non Row) : 4 chips tiennent sur une ligne sur la
            // plupart des écrans, et passent proprement à la ligne sur un
            // écran étroit (360dp) au lieu de déborder.
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _buildStatChip(
                  Icons.star_rounded,
                  '${_shop['rating']}',
                  '(${_formatCount(_shop['reviewCount'] as int)} avis)',
                  AppTheme.warning,
                ),
                _buildStatChip(
                  Icons.shopping_bag_outlined,
                  _formatCount(_shop['salesCount'] as int),
                  'ventes',
                  AppTheme.primary,
                ),
                _buildStatChip(
                  Icons.people_outline_rounded,
                  _formatCount(_shop['followersCount'] as int? ?? 0),
                  'abonnés',
                  AppTheme.primary,
                ),
                _buildStatChip(
                  Icons.inventory_2_outlined,
                  _formatCount(
                    (_shop['productsCount'] as int?) ?? _products.length,
                  ),
                  'produits',
                  AppTheme.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _isOwnShop
                      ? Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.outline),
                          ),
                          child: Center(
                            child: Text(
                              'Votre boutique',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.muted,
                              ),
                            ),
                          ),
                        )
                      : GestureDetector(
                    onTap: _toggleFollow,
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
                          _isFollowing ? 'Abonné(e) ✓' : 'Suivre la boutique',
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
                if (_shop['responseTime'] != null) ...[
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
                ],
                if ((_shop['memberSince'] as String? ?? '').isNotEmpty) ...[
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
                    // « 25 – 39 FCFA » quand un palier dégressif existe,
                    // sinon le prix normal seul.
                    priceRangeLabel(product),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    // Répartition réelle des notes (stats.ratingBreakdown) au lieu des
    // pourcentages figés 72/18/6/3/1 %.
    final breakdown =
        (_shop['ratingBreakdown'] as Map<int, int>?) ?? const <int, int>{};
    final totalReviews = breakdown.values.fold<int>(0, (a, b) => a + b);
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
                final pct = totalReviews > 0
                    ? (breakdown[star] ?? 0) / totalReviews
                    : 0.0;
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
