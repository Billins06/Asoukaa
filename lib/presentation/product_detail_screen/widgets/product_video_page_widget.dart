import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

/// Page "vidéo" de la galerie de la fiche produit.
///
/// Rien n'est téléchargé tant que l'acheteur n'a pas touché le bouton
/// lecture (pas d'autoplay : économise la data mobile). Le lecteur est mis
/// en pause dès que la page n'est plus affichée ([isActive] = false, swipe
/// vers une autre page) ou que l'écran est recouvert par une autre route.
class ProductVideoPageWidget extends StatefulWidget {
  final String url;
  final double height;

  /// true quand cette page est la page courante du PageView.
  final bool isActive;

  const ProductVideoPageWidget({
    super.key,
    required this.url,
    required this.height,
    required this.isActive,
  });

  @override
  State<ProductVideoPageWidget> createState() => _ProductVideoPageWidgetState();
}

class _ProductVideoPageWidgetState extends State<ProductVideoPageWidget> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _hasError = false;
  bool _isMuted = false;
  // Incrémenté à chaque (ré)initialisation : un chargement devenu obsolète
  // (URL changée, nouvel essai) libère son contrôleur au lieu de l'afficher.
  int _loadToken = 0;

  @override
  void didUpdateWidget(covariant ProductVideoPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadToken++;
      _disposeController();
      _isLoading = false;
      _hasError = false;
      return;
    }
    if (oldWidget.isActive && !widget.isActive) {
      _controller?.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode passe à false quand une autre route recouvre la fiche
    // produit : on coupe le son au lieu de laisser la vidéo tourner.
    if (!TickerMode.of(context)) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    c?.dispose();
  }

  Future<void> _startVideo() async {
    if (_isLoading || _controller != null) return;
    final token = ++_loadToken;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }
    final c = VideoPlayerController.networkUrl(uri);
    try {
      await c.initialize();
    } catch (_) {
      c.dispose();
      if (mounted && token == _loadToken) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    // Page détruite (ou URL changée) pendant le chargement.
    if (!mounted || token != _loadToken || _controller != null) {
      c.dispose();
      return;
    }
    await c.setVolume(_isMuted ? 0 : 1);
    if (!mounted || token != _loadToken) {
      c.dispose();
      return;
    }
    setState(() {
      _controller = c;
      _isLoading = false;
    });
    // Lecture lancée par le tap de l'acheteur, sauf s'il a déjà changé de
    // page pendant le chargement.
    if (widget.isActive) c.play();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      // Vidéo terminée : on repart du début.
      if (c.value.position >= c.value.duration) {
        c.seekTo(Duration.zero);
      }
      c.play();
    }
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() => _isMuted = !_isMuted);
    c.setVolume(_isMuted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: ColoredBox(
        color: const Color(0xFF111111),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final c = _controller;
    if (c == null) {
      if (_isLoading) return _buildLoading();
      if (_hasError) return _buildError();
      return _buildPlaceholder();
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, value, _) {
        if (value.hasError) return _buildError();
        final aspectRatio =
            value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
              if (value.isBuffering && value.isPlaying)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              if (!value.isPlaying && !value.isBuffering)
                Center(child: _buildPlayButton(size: 64)),
              // Contrôles au-dessus du compteur 1/N de la galerie.
              Positioned(
                left: 12,
                right: 12,
                bottom: 44,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleMute,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: VideoProgressColors(
                            playedColor: const Color(0xFFFF6210),
                            bufferedColor: Colors.white.withAlpha(110),
                            backgroundColor: Colors.white.withAlpha(50),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _startVideo,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A2A2A), Color(0xFF0D0D0D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlayButton(size: 76),
              const SizedBox(height: 12),
              Text(
                'Vidéo du produit',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(220),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
    );
  }

  Widget _buildError() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _disposeController();
        setState(() {
          _hasError = false;
          _isLoading = false;
        });
        _startVideo();
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.white70,
              ),
              const SizedBox(height: 10),
              Text(
                'Impossible de lire la vidéo',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Touchez pour réessayer',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayButton({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(200), width: 2),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: size * 0.6,
        color: Colors.white,
      ),
    );
  }
}
