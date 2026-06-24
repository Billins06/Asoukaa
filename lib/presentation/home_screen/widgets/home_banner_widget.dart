import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/custom_image_widget.dart';

class HomeBannerWidget extends StatefulWidget {
  const HomeBannerWidget({super.key});

  @override
  State<HomeBannerWidget> createState() => _HomeBannerWidgetState();
}

class _HomeBannerWidgetState extends State<HomeBannerWidget>
    with SingleTickerProviderStateMixin {
  int _currentPage = 0;
  late PageController _pageController;
  late AnimationController _countdownController;
  Timer? _autoAdvanceTimer;

  static final List<Map<String, dynamic>> _defaultBanners = [
    {
      'imageUrl':
          'https://images.pexels.com/photos/5632398/pexels-photo-5632398.jpeg',
      'semanticLabel':
          'Femme africaine en tenue traditionnelle colorée tenant des tissus wax dans un marché',
      'tag': 'VENTE FLASH',
      'title': 'Tissus Wax\nAuthentiques',
      'subtitle': 'Jusqu\'à -40% sur les collections',
      'cta': 'Découvrir',
      'tagColor': const Color(0xFFDC2626),
      'countdown': true,
      'searchQuery': 'Tissu Wax',
    },
    {
      'imageUrl': 'https://images.unsplash.com/photo-1553880380-b9f10ea55fe4',
      'semanticLabel':
          'Téléphones intelligents et tablettes disposés sur une surface noire brillante',
      'tag': 'NOUVEAU',
      'title': 'Électronique\nTop Qualité',
      'subtitle': 'Smartphones dès 45 000 FCFA',
      'cta': 'Voir les offres',
      'tagColor': const Color(0xFF16A34A),
      'countdown': false,
      'searchQuery': 'Électronique',
    },
    {
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1d426ee46-1773114867630.png',
      'semanticLabel':
          'Épices africaines colorées dans des bols en céramique sur fond de bois',
      'tag': 'LIVRAISON OFFERTE',
      'title': 'Épices &\nAlimentation',
      'subtitle': 'Livraison gratuite dès 15 000 FCFA',
      'cta': 'Commander',
      'tagColor': const Color(0xFF7C3AED),
      'countdown': false,
      'searchQuery': 'Alimentation',
    },
  ];

  List<Map<String, dynamic>> _banners = [];
  int _countdownSeconds = 9258;

  @override
  void initState() {
    super.initState();
    _banners = _defaultBanners;
    _pageController = PageController(viewportFraction: 0.92);
    _countdownController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            if (mounted) {
              setState(() {
                if (_countdownSeconds > 0) _countdownSeconds--;
              });
            }
          });
    _countdownController.repeat();

    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    _countdownController.dispose();
    super.dispose();
  }

  String _formatCountdown() {
    final h = _countdownSeconds ~/ 3600;
    final m = (_countdownSeconds % 3600) ~/ 60;
    final s = _countdownSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onBannerTap(Map<String, dynamic> banner) {
    final query = banner['searchQuery'] as String? ?? '';
    Navigator.pushNamed(context, AppRoutes.searchResults, arguments: query);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _banners.length,
            itemBuilder: (_, index) {
              final banner = _banners[index];
              return AnimatedScale(
                scale: _currentPage == index ? 1.0 : 0.96,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: GestureDetector(
                  onTap: () => _onBannerTap(banner),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomImageWidget(
                            imageUrl: banner['imageUrl'] as String,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            semanticLabel: banner['semanticLabel'] as String,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withAlpha(160),
                                  Colors.transparent,
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: banner['tagColor'] as Color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    banner['tag'] as String,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  banner['title'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  banner['subtitle'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white.withAlpha(210),
                                  ),
                                ),
                                if (banner['countdown'] == true) ...[
                                  const SizedBox(height: 8),
                                  _CountdownChip(time: _formatCountdown()),
                                ],
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6210),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    banner['cta'] as String,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == i ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? const Color(0xFFFF6210)
                    : const Color(0xFFFF6210).withAlpha(60),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final String time;
  const _CountdownChip({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            time,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
