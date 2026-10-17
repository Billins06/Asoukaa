import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../services/api_service.dart';
import '../../../routes/app_routes.dart';
import '../../../utils/lecture_json.dart';

class ProductTabsWidget extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductTabsWidget({super.key, required this.product});

  @override
  State<ProductTabsWidget> createState() => _ProductTabsWidgetState();
}

class _ProductTabsWidgetState extends State<ProductTabsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _reviews = [];
  double _avgRating = 0;
  int _reviewCount = 0;
  bool _isLoadingReviews = true;

  List<Map<String, dynamic>> _similarProducts = [];
  bool _isLoadingSimilar = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReviews();
    _loadSimilar();
  }

  Future<void> _loadReviews() async {
    final productId = (widget.product['id'] ?? '').toString();
    if (productId.isEmpty) {
      if (mounted) setState(() => _isLoadingReviews = false);
      return;
    }
    try {
      final res = await ApiService.instance.client.get(
        '/api/v1/reviews/product/$productId',
        queryParameters: {'limit': 20},
      );
      final data = res.data as Map<String, dynamic>? ?? {};
      final list = (data['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (mounted) {
        setState(() {
          _reviews = list;
          _avgRating = lireDouble(data['avgRating']);
          _reviewCount = lireInt(data['reviewCount'], list.length);
          _isLoadingReviews = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  Future<void> _loadSimilar() async {
    final categoryId = (widget.product['categoryId'] ?? '').toString();
    final currentId = (widget.product['id'] ?? '').toString();
    if (categoryId.isEmpty) {
      if (mounted) setState(() => _isLoadingSimilar = false);
      return;
    }
    try {
      final res = await ApiService.instance.client.get(
        '/api/v1/products',
        queryParameters: {'categoryId': categoryId, 'limit': 8},
      );
      final data = res.data as Map<String, dynamic>? ?? {};
      final list = (data['data'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) => (p['id'] ?? '').toString() != currentId)
          .toList();
      if (mounted) {
        setState(() {
          _similarProducts = list;
          _isLoadingSimilar = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSimilar = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFFF6210),
            unselectedLabelColor: const Color(0xFF9E9E9E),
            indicatorColor: const Color(0xFFFF6210),
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            tabs: [
              const Tab(text: 'Description'),
              Tab(text: 'Avis ($_reviewCount)'),
              const Tab(text: 'Similaires'),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDescriptionTab(),
                _buildReviewsTab(),
                _buildSimilarTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionTab() {
    final specs =
        (widget.product['specs'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final description = widget.product['description'] as String? ?? '';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'À propos du produit',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF616161),
              height: 1.6,
            ),
          ),
          if (specs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Caractéristiques',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: List.generate(specs.length, (index) {
                    final spec = specs[index];
                    final isLast = index == specs.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: index.isEven
                            ? const Color(0xFFFAF9F8)
                            : Colors.white,
                        border: !isLast
                            ? const Border(
                                bottom: BorderSide(
                                  color: Color(0xFFF0F0F0),
                                  width: 1,
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              spec['key'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              spec['value'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewsTab() {
    if (_isLoadingReviews) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFFFF6210)),
        ),
      );
    }

    if (_reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.rate_review_outlined,
                size: 40,
                color: Color(0xFFBDBDBD),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun avis pour ce produit pour le moment',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Rating breakdown calculé à partir des avis chargés
    final ratingCounts = [0, 0, 0, 0, 0, 0]; // index = stars (1..5)
    for (final r in _reviews) {
      final n = lireInt(r['notation']);
      if (n >= 1 && n <= 5) ratingCounts[n]++;
    }
    final total = ratingCounts.reduce((a, b) => a + b).toDouble();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rating summary
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(
                    _avgRating.toStringAsFixed(1),
                    style: GoogleFonts.outfit(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (i) => const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_reviewCount avis',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final stars = 5 - i;
                    final count = ratingCounts[stars];
                    final pct = total > 0 ? count / total : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text(
                            '$stars',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: const Color(0xFFF0F0F0),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFD97706),
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '$count',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF9E9E9E),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(_reviews.length, (index) {
            final r = _reviews[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ReviewItem(review: r),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSimilarTab() {
    if (_isLoadingSimilar) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFFFF6210)),
        ),
      );
    }

    if (_similarProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.category_outlined,
                size: 40,
                color: Color(0xFFBDBDBD),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun produit similaire pour le moment',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: _similarProducts.map((p) {
          final name = p['prod_name'] as String? ?? 'Produit';
          final price = (double.tryParse(p['basePrice']?.toString() ?? '') ?? 0)
              .toInt();
          final rating = lireDouble(p['noteMoyenne']);
          final images = p['images'];
          String imageUrl = '';
          if (images is List && images.isNotEmpty) {
            final first = images.first;
            if (first is Map && first['url'] != null) {
              imageUrl = first['url'].toString();
            }
          }
          if (imageUrl.isEmpty) {
            imageUrl =
                'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
          }
          return GestureDetector(
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.productDetail,
              arguments: {'id': p['id']},
            ),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: CustomImageWidget(
                      imageUrl: imageUrl,
                      width: 140,
                      height: 120,
                      fit: BoxFit.cover,
                      semanticLabel: 'Image du produit $name',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: Color(0xFFD97706),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_fmt(price)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF6210),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmt(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _ReviewItem extends StatelessWidget {
  final Map<String, dynamic> review;

  const _ReviewItem({required this.review});

  String _formatDate(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    const mois = [
      'Jan', 'Fév', 'Mars', 'Avr', 'Mai', 'Juin',
      'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc',
    ];
    return '${d.day} ${mois[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rating = lireInt(review['notation']);
    final comment = review['comment'] as String? ?? '';
    final date = _formatDate(review['createdAt']);
    final user = review['user'];
    final prenom = user is Map ? (user['prenom'] as String? ?? '') : '';
    final nom = user is Map ? (user['name'] as String? ?? '') : '';
    final displayName = ('$prenom $nom').trim();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F0F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFE4D1),
                child: Text(
                  initial,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF6210),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isNotEmpty ? displayName : 'Client Asoukaa',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 14,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF616161),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
