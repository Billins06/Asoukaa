import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../widgets/custom_image_widget.dart';
import './product_video_page_widget.dart';

class ProductGalleryWidget extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback? onBackTap;
  final int cartCount;
  final bool isTablet;

  const ProductGalleryWidget({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onBackTap,
    required this.cartCount,
    this.isTablet = false,
  });

  @override
  State<ProductGalleryWidget> createState() => _ProductGalleryWidgetState();
}

class _ProductGalleryWidgetState extends State<ProductGalleryWidget> {
  int _currentImageIndex = 0;
  late PageController _pageController;

  List<Map<String, dynamic>> get _images {
    final raw = widget.product['images'];
    if (raw is List && raw.isNotEmpty) {
      final list = raw
          // Photos seulement : les vidéos passent par _videos
          .where((img) => !(img is Map && img['isVideo'] == true))
          .map<Map<String, dynamic>>((img) {
            if (img is Map) {
              return {
                'url': (img['url'] ?? img['imageUrl'] ?? '').toString(),
                'semanticLabel':
                    (img['semanticLabel'] ?? 'Image du produit').toString(),
              };
            }
            return {'url': img.toString(), 'semanticLabel': 'Image du produit'};
          })
          .where((img) => (img['url'] as String).isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    }
    final fallbackUrl = (widget.product['imageUrl'] ?? widget.product['image_url'] ?? '').toString();
    return [
      {
        'url': fallbackUrl.isNotEmpty
            ? fallbackUrl
            : 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400',
        'semanticLabel': widget.product['semanticLabel'] ?? 'Image du produit',
      },
    ];
  }

  // URL des vidéos du produit ('videos' fourni par ProductService /
  // _normalizeNestProduct ; entrées isVideo encore présentes dans 'images'
  // acceptées aussi).
  List<String> get _videos {
    final urls = <String>[];
    void add(dynamic v) {
      final url = (v is Map ? (v['url'] ?? v['imageUrl'] ?? '') : (v ?? ''))
          .toString()
          .trim();
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }

    final rawVideos = widget.product['videos'];
    if (rawVideos is List) {
      for (final v in rawVideos) {
        add(v);
      }
    }
    final rawImages = widget.product['images'];
    if (rawImages is List) {
      for (final img in rawImages) {
        if (img is Map && img['isVideo'] == true) add(img);
      }
    }
    return urls;
  }

  // Pages de la galerie : photos d'abord (au moins une, grâce au repli de
  // _images), puis vidéos. Chaque page : {url, semanticLabel, isVideo}.
  List<Map<String, dynamic>> get _pages => [
        for (final img in _images) {...img, 'isVideo': false},
        for (final url in _videos)
          {'url': url, 'semanticLabel': 'Vidéo du produit', 'isVideo': true},
      ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  // Partage natif via les applications du téléphone (WhatsApp, SMS, etc.) —
  // pas de lien web produit pour l'instant (l'app n'a pas de version web
  // publique), donc on partage un résumé texte utile : nom, prix, boutique.
  void _shareProduct() {
    final name = (widget.product['name'] as String? ?? '').trim();
    final shop = (widget.product['shop'] as String? ?? '').trim();
    final priceValue = (widget.product['price'] as num?)?.toInt();
    final productId = (widget.product['id'] ?? '').toString();

    final buffer = StringBuffer();
    buffer.writeln('Regarde ce produit sur Asoukaa :');
    buffer.writeln(name.isNotEmpty ? name : 'Produit Asoukaa');
    if (priceValue != null && priceValue > 0) {
      buffer.writeln('${_formatSharePrice(priceValue)} FCFA');
    }
    if (shop.isNotEmpty) {
      buffer.writeln('Vendu par $shop');
    }
    // Lien profond : ouvre directement ce produit chez qui a déjà
    // l'application installée (voir deep_link_service.dart). Chez qui ne
    // l'a pas encore, le lien ne fait rien pour l'instant — il n'y a pas
    // encore de page web de secours.
    if (productId.isNotEmpty) {
      buffer.writeln('asoukaa://product?id=$productId');
    }

    // API de share_plus 10.x (la nouvelle API SharePlus/ShareParams
    // n'existe qu'à partir de la version 11 du package).
    Share.share(
      buffer.toString().trim(),
      subject: name.isNotEmpty ? name : 'Produit Asoukaa',
    );
  }

  String _formatSharePrice(int price) {
    final s = price.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final galleryHeight = widget.isTablet ? 360.0 : 320.0;
    final pages = _pages;
    // Le produit peut être rechargé avec moins de médias : on borne l'index.
    final currentIndex = _currentImageIndex < pages.length
        ? _currentImageIndex
        : pages.length - 1;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Stack(
            children: [
              // Main image PageView
              SizedBox(
                height: galleryHeight,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentImageIndex = i),
                  itemCount: pages.length,
                  itemBuilder: (_, index) {
                    final img = pages[index];
                    if (img['isVideo'] == true) {
                      return ProductVideoPageWidget(
                        key: ValueKey('video-${img['url']}'),
                        url: img['url'] as String,
                        height: galleryHeight,
                        isActive: index == currentIndex,
                      );
                    }
                    final image = CustomImageWidget(
                      imageUrl: img['url'] as String,
                      width: double.infinity,
                      height: galleryHeight,
                      fit: BoxFit.cover,
                      semanticLabel: img['semanticLabel'] as String,
                    );
                    // Un seul Hero (1re photo) : plusieurs pages visibles en
                    // même temps pendant un swipe avec le même tag Hero
                    // font échouer la transition de navigation.
                    return index == 0
                        ? Hero(
                            tag: 'product-${widget.product['id']}',
                            child: image,
                          )
                        : image;
                  },
                ),
              ),
              // Top gradient for AppBar icons
              if (!widget.isTablet)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withAlpha(120),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              // Back button
              if (widget.onBackTap != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: GestureDetector(
                    onTap: widget.onBackTap,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(220),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ),
              // Top right actions
              if (widget.onBackTap != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 12,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _shareProduct,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.share_outlined,
                            size: 18,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onFavoriteTap,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: widget.isFavorite
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Image count indicator
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${currentIndex + 1}/${pages.length}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Thumbnail strip
          if (pages.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: pages.length,
                itemBuilder: (_, index) {
                  final img = pages[index];
                  final isActive = currentIndex == index;
                  final isVideo = img['isVideo'] == true;
                  return GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFFF6210)
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isVideo
                            ? Container(
                                width: 56,
                                height: 56,
                                color: const Color(0xFF1A1A1A),
                                child: const Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                              )
                            : CustomImageWidget(
                                imageUrl: img['url'] as String,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                semanticLabel: img['semanticLabel'] as String,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
