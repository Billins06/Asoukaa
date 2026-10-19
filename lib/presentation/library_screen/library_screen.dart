import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../routes/app_routes.dart';
import '../../services/library_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/empty_state_widget.dart';

/// « Ma Bibliothèque » : les livres numériques achetés, à télécharger en PDF.
/// Le lien de téléchargement est généré à chaque appui (valable 2 minutes).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _books = [];
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await LibraryService.instance.getMyBooks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success) {
        _books = r.data ?? [];
        _error = null;
      } else if (!silent) {
        _error = r.error;
      }
    });
  }

  Future<void> _download(Map<String, dynamic> book) async {
    final productId = (book['productId'] ?? '').toString();
    if (productId.isEmpty || _downloadingId != null) return;
    setState(() => _downloadingId = productId);
    final r = await LibraryService.instance.getDownloadUrl(productId);
    if (!mounted) return;
    setState(() => _downloadingId = null);
    if (!r.success) {
      AppToast.show(
        context,
        message: r.error ?? 'Téléchargement impossible.',
        type: ToastType.error,
      );
      return;
    }
    final ok = await launchUrl(
      Uri.parse(r.data!),
      mode: LaunchMode.externalApplication,
      // Web : ouvre dans l'onglet courant (les navigateurs bloquent souvent
      // une nouvelle fenêtre ouverte après un appel réseau).
      webOnlyWindowName: '_self',
    );
    if (!mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: "Impossible d'ouvrir le téléchargement sur cet appareil.",
        type: ToastType.error,
      );
    } else {
      // Le compteur de téléchargements a changé côté serveur.
      _load(silent: true);
    }
  }

  void _reportProblem(Map<String, dynamic> book) {
    Navigator.pushNamed(
      context,
      AppRoutes.supportHelp,
      arguments: {
        'category': 'Produit défectueux',
        'orderId': (book['orderId'] ?? '').toString(),
      },
    );
  }

  String _size(dynamic bytes) {
    final n = bytes is num ? bytes.toInt() : int.tryParse('$bytes') ?? 0;
    if (n <= 0) return '';
    if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} Mo';
    return '${(n / 1024).ceil()} Ko';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Ma Bibliothèque',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: 'Bibliothèque indisponible',
        description: _error!,
        ctaLabel: 'Réessayer',
        onCtaTap: _load,
      );
    }
    if (_books.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.menu_book_outlined,
        title: 'Aucun livre pour le moment',
        description:
            'Les livres numériques que vous achetez apparaissent ici, prêts à télécharger.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _books.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _buildBookCard(_books[i]),
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> b) {
    final id = (b['productId'] ?? '').toString();
    final cover = (b['coverUrl'] ?? '').toString();
    final author = (b['author'] ?? '').toString();
    final pages = b['pageCount'];
    final size = _size(b['fileSizeBytes']);
    final downloads = (b['downloadCount'] is num) ? (b['downloadCount'] as num).toInt() : 0;
    final details = [
      if (author.isNotEmpty) author,
      if (pages != null) '$pages pages',
      if (size.isNotEmpty) size,
    ].join(' · ');
    final busy = _downloadingId == id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E4E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 88,
                  color: const Color(0xFFF5F2EF),
                  child: cover.isEmpty
                      ? const Icon(Icons.menu_book_rounded, color: Color(0xFF9E9E9E))
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.menu_book_rounded,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (b['title'] ?? 'Livre').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details,
                        style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF757575)),
                      ),
                    ],
                    if ((b['shopName'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Vendu par ${b['shopName']}',
                        style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF9E9E9E)),
                      ),
                    ],
                    if (downloads > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Téléchargé $downloads fois',
                        style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF9E9E9E)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : () => _download(b),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      busy ? 'Préparation…' : 'Télécharger le PDF',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _reportProblem(b),
                child: Text(
                  'Un problème ?',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
