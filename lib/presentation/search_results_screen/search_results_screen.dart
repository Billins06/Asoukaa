import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/connection_error_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';

class SearchResultsScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchResultsScreen({super.key, this.initialQuery});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late AnimationController _filterPanelController;
  late Animation<double> _filterPanelAnim;

  bool _showFilters = false;
  final bool _brandExpanded = false;
  final bool _sizeExpanded = false;
  final bool _colorExpanded = false;
  String _selectedSort = 'Popularité';
  String _selectedCategory = 'Tout';
  String _selectedBrand = 'Tout';
  String _selectedSize = 'Tout';
  String _selectedColor = 'Tout';
  RangeValues _priceRange = const RangeValues(0, 200000);
  double _minRating = 0;
  bool _isLoading = true;
  bool _hasConnectionError = false;
  bool _isOfflineCached = false;
  final ConnectivityService _connectivityService = ConnectivityService();

  // Real data from Supabase
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  static const List<String> _sortOptions = [
    'Nouveauté',
    'Popularité',
    'Promotion',
  ];

  static const List<String> _categories = [
    'Tout',
    'Mode',
    'Électronique',
    'Maison',
    'Beauté',
    'Alimentation',
    'Sport',
    'Artisanat',
  ];

  static const List<String> _brands = [
    'Tout',
    'Samsung',
    'Infinix',
    'JBL',
    'Nature Bio',
    'Artisanal',
    'Autre',
  ];
  static const List<String> _sizes = [
    'Tout',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    'Unique',
  ];
  static const List<Map<String, dynamic>> _colors = [
    {'label': 'Tout', 'color': null},
    {'label': 'Rouge', 'color': Color(0xFFDC2626)},
    {'label': 'Bleu', 'color': Color(0xFF3B82F6)},
    {'label': 'Vert', 'color': Color(0xFF16A34A)},
    {'label': 'Noir', 'color': Color(0xFF1A1A1A)},
    {'label': 'Blanc', 'color': Color(0xFFF5F5F5)},
    {'label': 'Jaune', 'color': Color(0xFFD97706)},
    {'label': 'Orange', 'color': Color(0xFFFF6210)},
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _filterPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _filterPanelAnim = CurvedAnimation(
      parent: _filterPanelController,
      curve: Curves.easeOutCubic,
    );
    _loadData();
    _connectivityService.onConnectivityChanged.listen((results) {
      final isOnline =
          !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (isOnline && (_hasConnectionError || _isOfflineCached)) _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasConnectionError = false;
    });
    final offline = await _connectivityService.isOffline();
    if (offline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOfflineCached = true;
        });
      }
      return;
    }
    try {
      await _searchProducts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasConnectionError = true;
        });
      }
    }
  }

  Future<void> _searchProducts() async {
    try {
      final query = _searchController.text.trim();
      var dbQuery = Supabase.instance.client
          .from('products')
          .select('*, shops(id, name, logo_url)')
          .eq('is_active', true);

      if (query.isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%$query%');
      }
      if (_selectedCategory != 'Tout') {
        dbQuery = dbQuery.eq('category', _selectedCategory);
      }

      final result = await dbQuery
          .order('created_at', ascending: false)
          .limit(100);

      final products = List<Map<String, dynamic>>.from(
        result as List,
      ).map(_normalizeProduct).toList();

      if (mounted) {
        setState(() {
          _allProducts = products;
          _applyFilters();
          _isLoading = false;
          _isOfflineCached = false;
          _hasConnectionError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasConnectionError = true;
        });
      }
    }
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    final shopData = p['shops'] as Map<String, dynamic>?;
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
    final discount = originalPrice > price
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;

    final createdAt = p['created_at'] as String?;
    final isNew = createdAt != null
        ? DateTime.now().difference(DateTime.parse(createdAt)).inDays < 14
        : false;

    return {
      'id': p['id'] ?? '',
      'name': p['name'] ?? '',
      'shop': shopData?['name'] ?? '',
      'shop_id': shopData?['id'] ?? p['shop_id'] ?? '',
      'seller_id': p['seller_id'] ?? '',
      'price': price,
      'originalPrice': originalPrice,
      'discount': discount,
      'rating': (p['rating'] as num? ?? 4.5).toDouble(),
      'reviewCount': p['review_count'] as int? ?? 0,
      'category': p['category'] ?? '',
      'brand': p['brand'] ?? 'Autre',
      'size': p['size'] ?? 'Unique',
      'color': p['color'] ?? '',
      'imageUrl': imageUrl,
      'semanticLabel':
          'Produit ${p['name'] ?? ''} de la boutique ${shopData?['name'] ?? ''}',
      'isNew': isNew,
    };
  }

  void _applyFilters() {
    var results = _allProducts.where((p) {
      final query = _searchController.text.toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          (p['name'] as String).toLowerCase().contains(query) ||
          (p['shop'] as String).toLowerCase().contains(query) ||
          (p['category'] as String).toLowerCase().contains(query);

      final matchesCategory =
          _selectedCategory == 'Tout' || p['category'] == _selectedCategory;
      final matchesBrand =
          _selectedBrand == 'Tout' || p['brand'] == _selectedBrand;
      final matchesSize = _selectedSize == 'Tout' || p['size'] == _selectedSize;
      final matchesColor =
          _selectedColor == 'Tout' || p['color'] == _selectedColor;
      final price = p['price'] as int;
      final matchesPrice =
          price >= _priceRange.start && price <= _priceRange.end;
      final rating = (p['rating'] as num).toDouble();
      final matchesRating = rating >= _minRating;

      return matchesQuery &&
          matchesCategory &&
          matchesBrand &&
          matchesSize &&
          matchesColor &&
          matchesPrice &&
          matchesRating;
    }).toList();

    switch (_selectedSort) {
      case 'Nouveauté':
        results.sort((a, b) {
          final aNew = a['isNew'] as bool? ?? false;
          final bNew = b['isNew'] as bool? ?? false;
          return bNew
              ? 1
              : aNew
              ? -1
              : 0;
        });
        break;
      case 'Popularité':
        results.sort(
          (a, b) =>
              (b['reviewCount'] as int).compareTo(a['reviewCount'] as int),
        );
        break;
      case 'Promotion':
        results.sort(
          (a, b) => (b['discount'] as int).compareTo(a['discount'] as int),
        );
        break;
    }

    _filteredProducts = results;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterPanelController.dispose();
    super.dispose();
  }

  void _toggleFilters() {
    setState(() => _showFilters = !_showFilters);
    if (_showFilters) {
      _filterPanelController.forward();
    } else {
      _filterPanelController.reverse();
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedCategory = 'Tout';
      _selectedBrand = 'Tout';
      _selectedSize = 'Tout';
      _selectedColor = 'Tout';
      _priceRange = const RangeValues(0, 200000);
      _minRating = 0;
      _applyFilters();
    });
  }

  void _onSearchSubmit(String query) {
    setState(() => _isLoading = true);
    _searchProducts();
  }

  void _onFilterChanged() {
    setState(() => _applyFilters());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            if (_showFilters) _buildFilterPanel(),
            Expanded(
              child: _isLoading
                  ? _buildLoadingGrid()
                  : _hasConnectionError
                  ? ConnectionErrorScreen(onRetry: _loadData)
                  : _isOfflineCached
                  ? _buildOfflineBanner()
                  : _filteredProducts.isEmpty
                  ? _buildEmptyState()
                  : _buildProductGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.outline),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _onSearchSubmit,
                    textInputAction: TextInputAction.search,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Rechercher des produits...',
                      hintStyle: GoogleFonts.outfit(
                        fontSize: 14,
                        color: AppTheme.muted,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.muted,
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: AppTheme.muted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchSubmit('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleFilters,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _showFilters
                        ? AppTheme.primary
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _showFilters ? AppTheme.primary : AppTheme.outline,
                    ),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: _showFilters ? Colors.white : AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._sortOptions.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedSort = s;
                          _applyFilters();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedSort == s
                              ? AppTheme.primary
                              : AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedSort == s
                                ? AppTheme.primary
                                : AppTheme.outline,
                          ),
                        ),
                        child: Text(
                          s,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _selectedSort == s
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_filteredProducts.length} résultat(s)',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return SizeTransition(
      sizeFactor: _filterPanelAnim,
      child: Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filtres',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: _resetFilters,
                  child: Text(
                    'Réinitialiser',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // Category filter
            Text(
              'Catégorie',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories
                    .map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategory = cat;
                              _applyFilters();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedCategory == cat
                                  ? AppTheme.primaryMuted
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCategory == cat
                                    ? AppTheme.primary
                                    : AppTheme.outline,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _selectedCategory == cat
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            // Price range
            Text(
              'Prix (FCFA)',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            RangeSlider(
              values: _priceRange,
              min: 0,
              max: 200000,
              divisions: 20,
              activeColor: AppTheme.primary,
              inactiveColor: AppTheme.outlineVariant,
              labels: RangeLabels(
                '${(_priceRange.start / 1000).round()}k',
                '${(_priceRange.end / 1000).round()}k',
              ),
              onChanged: (v) {
                setState(() {
                  _priceRange = v;
                  _applyFilters();
                });
              },
            ),
            // Min rating
            Text(
              'Note minimum',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            Row(
              children: [0, 3, 4, 4.5].map((r) {
                final rDouble = r.toDouble();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _minRating = rDouble;
                        _applyFilters();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _minRating == rDouble
                            ? AppTheme.primaryMuted
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _minRating == rDouble
                              ? AppTheme.primary
                              : AppTheme.outline,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (r > 0) ...[
                            const Icon(
                              Icons.star_rounded,
                              color: AppTheme.warning,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                          ],
                          Text(
                            r == 0 ? 'Tout' : '$r+',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _minRating == rDouble
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) =>
          _buildProductCard(_filteredProducts[index]),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final price = product['price'] as int;
    final originalPrice = product['originalPrice'] as int;
    final discount = product['discount'] as int;

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
                    child: CustomImageWidget(
                      imageUrl: product['imageUrl'] as String,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      semanticLabel: product['semanticLabel'] as String,
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
                  if (product['isNew'] == true)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Nouveau',
                          style: GoogleFonts.outfit(
                            fontSize: 9,
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
                  const SizedBox(height: 2),
                  Text(
                    product['shop'] as String,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppTheme.muted,
                    ),
                    maxLines: 1,
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
                        '(${product['reviewCount']})',
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

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const LoadingSkeletonWidget(
        width: double.infinity,
        height: 220,
        borderRadius: 14,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'Aucun résultat',
        description:
            'Aucun produit ne correspond à votre recherche. Essayez d\'autres mots-clés ou filtres.',
        ctaLabel: 'Réinitialiser les filtres',
        onCtaTap: _resetFilters,
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.warningContainer,
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: AppTheme.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mode hors ligne — résultats limités',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredProducts.isEmpty
              ? _buildEmptyState()
              : _buildProductGrid(),
        ),
      ],
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }
}
