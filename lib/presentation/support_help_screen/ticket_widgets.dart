import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/support_ticket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

// Elements partages par l'ecran de support et l'ecran de detail d'un ticket :
// puces de statut, dates en francais, choix / apercu / visionneuse d'images.

// --- Statuts -----------------------------------------------------------------

Color ticketStatusColor(String status) {
  switch (status) {
    case TicketStatus.enCours:
      return const Color(0xFF3B82F6);
    case TicketStatus.resolu:
      return const Color(0xFF16A34A);
    case TicketStatus.ferme:
      return const Color(0xFF757575);
    case TicketStatus.ouvert:
    default:
      return const Color(0xFFD97706);
  }
}

String ticketStatusLabel(String status) {
  switch (status) {
    case TicketStatus.enCours:
      return 'En cours';
    case TicketStatus.resolu:
      return 'R\u00e9solu';
    case TicketStatus.ferme:
      return 'Ferm\u00e9';
    case TicketStatus.ouvert:
    default:
      return 'Ouvert';
  }
}

class TicketStatusChip extends StatelessWidget {
  final String status;

  const TicketStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = ticketStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            ticketStatusLabel(status),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Dates en francais -------------------------------------------------------

const List<String> _moisCourts = [
  'janv.',
  'f\u00e9vr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'ao\u00fbt',
  'sept.',
  'oct.',
  'nov.',
  'd\u00e9c.',
];

const List<String> _moisLongs = [
  'janvier',
  'f\u00e9vrier',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'ao\u00fbt',
  'septembre',
  'octobre',
  'novembre',
  'd\u00e9cembre',
];

const List<String> _jours = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool ticketSameDay(DateTime a, DateTime b) => _memeJour(a, b);

/// " 14:05 "
String ticketTime(DateTime d) => '${_deuxChiffres(d.hour)}:${_deuxChiffres(d.minute)}';

/// Date courte pour la liste : heure si aujourd'hui, " Hier ", " 12 oct. ".
String ticketListDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (_memeJour(d, now)) return ticketTime(d);
  final hier = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  if (_memeJour(d, hier)) return 'Hier';
  final base = '${d.day} ${_moisCourts[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Separateur de jour dans la conversation : " Aujourd'hui ", " Hier ",
/// " lundi 12 octobre ".
String ticketDayLabel(DateTime d) {
  final now = DateTime.now();
  if (_memeJour(d, now)) return "Aujourd'hui";
  final hier = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  if (_memeJour(d, hier)) return 'Hier';
  final base = '${_jours[d.weekday - 1]} ${d.day} ${_moisLongs[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// " 12 octobre 2025 a 14:05 "
String ticketFullDate(DateTime d) {
  return '${d.day} ${_moisLongs[d.month - 1]} ${d.year} \u00e0 ${ticketTime(d)}';
}

// --- Images ------------------------------------------------------------------

/// Les URLs d'images peuvent etre relatives au serveur : on les complete avec
/// l'adresse reellement utilisee par l'application.
String resolveTicketImageUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base =
      ApiService.instance.adresseActuelle.replaceAll(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

/// Image choisie par l'utilisateur, pas encore envoyee.
class PickedTicketImage {
  final XFile file;
  final Uint8List bytes;

  /// Renseignee des que l'image a ete envoyee au serveur (evite un second
  /// envoi si la creation du ticket echoue et qu'on reessaie).
  String? uploadedUrl;

  PickedTicketImage(this.file, this.bytes);
}

/// Demande Galerie / Appareil photo puis renvoie l'image choisie (ou null).
Future<PickedTicketImage?> pickTicketImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppTheme.primary,
            ),
            title: Text('Galerie', style: GoogleFonts.outfit(fontSize: 15)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppTheme.primary,
              ),
              title: Text(
                'Appareil photo',
                style: GoogleFonts.outfit(fontSize: 15),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;

  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > SupportTicketService.maxImageBytes) {
      if (context.mounted) {
        AppToast.show(
          context,
          message: 'Image trop lourde (5 Mo maximum).',
          type: ToastType.error,
        );
      }
      return null;
    }
    return PickedTicketImage(file, bytes);
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        message: "Impossible d'acc\u00e9der \u00e0 la photo.",
        type: ToastType.error,
      );
    }
    return null;
  }
}

/// Bande d'apercus des images choisies, avec bouton de suppression.
class PickedImagesStrip extends StatelessWidget {
  final List<PickedTicketImage> images;
  final void Function(int index) onRemove;
  final double size;

  const PickedImagesStrip({
    super.key,
    required this.images,
    required this.onRemove,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 8),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(images[i].bytes, fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(i),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Miniature carree d'une image deja envoyee ; un appui ouvre la visionneuse.
class TicketAttachmentThumb extends StatelessWidget {
  final List<String> urls;
  final int index;
  final double size;

  const TicketAttachmentThumb({
    super.key,
    required this.urls,
    required this.index,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openTicketImageViewer(context, urls, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: CachedNetworkImage(
            imageUrl: resolveTicketImageUrl(urls[index]),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppTheme.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openTicketImageViewer(
  BuildContext context,
  List<String> urls,
  int index,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => TicketImageViewer(urls: urls, initialIndex: index),
    ),
  );
}

/// Visionneuse plein ecran : pincer pour zoomer, glisser pour changer d'image.
class TicketImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const TicketImageViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<TicketImageViewer> createState() => _TicketImageViewerState();
}

class _TicketImageViewerState extends State<TicketImageViewer> {
  late final PageController _pageController;
  late int _current;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    final last = widget.urls.isEmpty ? 0 : widget.urls.length - 1;
    _current = widget.initialIndex.clamp(0, last).toInt();
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() {
              _current = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) => _ZoomablePage(
              url: resolveTicketImageUrl(widget.urls[i]),
              onZoomChanged: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (widget.urls.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_current + 1} / ${widget.urls.length}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePage({required this.url, required this.onZoomChanged});

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reportZoom() {
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.02);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 5,
      onInteractionEnd: (_) => _reportZoom(),
      child: Center(
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.contain,
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 56,
            ),
          ),
        ),
      ),
    );
  }
}
