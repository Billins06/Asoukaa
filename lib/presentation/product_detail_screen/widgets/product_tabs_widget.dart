import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_image_widget.dart';

class ProductTabsWidget extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductTabsWidget({super.key, required this.product});

  @override
  State<ProductTabsWidget> createState() => _ProductTabsWidgetState();
}

class _ProductTabsWidgetState extends State<ProductTabsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static final List<Map<String, dynamic>> _reviewsMaps = [
    {
      'name': 'Aminata Coulibaly',
      'avatar':
          'https://images.pexels.com/photos/3763188/pexels-photo-3763188.jpeg',
      'avatarSemanticLabel':
          'Portrait d\'une femme africaine souriante aux cheveux tressés',
      'rating': 5,
      'date': '12 Mars 2026',
      'comment':
          'Tissu de très bonne qualité ! Les couleurs sont exactement comme sur les photos. Livraison rapide, je recommande vivement cette boutique.',
      'reviewImage':
          'https://images.pexels.com/photos/6153354/pexels-photo-6153354.jpeg',
      'reviewImageSemanticLabel':
          'Photo client montrant le tissu wax reçu avec les motifs bien visibles',
    },
    {
      'name': 'Moussa Traoré',
      'avatar':
          'https://images.pixabay.com/photo/2016/11/21/12/42/beard-1845166_1280.jpg',
      'avatarSemanticLabel':
          'Portrait d\'un homme africain avec barbe courte en chemise blanche',
      'rating': 4,
      'date': '8 Mars 2026',
      'comment':
          'Bonne qualité globale. Le tissu est solide et les couleurs ne déteint pas au lavage. J\'aurais aimé un emballage un peu plus soigné.',
      'reviewImage': null,
      'reviewImageSemanticLabel': null,
    },
    {
      'name': 'Fatou Diallo',
      'avatar':
          'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=150',
      'avatarSemanticLabel':
          'Portrait d\'une jeune femme africaine avec des boucles d\'oreilles dorées',
      'rating': 5,
      'date': '2 Mars 2026',
      'comment':
          'Parfait pour mes tenues de cérémonie ! J\'ai commandé 10 yards et je suis ravie. Le vendeur est très réactif et professionnel.',
      'reviewImage':
          'https://images.pexels.com/photos/5632398/pexels-photo-5632398.jpeg',
      'reviewImageSemanticLabel':
          'Photo de la cliente portant une robe confectionnée avec le tissu commandé',
    },
    {
      'name': 'Koffi Asante',
      'avatar':
          'https://images.pixabay.com/photo/2017/08/01/08/29/people-2563491_1280.jpg',
      'avatarSemanticLabel':
          'Portrait d\'un homme ghanéen avec lunettes sur fond gris',
      'rating': 4,
      'date': '25 Fév 2026',
      'comment':
          'Très bon rapport qualité-prix. Le tissu est authentique et de bonne épaisseur. Je reviendrai commander.',
      'reviewImage': null,
      'reviewImageSemanticLabel': null,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
            tabs: const [
              Tab(text: 'Description'),
              Tab(text: 'Avis (234)'),
              Tab(text: 'Similaires'),
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
    // Rating breakdown
    final ratingCounts = [0, 3, 12, 45, 82, 92]; // index = stars
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
                    '4.8',
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
                    '234 avis',
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
          ...List.generate(_reviewsMaps.length, (index) {
            final r = _reviewsMaps[index];
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
    final similarProducts = [
      {
        'id': 's1',
        'name': 'Tissu Wax Hollandais 6Y',
        'price': 22000,
        'rating': 4.6,
        'imageUrl':
            'https://img.rocket.new/generatedImages/rocket_gen_img_1078d5d8c-1772633811639.png',
        'semanticLabel':
            'Tissu wax hollandais avec motifs floraux jaunes et rouges plié sur comptoir',
      },
      {
        'id': 's2',
        'name': 'Tissu Bazin Riche 5Y',
        'price': 28000,
        'rating': 4.9,
        'imageUrl':
            'https://images.unsplash.com/photo-1715381043637-432896c98033',
        'semanticLabel':
            'Tissu bazin riche bleu royal brillant avec reflets argentés sur une table',
      },
      {
        'id': 's3',
        'name': 'Tissu Kente Ghana 4Y',
        'price': 35000,
        'rating': 4.7,
        'imageUrl':
            'https://img.rocket.new/generatedImages/rocket_gen_img_10f1d6997-1773009373335.png',
        'semanticLabel':
            'Tissu kente ghanéen traditionnel avec bandes multicolores dorées et vertes',
      },
      {
        'id': 's4',
        'name': 'Tissu Wax Imprimé 6Y',
        'price': 16000,
        'rating': 4.4,
        'imageUrl':
            'https://img.rocket.new/generatedImages/rocket_gen_img_16ccffa58-1765354970418.png',
        'semanticLabel':
            'Tissu wax imprimé avec motifs abstraits colorés bleu et orange déroulé',
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: similarProducts.map((p) {
          return Container(
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
                    imageUrl: p['imageUrl'] as String,
                    width: 140,
                    height: 120,
                    fit: BoxFit.cover,
                    semanticLabel: p['semanticLabel'] as String,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] as String,
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
                            '${p['rating']}',
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
                        '${_fmt(p['price'] as int)} FCFA',
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

  @override
  Widget build(BuildContext context) {
    final rating = review['rating'] as int;
    final hasImage = review['reviewImage'] != null;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: CustomImageWidget(
                  imageUrl: review['avatar'] as String,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  semanticLabel: review['avatarSemanticLabel'] as String,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['name'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      review['date'] as String,
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
          const SizedBox(height: 10),
          Text(
            review['comment'] as String,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF616161),
              height: 1.5,
            ),
          ),
          if (hasImage) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomImageWidget(
                imageUrl: review['reviewImage'] as String,
                width: 100,
                height: 80,
                fit: BoxFit.cover,
                semanticLabel: review['reviewImageSemanticLabel'] as String,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
