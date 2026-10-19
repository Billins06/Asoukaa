import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../routes/app_routes.dart';
import '../../../services/banner_service.dart';
import '../../../services/product_service.dart';
import '../../../utils/lecture_json.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/custom_image_widget.dart';

/// Bannières défilantes de l'accueil, entièrement pilotées par l'admin
/// (dashboard > Bannières) : image, titre/sous-titre facultatifs, durée
/// d'affichage propre à chaque bannière et cible du clic (catégorie,
/// produit, boutique ou lien externe). Aucune bannière => la zone disparaît.
///
/// [refreshToken] : incrémenté par l'accueil au « tirer pour actualiser »
/// pour recharger la liste.
class HomeBannerWidget extends StatefulWidget {
  final int refreshToken;

  const HomeBannerWidget({super.key, this.refreshToken = 0});

  @override
  State<HomeBannerWidget> createState() => _HomeBannerWidgetState();
}

class _HomeBannerWidgetState extends State<HomeBannerWidget> {
  static const double _height = 216;

  final PageController _pageController = PageController(viewportFraction: 0.92);
  Timer? _timer;

  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;
  int _currentPage = 0;
  // Incrémenté à chaque chargement : une réponse arrivée en retard est ignorée.
  int _loadGen = 0;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final list = await BannerService.instance.getBanners();
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _banners = list;
      _loading = false;
      if (_currentPage >= list.length) _currentPage = 0;
    });
    // La liste a pu changer de taille : on recale le défilement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients || _banners.isEmpty) return;
      final shown = _pageController.page?.round() ?? 0;
      if (shown != _currentPage) _pageController.jumpToPage(_currentPage);
    });
    _scheduleNext();
  }

  /// Programme le passage à la bannière suivante après la durée choisie par
  /// l'admin pour la bannière actuellement affichée.
  void _scheduleNext() {
    _timer?.cancel();
    if (!mounted || _banners.length < 2) return;
    final seconds = lireInt(
      _banners[_currentPage]['durationSeconds'],
      BannerService.defaultSeconds,
    ).clamp(BannerService.minSeconds, BannerService.maxSeconds).toInt();
    _timer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _banners.length < 2) return;
      final covered = ModalRoute.of(context)?.isCurrent == false;
      final dragging = _pageController.hasClients &&
          _pageController.position.isScrollingNotifier.value;
      if (!_pageController.hasClients || covered || dragging) {
        // Accueil recouvert par une autre page ou doigt sur la bannière :
        // on réessaie après la durée de la bannière affichée.
        _scheduleNext();
        return;
      }
      // onPageChanged reprogramme ensuite le minuteur de la page suivante.
      _pageController.animateToPage(
        (_currentPage + 1) % _banners.length,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  // ─── Clic sur une bannière ───────────────────────────────────────────

  Future<void> _onBannerTap(Map<String, dynamic> banner) async {
    if (_navigating) return;
    final type = (banner['targetType'] ?? '').toString();
    final id = (banner['targetId'] ?? '').toString();
    final label = (banner['targetLabel'] ?? '').toString();

    switch (type) {
      case 'category':
        if (id.isEmpty) return;
        _navigating = true;
        Navigator.pushNamed(
          context,
          AppRoutes.categoryProducts,
          arguments: {
            'mode': 'category',
            'id': id,
            'title': label.isEmpty ? 'Produits' : label,
          },
        ).whenComplete(() => _navigating = false);
        return;

      case 'shop':
        if (id.isEmpty) return;
        _navigating = true;
        final shopName = label.isEmpty ? 'Boutique' : label;
        final shopLogo = (banner['targetLogo'] ?? '').toString();
        Navigator.pushNamed(
          context,
          AppRoutes.boutiqueVendeur,
          arguments: {
            'id': id,
            'name': shopName,
            if (shopLogo.isNotEmpty) 'logo': shopLogo,
            'logoSemanticLabel': 'Logo de la boutique $shopName',
            // Note et ventes réelles : rechargées par la page boutique.
            'rating': 0.0,
            'salesCount': 0,
          },
        ).whenComplete(() => _navigating = false);
        return;

      case 'product':
        if (id.isEmpty) return;
        _navigating = true;
        try {
          final result = await ProductService.instance.getProductById(id);
          if (!mounted) return;
          final product = result.data;
          if (result.success && product != null) {
            Navigator.pushNamed(
              context,
              AppRoutes.productDetail,
              arguments: product,
            );
          } else {
            AppToast.show(
              context,
              message: result.error ?? 'Ce produit n\'est plus disponible.',
              type: ToastType.error,
            );
          }
        } finally {
          _navigating = false;
        }
        return;

      case 'link':
        final url = (banner['targetUrl'] ?? '').toString().trim();
        final uri = Uri.tryParse(url);
        // Le serveur n'envoie que du https ; on revérifie par prudence.
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
        _navigating = true;
        try {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && mounted) {
            AppToast.show(
              context,
              message: 'Impossible d\'ouvrir ce lien',
              type: ToastType.error,
            );
          }
        } catch (_) {
          if (mounted) {
            AppToast.show(
              context,
              message: 'Impossible d\'ouvrir ce lien',
              type: ToastType.error,
            );
          }
        } finally {
          _navigating = false;
        }
        return;
    }
  }

  // ─── Affichage ───────────────────────────────────────────────────────

  Widget _buildBanner(Map<String, dynamic> banner, int index) {
    final titre = (banner['titre'] ?? '').toString();
    final sousTitre = (banner['sousTitre'] ?? '').toString();
    final hasText = titre.isNotEmpty || sousTitre.isNotEmpty;

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
                  height: _height,
                  fit: BoxFit.cover,
                  semanticLabel: titre.isNotEmpty ? titre : 'Bannière',
                ),
                if (hasText) ...[
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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.65,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (titre.isNotEmpty)
                              Text(
                                titre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            if (titre.isNotEmpty && sousTitre.isNotEmpty)
                              const SizedBox(height: 4),
                            if (sousTitre.isNotEmpty)
                              Text(
                                sousTitre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withAlpha(220),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Premier chargement : emplacement réservé (évite que l'accueil saute).
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Container(
          height: _height,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1EDE8),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }
    // Aucune bannière visible : la zone n'apparaît pas.
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        children: [
        SizedBox(
          height: _height,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => _currentPage = i);
              _scheduleNext();
            },
            itemCount: _banners.length,
            itemBuilder: (_, index) => _buildBanner(_banners[index], index),
          ),
        ),
        if (_banners.length > 1) ...[
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
        ],
      ),
    );
  }
}
