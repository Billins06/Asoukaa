import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      illustration:
          'https://images.unsplash.com/photo-1555529669-e69e7aa0ba9a?w=600&q=80',
      illustrationLabel:
          'Marché africain coloré avec des étals de produits frais et artisanaux',
      badge: '🛍️ Bienvenue',
      title: 'Le marché\nde l\'Afrique\nde l\'Ouest',
      subtitle:
          'Découvrez des milliers de produits locaux, artisanaux et importés — livrés directement chez vous.',
      accentColor: AppTheme.primary,
      bgColor: const Color(0xFFFFF3EE),
    ),
    _OnboardingSlide(
      illustration:
          'https://images.pexels.com/photos/3184465/pexels-photo-3184465.jpeg?w=600&q=80',
      illustrationLabel:
          'Vendeur africain présentant ses produits dans une boutique moderne',
      badge: '🏪 Vendeurs',
      title: 'Vendez\npartout,\nsans limite',
      subtitle:
          'Créez votre boutique en quelques minutes. Gérez vos produits, commandes et revenus depuis votre téléphone.',
      accentColor: const Color(0xFF7C3AED),
      bgColor: const Color(0xFFF5F3FF),
    ),
    _OnboardingSlide(
      illustration:
          'https://images.pixabay.com/photo/2020/05/18/16/17/social-media-5187243_1280.png',
      illustrationLabel: 'Livreur à moto dans une ville africaine avec colis',
      badge: '🚴 Livraison',
      title: 'Livraison\nrapide &\nfiable',
      subtitle:
          'Suivez vos colis en temps réel. Nos livreurs partenaires assurent une livraison sécurisée dans toute la région.',
      accentColor: const Color(0xFF059669),
      bgColor: const Color(0xFFF0FDF4),
    ),
    _OnboardingSlide(
      illustration:
          'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=600&q=80',
      illustrationLabel:
          'Paiement mobile avec Orange Money et Wave sur smartphone',
      badge: '💳 Paiement',
      title: 'Payez\ncomme vous\nvoulez',
      subtitle:
          'Orange Money, Wave, Moov Money ou à la livraison — choisissez le mode de paiement qui vous convient.',
      accentColor: AppTheme.primary,
      bgColor: const Color(0xFFFFF3EE),
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _fadeController.reset();
    _fadeController.forward();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _goToApp();
    }
  }

  void _goToApp() {
    Navigator.pushReplacementNamed(context, AppRoutes.signUpLogin);
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentPage];
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: slide.bgColor,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        color: slide.bgColor,
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Asoukaa',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    // Skip
                    TextButton(
                      onPressed: _goToApp,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        'Passer',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Page view
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    return _SlideContent(
                      slide: _slides[index],
                      fadeAnimation: _fadeAnimation,
                      isActive: index == _currentPage,
                    );
                  },
                ),
              ),

              // Bottom controls
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  children: [
                    // Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slides.length, (index) {
                        final isActive = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive
                                ? slide.accentColor
                                : slide.accentColor.withAlpha(60),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    // CTA Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: ElevatedButton(
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: slide.accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isLast ? 'Commencer' : 'Suivant',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isLast
                                    ? Icons.rocket_launch_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _goToApp,
                        child: Text(
                          'J\'ai déjà un compte',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  final _OnboardingSlide slide;
  final Animation<double> fadeAnimation;
  final bool isActive;

  const _SlideContent({
    required this.slide,
    required this.fadeAnimation,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Illustration card
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: slide.accentColor.withAlpha(30),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(
                  slide.illustration,
                  fit: BoxFit.cover,
                  semanticLabel: slide.illustrationLabel,
                  errorBuilder: (_, __, ___) => Container(
                    color: slide.accentColor.withAlpha(20),
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 64,
                        color: slide.accentColor.withAlpha(80),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Badge
          FadeTransition(
            opacity: fadeAnimation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: slide.accentColor.withAlpha(20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                slide.badge,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: slide.accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Title
          FadeTransition(
            opacity: fadeAnimation,
            child: Text(
              slide.title,
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Subtitle
          FadeTransition(
            opacity: fadeAnimation,
            child: Text(
              slide.subtitle,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OnboardingSlide {
  final String illustration;
  final String illustrationLabel;
  final String badge;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color bgColor;

  const _OnboardingSlide({
    required this.illustration,
    required this.illustrationLabel,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.bgColor,
  });
}
