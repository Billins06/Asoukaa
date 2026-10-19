import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_picker_service.dart';

import 'package:dio/dio.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';

class PublierProduitScreen extends StatefulWidget {
  // Produit existant (donnees brutes du serveur, via GET /products/:id) a
  // modifier. null = creation d'un nouveau produit.
  final Map<String, dynamic>? editProduct;

  const PublierProduitScreen({super.key, this.editProduct});

  @override
  State<PublierProduitScreen> createState() => _PublierProduitScreenState();
}

class _PublierProduitScreenState extends State<PublierProduitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _prixController = TextEditingController();
  final _stockController = TextEditingController();
  final _qteMinController = TextEditingController();
  final _lieuController = TextEditingController();
  final _marqueController = TextEditingController();

  // Real-time validation states
  String? _nomError;
  String? _prixError;
  String? _stockError;
  String? _lieuError;

  bool _nomValid = false;
  bool _prixValid = false;
  bool _stockValid = false;
  bool _lieuValid = false;
  bool _categoryValid = false;

  String? _selectedCategory;
  // Categorie parente choisie dans le premier menu (niveau 1). Sert a
  // filtrer les sous-categories proposees dans le second menu : sans ca,
  // le dropdown listait toutes les categories (parents ET enfants) a plat,
  // ce qui faisait apparaitre les sous-categories comme si elles etaient
  // elles-memes des categories principales.
  String? _selectedParentCategoryId;
  String? _selectedSize;
  String? _selectedColor;

  // Mode edition : produit/variante en cours de modification, et vraies
  // categories recuperees du serveur (remplace l'ancienne liste figee qui
  // ne correspondait a aucun identifiant reel cote backend).
  List<Map<String, dynamic>> _categoryOptions = [];
  bool _loadingCategories = true;
  String? _editingProductId;
  String? _editingVariantId;
  List<Map<String, dynamic>> _existingImages = [];
  List<Map<String, dynamic>> _existingVideos = [];
  bool get _isEditMode => widget.editProduct != null;

  final List<String> _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Unique'];

  final List<String> _colorOptions = [
    'Noir',
    'Blanc',
    'Rouge',
    'Bleu',
    'Vert',
    'Jaune',
    'Orange',
    'Violet',
    'Rose',
    'Marron',
    'Gris',
    'Multicolore',
  ];

  // Image slots with real URLs from Supabase Storage
  final List<String?> _imageSlots = List.filled(8, null);
  final List<bool> _imageUploading = List.filled(8, false);
  // Video slots (up to 2) — memes URLs reelles que les images une fois
  // uploadees (POST /upload/product-videos puis POST /products/:id/images
  // avec isVideo: true).
  final List<String?> _videoSlots = List.filled(2, null);
  final List<bool> _videoUploading = List.filled(2, false);
  // Doit rester <= MAX_VIDEO_FILE_SIZE cote backend (UploadService) : sert
  // juste a donner un message d'erreur immediat avant meme d'envoyer la
  // requete pour une video trop lourde.
  static const int _maxVideoSizeBytes = 50 * 1024 * 1024;

  // Tiered pricing rows
  final List<Map<String, TextEditingController>> _tiers = [];
  // Mode edition : le produit avait deja des paliers enregistres. Sert a
  // envoyer un PUT avec une liste vide quand le vendeur les retire tous
  // (sinon aucun appel n'etait fait et les anciens paliers restaient).
  bool _hadExistingTiers = false;

  bool _isSubmitting = false;
  bool _isSuccess = false;

  // ── Livre numérique (PDF) ──
  bool _isDigital = false;
  final _auteurController = TextEditingController();
  final _pagesController = TextEditingController();
  final List<String> _languesLivre = [
    'Français', 'Anglais', 'Fon', 'Yoruba', 'Autre',
  ];
  String _langueLivre = 'Français';
  // Chemin renvoyé par le serveur après l'envoi du PDF (null = pas de nouveau fichier).
  String? _ebookPath;
  String? _ebookName;
  int? _ebookSize;
  bool _ebookUploading = false;
  double _ebookProgress = 0;
  static const int _ebookMaxBytes = 50 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _addTier();
    _nomController.addListener(_validateNom);
    _prixController.addListener(_validatePrix);
    _stockController.addListener(_validateStock);
    _lieuController.addListener(_validateLieu);
    _loadCategories();
    if (widget.editProduct != null) {
      _prefillFromProduct(widget.editProduct!);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final r = await ApiService.instance.client.get('/api/v1/categories/flat');
      final raw = r.data;
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
      if (mounted) {
        setState(() {
          _categoryOptions = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loadingCategories = false;
          // Si une categorie etait deja selectionnee (mode edition, prefill
          // execute avant la fin de ce chargement), on retrouve sa categorie
          // parente pour pre-selectionner le premier menu correctement.
          if (_selectedCategory != null) {
            final match = _categoryOptions.firstWhere(
              (c) => (c['id'] ?? '').toString() == _selectedCategory,
              orElse: () => <String, dynamic>{},
            );
            final parentId = match['parentId'];
            _selectedParentCategoryId = (parentId != null && parentId.toString().isNotEmpty)
                ? parentId.toString()
                : _selectedCategory;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  // Categories de niveau 1 (parentId null) : premier menu.
  // Livre numérique : seulement les catégories de livres ; produit physique : les autres.
  List<Map<String, dynamic>> get _parentCategoryOptions => _categoryOptions
      .where((c) => c['parentId'] == null || c['parentId'].toString().isEmpty)
      .where((c) => (c['isDigital'] == true) == _isDigital)
      .toList();

  // Sous-categories directes d'une categorie parente donnee : second menu,
  // affiche uniquement quand la categorie choisie en a.
  List<Map<String, dynamic>> _childCategoryOptions(String? parentId) {
    if (parentId == null) return [];
    return _categoryOptions
        .where((c) => (c['parentId'] ?? '').toString() == parentId)
        .toList();
  }

  // Pre-remplit le formulaire a partir d'un produit existant
  // (GET /products/:id). NB: la marque et le lieu ne sont pas des champs
  // dedies cote serveur pour l'instant, ils sont simplement ranges dans la
  // liste generique "tags" a la creation. On les retrouve donc ici de facon
  // approximative : fiable pour le nom, la description, le prix, la
  // categorie, le stock et les images ; moins pour marque/lieu.
  void _prefillFromProduct(Map<String, dynamic> p) {
    _editingProductId = (p['id'] ?? '').toString();
    // Nature du produit d'abord : la validation du prix (0 permis pour un livre) en dépend.
    _isDigital = p['isDigital'] == true;
    _nomController.text = p['prod_name'] as String? ?? '';
    _descriptionController.text = p['description'] as String? ?? '';
    final basePrice = p['basePrice'];
    final priceValue = basePrice is num
        ? basePrice
        : double.tryParse(basePrice?.toString() ?? '') ?? 0;
    _prixController.text = priceValue == priceValue.roundToDouble()
        ? priceValue.toInt().toString()
        : priceValue.toString();

    final categories =
        (p['categories'] as List?)?.whereType<Map>().toList() ?? [];
    if (categories.isNotEmpty) {
      _selectedCategory = (categories.first['id'] ?? '').toString();
      _categoryValid = true;
    }

    final variants = (p['variants'] as List?)?.whereType<Map>().toList() ?? [];
    if (variants.isNotEmpty) {
      final v = variants.first;
      _editingVariantId = (v['id'] ?? '').toString();
      _stockController.text =
          ((v['stockQuantity'] as num?)?.toInt() ?? 0).toString();
      _selectedSize = v['size'] as String?;
      _selectedColor = v['color'] as String?;
    }

    // product.images contient a la fois les photos et les videos
    // (distinguees par isVideo) : on les separe avant de remplir les slots
    // pour ne pas afficher une video dans la galerie photo (et vice versa).
    final allMedia = (p['images'] as List?)?.whereType<Map>().toList() ?? [];
    final images = allMedia.where((e) => e['isVideo'] != true).toList();
    final videos = allMedia.where((e) => e['isVideo'] == true).toList();

    _existingImages = images.map((e) => Map<String, dynamic>.from(e)).toList();
    for (var i = 0; i < images.length && i < _imageSlots.length; i++) {
      _imageSlots[i] = images[i]['url'] as String?;
    }

    _existingVideos = videos.map((e) => Map<String, dynamic>.from(e)).toList();
    for (var i = 0; i < videos.length && i < _videoSlots.length; i++) {
      _videoSlots[i] = videos[i]['url'] as String?;
    }

    _prefillTiers(p['tierPrices']);

    // Livre numérique : on reprend les champs du livre (le PDF actuel est conservé
    // tant que le vendeur n'en choisit pas un nouveau).
    _isDigital = p['isDigital'] == true;
    if (_isDigital) {
      _auteurController.text = p['author'] as String? ?? '';
      final pages = p['pageCount'];
      _pagesController.text = pages == null ? '' : pages.toString();
      final lang = (p['language'] as String?)?.trim();
      if (lang != null && lang.isNotEmpty) {
        // Langue hors liste (saisie autrement) : on l'ajoute pour ne pas l'écraser.
        if (!_languesLivre.contains(lang)) _languesLivre.add(lang);
        _langueLivre = lang;
      }
      _ebookName = 'PDF actuel conservé';
      final size = p['fileSizeBytes'];
      _ebookSize = size is num ? size.toInt() : int.tryParse('$size');
    }

    final tags = (p['tags'] as List?)
            ?.whereType<Map>()
            .map((t) => t['tag'] as String? ?? '')
            .where((t) => t.isNotEmpty)
            .toList() ??
        [];
    final leftoverTags =
        tags.where((t) => t != _selectedSize && t != _selectedColor).toList();
    if (leftoverTags.isNotEmpty) _lieuController.text = leftoverTags.first;
    if (leftoverTags.length > 1) _marqueController.text = leftoverTags[1];

    _nomValid = _nomController.text.trim().length >= 3;
    _prixValid = _prixController.text.isNotEmpty;
    _stockValid = _stockController.text.isNotEmpty;
    _lieuValid = _lieuController.text.trim().length >= 2;
  }

  // Recharge les prix degressifs deja enregistres (GET /products/:id renvoie
  // tierPrices tries par minQuantity, avec price en chaine decimale, ex.
  // "1500.00"). Sans ca, le vendeur voyait une liste vide en modification.
  // Tous les paliers existants sont repris (meme au-dela de 5) pour ne pas
  // en supprimer silencieusement au prochain enregistrement.
  void _prefillTiers(dynamic rawTiers) {
    final tiers = (rawTiers as List?)?.whereType<Map>().toList() ?? [];
    final rows = <Map<String, String>>[];
    for (final t in tiers) {
      final min = t['minQuantity'];
      final minValue = min is num ? min.toInt() : int.tryParse(min?.toString() ?? '');
      final price = t['price'];
      final priceValue = price is num
          ? price.toDouble()
          : double.tryParse(price?.toString() ?? '');
      if (minValue == null || priceValue == null) continue;
      rows.add({
        'qte': minValue.toString(),
        'prix': priceValue == priceValue.roundToDouble()
            ? priceValue.toInt().toString()
            : priceValue.toString(),
      });
    }
    rows.sort((a, b) => int.parse(a['qte']!).compareTo(int.parse(b['qte']!)));
    if (rows.isEmpty) return;

    _hadExistingTiers = true;
    for (final t in _tiers) {
      t['qte']!.dispose();
      t['prix']!.dispose();
    }
    _tiers.clear();
    for (final r in rows) {
      _tiers.add({
        'qte': TextEditingController(text: r['qte']),
        'prix': TextEditingController(text: r['prix']),
      });
    }
  }

  // Controle des prix degressifs avant envoi. Renvoie un message d'erreur
  // (en francais, affiche tel quel) ou null si tout est correct. Une ligne
  // entierement vide est ignoree ; une ligne a moitie remplie est refusee.
  String? _validateTiers() {
    final unitPrice = double.tryParse(_prixController.text.trim());
    final seen = <int>{};
    int? previousMin;
    for (var i = 0; i < _tiers.length; i++) {
      final qteText = _tiers[i]['qte']!.text.trim();
      final prixText = _tiers[i]['prix']!.text.trim();
      if (qteText.isEmpty && prixText.isEmpty) continue;
      final label = 'Palier ${i + 1}';
      if (qteText.isEmpty || prixText.isEmpty) {
        return '$label : renseignez la quantité minimale et le prix, ou videz la ligne.';
      }
      final min = int.tryParse(qteText);
      if (min == null || min < 2) {
        return '$label : la quantité minimale doit être d\'au moins 2.';
      }
      final price = double.tryParse(prixText);
      if (price == null || price <= 0) {
        return '$label : le prix doit être supérieur à 0.';
      }
      if (unitPrice != null && unitPrice > 0 && price >= unitPrice) {
        return '$label : le prix ($prixText FCFA) doit être inférieur au prix unitaire (${_prixController.text.trim()} FCFA).';
      }
      if (!seen.add(min)) {
        return 'Deux paliers ont la même quantité minimale ($min).';
      }
      if (previousMin != null && min <= previousMin) {
        return 'Les quantités minimales doivent être croissantes d\'un palier à l\'autre.';
      }
      previousMin = min;
    }
    return null;
  }

  // ── Real-time validators ──────────────────────────────────────────────────

  void _validateNom() {
    final v = _nomController.text;
    if (v.isEmpty) {
      setState(() {
        _nomError = null;
        _nomValid = false;
      });
    } else if (v.trim().length < 3) {
      setState(() {
        _nomError = 'Nom trop court (min. 3 caractères)';
        _nomValid = false;
      });
    } else if (v.trim().length > 100) {
      setState(() {
        _nomError = 'Nom trop long (max. 100 caractères)';
        _nomValid = false;
      });
    } else {
      setState(() {
        _nomError = null;
        _nomValid = true;
      });
    }
  }

  void _validatePrix() {
    final v = _prixController.text;
    if (v.isEmpty) {
      setState(() {
        _prixError = null;
        _prixValid = false;
      });
    } else {
      final price = int.tryParse(v);
      // Un livre numérique peut être gratuit (0 F) ; un produit physique non.
      if (price == null || price < 0 || (price == 0 && !_isDigital)) {
        setState(() {
          _prixError = _isDigital ? 'Prix invalide (0 = gratuit)' : 'Prix invalide (doit être > 0)';
          _prixValid = false;
        });
      } else if (price > 100000000) {
        setState(() {
          _prixError = 'Prix trop élevé';
          _prixValid = false;
        });
      } else {
        setState(() {
          _prixError = null;
          _prixValid = true;
        });
      }
    }
  }

  void _validateStock() {
    final v = _stockController.text;
    if (v.isEmpty) {
      setState(() {
        _stockError = null;
        _stockValid = false;
      });
    } else {
      final stock = int.tryParse(v);
      if (stock == null || stock < 0) {
        setState(() {
          _stockError = 'Stock invalide (doit être ≥ 0)';
          _stockValid = false;
        });
      } else {
        setState(() {
          _stockError = null;
          _stockValid = true;
        });
      }
    }
  }

  void _validateLieu() {
    final v = _lieuController.text;
    if (v.isEmpty) {
      setState(() {
        _lieuError = null;
        _lieuValid = false;
      });
    } else if (v.trim().length < 2) {
      setState(() {
        _lieuError = 'Lieu trop court';
        _lieuValid = false;
      });
    } else {
      setState(() {
        _lieuError = null;
        _lieuValid = true;
      });
    }
  }

  void _addTier() {
    if (_tiers.length < 5) {
      setState(() {
        _tiers.add({
          'qte': TextEditingController(),
          'prix': TextEditingController(),
        });
      });
    }
  }

  void _removeTier(int index) {
    setState(() {
      // On garde toujours au moins une ligne (vide) a l'ecran : retirer le
      // dernier palier revient a vider ses champs.
      if (_tiers.length <= 1) {
        _tiers[index]['qte']!.clear();
        _tiers[index]['prix']!.clear();
        return;
      }
      _tiers[index]['qte']!.dispose();
      _tiers[index]['prix']!.dispose();
      _tiers.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nomController.removeListener(_validateNom);
    _prixController.removeListener(_validatePrix);
    _stockController.removeListener(_validateStock);
    _lieuController.removeListener(_validateLieu);
    _nomController.dispose();
    _descriptionController.dispose();
    _prixController.dispose();
    _stockController.dispose();
    _qteMinController.dispose();
    _lieuController.dispose();
    _marqueController.dispose();
    _auteurController.dispose();
    _pagesController.dispose();
    for (final t in _tiers) {
      t['qte']!.dispose();
      t['prix']!.dispose();
    }
    super.dispose();
  }

  // ── Pick and upload image ─────────────────────────────────────────────────

  Future<void> _pickAndUploadImage(
    int index, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 80);
    if (picked == null) return;

    setState(() => _imageUploading[index] = true);

    try {
      final bytes = await picked.readAsBytes();
      // Type d'après le vrai format choisi (JPG par défaut) : sans type, le
      // serveur refuse le fichier. L'extension du nom suit le type.
      final mime = UploadService.mimeDepuisNom(
        picked.name.isNotEmpty ? picked.name : picked.path,
      );
      final extPhoto = mime == 'image/png'
          ? 'png'
          : (mime == 'image/webp' ? 'webp' : 'jpg');
      final fileName =
          'product_${DateTime.now().millisecondsSinceEpoch}.$extPhoto';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final res = await ApiService.instance.client.post('/api/v1/upload/products', data: formData);
      final url = res.data['url'] as String?;
      if (!mounted) return;
      setState(() {
        _imageUploading[index] = false;
        if (url != null) {
          _imageSlots[index] = url;
        } else {
          AppToast.show(context, message: 'Échec de l\'upload. Réessayez.', type: ToastType.error);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _imageUploading[index] = false);
      AppToast.show(context, message: 'Échec de l\'upload. Réessayez.', type: ToastType.error);
    }
  }

  void _showImageSourceDialog(int index) {
    showModalBottomSheet(
      context: context,
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
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(index, source: ImageSource.gallery);
              },
            ),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(index, source: ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Pick and upload video ─────────────────────────────────────────────────

  Future<void> _pickAndUploadVideo(
    int index, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = await picker.pickVideo(source: source);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, message: 'Impossible de sélectionner la vidéo.', type: ToastType.error);
      return;
    }
    if (picked == null) return;

    final sizeBytes = await picked.length();
    if (sizeBytes > _maxVideoSizeBytes) {
      if (!mounted) return;
      AppToast.show(
        context,
        message:
            'Vidéo trop volumineuse (max ${_maxVideoSizeBytes ~/ (1024 * 1024)} Mo). Choisissez une vidéo plus courte.',
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    setState(() => _videoUploading[index] = true);

    try {
      final bytes = await picked.readAsBytes();
      final dotIndex = picked.path.lastIndexOf('.');
      final ext = dotIndex != -1 ? picked.path.substring(dotIndex + 1).toLowerCase() : 'mp4';
      final fileName = 'product_video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          // Type d'après l'extension (mp4 / mov / webm), mp4 par défaut.
          contentType: DioMediaType.parse(
            ['video/mp4', 'video/quicktime', 'video/webm']
                    .contains(UploadService.mimeDepuisNom(fileName))
                ? UploadService.mimeDepuisNom(fileName)
                : 'video/mp4',
          ),
        ),
      });
      // Une vidéo (jusqu'à 50 Mo) met bien plus longtemps qu'une photo à
      // partir puis à être stockée côté serveur : le délai global de 30 s
      // d'ApiService ferait échouer l'envoi sur une connexion mobile lente.
      final res = await ApiService.instance.client.post(
        '/api/v1/upload/product-videos',
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final url = res.data['url'] as String?;
      if (!mounted) return;
      setState(() {
        _videoUploading[index] = false;
        if (url != null) {
          _videoSlots[index] = url;
        } else {
          AppToast.show(context, message: 'Échec de l\'upload de la vidéo. Réessayez.', type: ToastType.error);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _videoUploading[index] = false);
      AppToast.show(
        context,
        message: 'Échec de l\'upload de la vidéo : ${_describeError(e)}',
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _showVideoSourceDialog(int index) {
    showModalBottomSheet(
      context: context,
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
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadVideo(index, source: ImageSource.gallery);
              },
            ),
            if (PhotoPickerService.cameraAvailable)
              ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text('Caméra', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadVideo(index, source: ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _submitForm() async {
    _validateNom();
    _validatePrix();
    if (!_isDigital) {
      _validateStock();
      _validateLieu();
    }

    if (!_formKey.currentState!.validate()) return;

    final isLoggedIn = await NestAuthService.instance.isLoggedIn();
    if (!isLoggedIn) {
      AppToast.show(context, message: 'Vous devez être connecté.', type: ToastType.error);
      return;
    }

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      setState(() => _categoryValid = false);
      AppToast.show(context, message: 'Sélectionnez une catégorie.', type: ToastType.error);
      return;
    }

    if (_isDigital) {
      if (_ebookUploading) {
        AppToast.show(context, message: "Patientez : le PDF est en cours d'envoi.", type: ToastType.error);
        return;
      }
      if (!_isEditMode && _ebookPath == null) {
        AppToast.show(context, message: 'Ajoutez le fichier PDF du livre.', type: ToastType.error);
        return;
      }
    }

    final tierError = _isDigital ? null : _validateTiers();
    if (tierError != null) {
      AppToast.show(
        context,
        message: 'Prix dégressifs : $tierError',
        type: ToastType.error,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final priceValue = double.tryParse(_prixController.text.trim()) ?? 0;
      final stockValue = int.tryParse(_stockController.text.trim()) ?? 0;

      // Contrat reel attendu par le backend (CreateProductDto / UpdateProductDto) :
      // prod_name, description, basePrice, categoryIds (UUIDs), tags, status.
      final productPayload = <String, dynamic>{
        'prod_name': _nomController.text.trim(),
        'description': _descriptionController.text.trim(),
        'basePrice': priceValue,
        'status': 'active',
        'categoryIds': [_selectedCategory],
        'tags': [
          if (_marqueController.text.trim().isNotEmpty) _marqueController.text.trim(),
          if (_lieuController.text.trim().isNotEmpty) _lieuController.text.trim(),
        ],
      };
      if (_isDigital) {
        productPayload['isDigital'] = true;
        productPayload['author'] = _auteurController.text.trim();
        productPayload['pageCount'] = int.tryParse(_pagesController.text.trim()) ?? 0;
        productPayload['language'] = _langueLivre;
        // Nouveau PDF seulement : en modification, sans PDF choisi, l'ancien est conservé.
        if (_ebookPath != null) productPayload['filePath'] = _ebookPath;
      }

      String productId;
      if (_isEditMode && _editingProductId != null && _editingProductId!.isNotEmpty) {
        productId = _editingProductId!;
        await ApiService.instance.client.put(
          '/api/v1/products/$productId',
          data: productPayload,
        );
      } else {
        final res = await ApiService.instance.client.post(
          '/api/v1/products',
          data: productPayload,
        );
        final data = res.data;
        productId = (data is Map ? data['id'] : null)?.toString() ?? '';
        if (productId.isEmpty) {
          throw Exception('Produit créé mais identifiant manquant dans la réponse');
        }
      }

      // Le stock/prix vivent sur la variante, pas sur le produit lui-même.
      // (Livre numérique : le serveur crée lui-même sa variante technique.)
      if (!_isDigital) {
      final variantPayload = <String, dynamic>{
        'color': _selectedColor,
        'size': _selectedSize,
        'price': priceValue,
        'stockQuantity': stockValue,
      }..removeWhere((key, value) => value == null);

      if (_isEditMode && _editingVariantId != null && _editingVariantId!.isNotEmpty) {
        await ApiService.instance.client.put(
          '/api/v1/products/$productId/variants/$_editingVariantId',
          data: variantPayload,
        );
      } else {
        await ApiService.instance.client.post(
          '/api/v1/products/$productId/variants',
          data: {
            'sku': 'SKU-${DateTime.now().millisecondsSinceEpoch}',
            ...variantPayload,
          },
        );
      }
      }

      // Images : on ajoute les nouvelles, on retire celles retirées de la fiche.
      final currentUrls =
          _imageSlots.where((s) => s != null).map((s) => s!).toSet();
      final existingUrls = _existingImages
          .map((e) => e['url'] as String?)
          .whereType<String>()
          .toSet();

      for (var i = 0; i < _imageSlots.length; i++) {
        final url = _imageSlots[i];
        if (url == null || existingUrls.contains(url)) continue;
        try {
          await ApiService.instance.client.post(
            '/api/v1/products/$productId/images',
            data: {'imageUrl': url, 'isPrimary': i == 0},
          );
        } catch (e) {
          // Ne pas avaler l'erreur en silence : l'upload du fichier (voir
          // _pickAndUploadImage) a pu reussir alors que ce rattachement au
          // produit echoue ensuite (reseau, session expiree, etc.) - sans ce
          // toast le vendeur croit la photo enregistree alors qu'elle
          // manque sur la fiche produit.
          debugPrint('[PublierProduit][image attach] Exception: $e');
          if (mounted) {
            AppToast.show(
              context,
              message: "Échec de l'envoi de la photo ${i + 1} : ${_describeError(e)}",
              type: ToastType.error,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }
      for (final existing in _existingImages) {
        final url = existing['url'] as String?;
        final imageId = existing['id'] as String?;
        if (url == null || imageId == null) continue;
        if (!currentUrls.contains(url)) {
          try {
            await ApiService.instance.client.delete(
              '/api/v1/products/$productId/images/$imageId',
            );
          } catch (_) {}
        }
      }

      // Videos : meme logique que les images (meme endpoint), avec
      // isVideo: true et jamais isPrimary (une video n'est jamais l'image
      // principale de la fiche).
      final currentVideoUrls =
          _videoSlots.where((s) => s != null).map((s) => s!).toSet();
      final existingVideoUrls = _existingVideos
          .map((e) => e['url'] as String?)
          .whereType<String>()
          .toSet();

      for (var i = 0; i < _videoSlots.length; i++) {
        final url = _videoSlots[i];
        if (url == null || existingVideoUrls.contains(url)) continue;
        try {
          await ApiService.instance.client.post(
            '/api/v1/products/$productId/images',
            data: {'imageUrl': url, 'isVideo': true, 'isPrimary': false},
          );
        } catch (e) {
          debugPrint('[PublierProduit][video attach] Exception: $e');
          if (mounted) {
            AppToast.show(
              context,
              message: "Échec de l'envoi de la vidéo ${i + 1} : ${_describeError(e)}",
              type: ToastType.error,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }
      for (final existing in _existingVideos) {
        final url = existing['url'] as String?;
        final imageId = existing['id'] as String?;
        if (url == null || imageId == null) continue;
        if (!currentVideoUrls.contains(url)) {
          try {
            await ApiService.instance.client.delete(
              '/api/v1/products/$productId/images/$imageId',
            );
          } catch (_) {}
        }
      }

      // Lignes deja validees par _validateTiers (les lignes vides sont
      // ignorees). PUT remplace tous les paliers : on l'envoie aussi avec
      // une liste vide quand le vendeur a retire tous les paliers existants.
      final priceTiers = _tiers
          .where((t) =>
              t['qte']!.text.trim().isNotEmpty &&
              t['prix']!.text.trim().isNotEmpty)
          .map(
            (t) => {
              'minQuantity': int.tryParse(t['qte']!.text.trim()) ?? 0,
              'price': double.tryParse(t['prix']!.text.trim()) ?? 0,
            },
          )
          .toList();
      String? tierSaveError;
      if (!_isDigital && (priceTiers.isNotEmpty || (_isEditMode && _hadExistingTiers))) {
        try {
          await ApiService.instance.client.put(
            '/api/v1/products/$productId/tier-prices',
            data: priceTiers,
          );
          _hadExistingTiers = priceTiers.isNotEmpty;
        } catch (e) {
          debugPrint('[PublierProduit][tier-prices] Exception: $e');
          tierSaveError = _describeError(e);
        }
      }

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isSuccess = true;
      });
      if (tierSaveError != null) {
        // Le produit lui-meme est bien enregistre : on le dit, mais on
        // previent clairement que les paliers n'ont pas ete pris en compte.
        AppToast.show(
          context,
          message:
              'Produit enregistré, mais les prix dégressifs n\'ont pas pu être enregistrés : $tierSaveError',
          type: ToastType.error,
          duration: const Duration(seconds: 8),
        );
      } else {
        AppToast.show(
          context,
          message: _isEditMode
              ? 'Produit mis à jour avec succès !'
              : 'Produit publié avec succès ! Il sera visible sous peu.',
          type: ToastType.success,
          actionLabel: 'OK',
        );
      }
      Future.delayed(Duration(seconds: tierSaveError != null ? 3 : 2), () {
        if (!mounted) return;
        Navigator.pop(context, true);
      });
    } catch (e, st) {
      debugPrint('[PublierProduit][_submitForm] Exception: $e');
      debugPrint('[PublierProduit][_submitForm] Stack: $st');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.show(
        context,
        message: _isEditMode
            ? 'Erreur lors de la mise à jour : ${_describeError(e)}'
            : 'Erreur lors de la publication : ${_describeError(e)}',
        type: ToastType.error,
        duration: const Duration(seconds: 8),
      );
    }
  }

  // Extrait le vrai message d'erreur renvoye par le backend au lieu d'un
  // texte generique — sans ca, un rejet legitime (boutique pas encore
  // approuvee, categorie invalide, SKU en double...) ressemblait a une
  // panne et restait impossible a diagnostiquer depuis l'appli.
  String _describeError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String? backendMsg;
      if (data is Map) {
        final m = data['message'];
        backendMsg = m is List ? m.join(', ') : m?.toString();
      } else if (data is String && data.isNotEmpty) {
        backendMsg = data;
      }
      if (backendMsg != null && backendMsg.isNotEmpty) {
        return backendMsg;
      }
      if (status != null) return 'HTTP $status';
      return e.message ?? 'erreur réseau';
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditMode) ...[
              _buildNatureSelector(),
              const SizedBox(height: 20),
            ],
            _buildMediaSection(),
            const SizedBox(height: 20),
            _buildInfoSection(),
            const SizedBox(height: 20),
            if (_isDigital) ...[
              _buildBookSection(),
              const SizedBox(height: 20),
            ] else ...[
              _buildSpecificationsSection(),
              const SizedBox(height: 20),
            ],
            _buildPricingSection(),
            const SizedBox(height: 20),
            if (!_isDigital) ...[
              _buildTieredPricingSection(),
              const SizedBox(height: 20),
              _buildStockSection(),
              const SizedBox(height: 20),
              _buildLocationSection(),
            ],
            const SizedBox(height: 28),
            _buildSubmitButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _isEditMode ? 'Modifier le produit' : 'Publier un produit',
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.outlineVariant),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppTheme.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildValidatedFormField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    String? errorText,
    bool isValid = false,
    int maxLines = 1,
    String? suffixText,
    bool alignLabelWithHint = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final showError = errorText != null && controller.text.isNotEmpty;
    final showSuccess = isValid && !showError;

    Color borderColor() {
      if (showError) return const Color(0xFFDC2626);
      if (showSuccess) return const Color(0xFF16A34A);
      return AppTheme.outline;
    }

    Color fillColor() {
      if (showError) return const Color(0xFFFEF2F2);
      if (showSuccess) return const Color(0xFFF0FDF4);
      return AppTheme.surface;
    }

    Color iconColor() {
      if (showError) return const Color(0xFFDC2626);
      if (showSuccess) return const Color(0xFF16A34A);
      return AppTheme.muted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          validator: validator,
          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            alignLabelWithHint: alignLabelWithHint,
            suffixText: suffixText,
            prefixIcon: Icon(prefixIcon, size: 20, color: iconColor()),
            suffixIcon: showSuccess
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Color(0xFF16A34A),
                  )
                : showError
                ? const Icon(
                    Icons.error_rounded,
                    size: 20,
                    color: Color(0xFFDC2626),
                  )
                : null,
            filled: true,
            fillColor: fillColor(),
            labelStyle: GoogleFonts.outfit(fontSize: 14, color: iconColor()),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor()),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: borderColor(),
                width: showSuccess ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showError
                    ? const Color(0xFFDC2626)
                    : showSuccess
                    ? const Color(0xFF16A34A)
                    : AppTheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
            ),
            errorStyle: GoogleFonts.outfit(
              fontSize: 11,
              color: const Color(0xFFDC2626),
            ),
          ),
        ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: const Color(0xFFDC2626),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (showSuccess)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 13,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 4),
                Text(
                  'Valide ✓',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── MEDIA SECTION ──────────────────────────────────────────────────────────

  Widget _buildMediaSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            _isDigital ? 'Couverture du livre' : 'Photos & Vidéos',
            _isDigital
                ? 'Jusqu\'à 8 images ; la première est la couverture'
                : 'Jusqu\'à 8 photos et 2 vidéos',
          ),
          const SizedBox(height: 14),
          Text(
            'Photos (${_imageSlots.where((s) => s != null).length}/8)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 8,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _buildImageSlot(i),
            ),
          ),
          if (!_isDigital) ...[
            const SizedBox(height: 16),
            Text(
              'Vidéos (${_videoSlots.where((s) => s != null).length}/2)',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildVideoSlot(0),
                const SizedBox(width: 10),
                _buildVideoSlot(1),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageSlot(int index) {
    final hasImage = _imageSlots[index] != null;
    final isUploading = _imageUploading[index];

    return GestureDetector(
      onTap: isUploading ? null : () => _showImageSourceDialog(index),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? AppTheme.primary.withAlpha(80) : AppTheme.outline,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: isUploading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                  ),
                ),
              )
            : hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      _imageSlots[index]!,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      semanticLabel: 'Image produit ${index + 1}',
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _imageSlots[index] = null),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Principale',
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    index == 0
                        ? Icons.add_photo_alternate_outlined
                        : Icons.add_rounded,
                    color: AppTheme.muted,
                    size: index == 0 ? 26 : 22,
                  ),
                  if (index == 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Principale',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildVideoSlot(int index) {
    final hasVideo = _videoSlots[index] != null;
    final isUploading = _videoUploading[index];
    return GestureDetector(
      onTap: isUploading ? null : () => _showVideoSourceDialog(index),
      child: Container(
        width: 120,
        height: 72,
        decoration: BoxDecoration(
          color: hasVideo ? AppTheme.primaryMuted : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVideo ? AppTheme.primary.withAlpha(80) : AppTheme.outline,
            width: hasVideo ? 2 : 1,
          ),
        ),
        child: isUploading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                  ),
                ),
              )
            : hasVideo
            ? Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    color: AppTheme.primary,
                    size: 28,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _videoSlots[index] = null),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'Vidéo ${index + 1}',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.video_call_outlined,
                    color: AppTheme.muted,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vidéo ${index + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── INFO SECTION ───────────────────────────────────────────────────────────

  Widget _buildInfoSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Informations produit',
            'Nom, description et catégorie',
          ),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _nomController,
            label: _isDigital ? 'Titre du livre *' : 'Nom du produit *',
            hintText: _isDigital ? 'Ex: Le roi de Dahomey' : 'Ex: Tissu Wax Ankara 6 yards',
            prefixIcon: Icons.inventory_2_outlined,
            errorText: _nomError,
            isValid: _nomValid,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Champ requis';
              if (v.trim().length < 3) {
                return 'Nom trop court (min. 3 caractères)';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _buildCategoryDropdown(),
          const SizedBox(height: 14),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: _isDigital
                  ? 'Résumé du livre : les clients ne peuvent pas le feuilleter avant achat...'
                  : 'Décrivez votre produit en détail...',
              prefixIcon: const Icon(Icons.description_outlined, size: 20),
              alignLabelWithHint: true,
              labelStyle: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // Style commun des deux menus (bordure rouge si invalide, memes couleurs
  // / rayon que le reste du formulaire) pour eviter de dupliquer la deco.
  InputDecoration _categoryFieldDecoration({
    required String label,
    required bool hasError,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        Icons.category_outlined,
        size: 20,
        color: hasError ? const Color(0xFFDC2626) : AppTheme.muted,
      ),
      filled: true,
      fillColor: AppTheme.surface,
      labelStyle: GoogleFonts.outfit(fontSize: 14, color: AppTheme.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? const Color(0xFFDC2626) : AppTheme.outline,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
      ),
    );
  }

  // Menu a deux niveaux : categorie principale, puis sous-categorie si la
  // categorie choisie en possede. Avant ce correctif, les categories et
  // sous-categories etaient toutes listees a plat dans un seul menu, ce qui
  // faisait apparaitre les sous-categories comme si elles etaient elles-memes
  // des categories principales.
  Widget _buildCategoryDropdown() {
    final children = _childCategoryOptions(_selectedParentCategoryId);
    final needsChild = children.isNotEmpty;
    final showParentError = !_categoryValid && _selectedParentCategoryId == null;
    final showChildError = !_categoryValid && needsChild && _selectedCategory == null;
    // La valeur du second menu ne doit pointer que vers une sous-categorie
    // de la categorie parente actuellement choisie (sinon Flutter plante
    // si la valeur ne correspond a aucun item de la liste).
    final childValue = children.any((c) => (c['id'] ?? '').toString() == _selectedCategory)
        ? _selectedCategory
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // initialValue n'est lu qu'à la création du champ : la clé force
          // sa reconstruction quand la catégorie parente est fixée après
          // coup (mode modification : chargement asynchrone des catégories).
          key: ValueKey('parent-cat-$_selectedParentCategoryId'),
          initialValue: _selectedParentCategoryId,
          decoration: _categoryFieldDecoration(
            label: 'Catégorie *',
            hasError: showParentError,
          ),
          hint: Text(
            _loadingCategories
                ? 'Chargement des catégories...'
                : 'Sélectionner une catégorie',
            style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.muted),
          ),
          items: _parentCategoryOptions
              .map(
                (c) => DropdownMenuItem(
                  value: (c['id'] ?? '').toString(),
                  child: Text(
                    (c['name'] ?? '').toString(),
                    style: GoogleFonts.outfit(fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: _loadingCategories
              ? null
              : (val) {
                  setState(() {
                    _selectedParentCategoryId = val;
                    final newChildren = _childCategoryOptions(val);
                    // Une categorie sans sous-categorie est directement
                    // utilisable comme categorie finale du produit ; sinon
                    // on attend que l'utilisateur precise la sous-categorie.
                    if (newChildren.isEmpty) {
                      _selectedCategory = val;
                      _categoryValid = val != null;
                    } else {
                      _selectedCategory = null;
                      _categoryValid = false;
                    }
                  });
                },
          validator: (v) => v == null ? 'Catégorie requise' : null,
        ),
        if (needsChild) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // Clé liée au parent : quand on change de catégorie parente, le
            // champ repart de zéro. Sans elle, il garderait la sous-catégorie
            // de l'ancien parent, absente de la nouvelle liste → plantage
            // Flutter ("There should be exactly one item with value...").
            key: ValueKey('child-cat-$_selectedParentCategoryId'),
            initialValue: childValue,
            decoration: _categoryFieldDecoration(
              label: 'Sous-catégorie *',
              hasError: showChildError,
            ),
            hint: Text(
              'Sélectionner une sous-catégorie',
              style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.muted),
            ),
            items: children
                .map(
                  (c) => DropdownMenuItem(
                    value: (c['id'] ?? '').toString(),
                    child: Text(
                      (c['name'] ?? '').toString(),
                      style: GoogleFonts.outfit(fontSize: 14),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedCategory = val;
                _categoryValid = val != null;
              });
            },
            validator: (v) => v == null ? 'Sous-catégorie requise' : null,
          ),
        ],
      ],
    );
  }

  // ── LIVRE NUMÉRIQUE ────────────────────────────────────────────────────────

  Widget _buildNatureSelector() {
    Widget chip(String label, IconData icon, bool digital) {
      final selected = _isDigital == digital;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isSubmitting
              ? null
              : () {
                  if (_isDigital == digital) return;
                  setState(() {
                    _isDigital = digital;
                    // Les catégories diffèrent selon la nature : on repart de zéro.
                    _selectedParentCategoryId = null;
                    _selectedCategory = null;
                    _categoryValid = false;
                  });
                  _validatePrix();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withAlpha(25) : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? AppTheme.primary : AppTheme.muted),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Type de produit', 'Que souhaitez-vous publier ?'),
          const SizedBox(height: 14),
          Row(
            children: [
              chip('Produit physique', Icons.inventory_2_outlined, false),
              const SizedBox(width: 12),
              chip('Livre numérique (PDF)', Icons.menu_book_outlined, true),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickEbook() async {
    if (_ebookUploading) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.size > _ebookMaxBytes) {
        if (mounted) {
          AppToast.show(context, message: 'Le PDF dépasse 50 Mo.', type: ToastType.error);
        }
        return;
      }
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) {
          AppToast.show(context, message: 'Impossible de lire ce fichier.', type: ToastType.error);
        }
        return;
      }
      if (bytes.length > _ebookMaxBytes) {
        if (mounted) {
          AppToast.show(context, message: 'Le PDF dépasse 50 Mo.', type: ToastType.error);
        }
        return;
      }
      setState(() {
        _ebookUploading = true;
        _ebookProgress = 0;
      });
      final r = await UploadService.instance.uploadEbook(
        bytes,
        f.name,
        onProgress: (p) {
          if (mounted) setState(() => _ebookProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _ebookPath = r.path;
        _ebookName = f.name;
        _ebookSize = r.size;
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: "Échec de l'envoi du PDF : ${_describeError(e)}",
          type: ToastType.error,
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      if (mounted) setState(() => _ebookUploading = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    return '${(bytes / 1024).ceil()} Ko';
  }

  Widget _buildBookSection() {
    final noCategory = !_loadingCategories && _parentCategoryOptions.isEmpty;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Fiche du livre', 'Auteur, pages, langue et fichier PDF'),
          const SizedBox(height: 16),
          if (noCategory) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Aucune catégorie de livres numériques n'est disponible pour le moment. Réessayez plus tard.",
                style: GoogleFonts.outfit(fontSize: 12.5, color: const Color(0xFF92400E)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _buildValidatedFormField(
            controller: _auteurController,
            label: 'Auteur *',
            hintText: "Ex: Amadou Diallo",
            prefixIcon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Auteur requis';
              if (v.trim().length > 200) return 'Trop long (max. 200 caractères)';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _buildValidatedFormField(
            controller: _pagesController,
            label: 'Nombre de pages *',
            hintText: 'Ex: 220',
            prefixIcon: Icons.auto_stories_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1) return 'Nombre de pages requis';
              if (n > 20000) return 'Nombre de pages invalide';
              return null;
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _langueLivre,
            decoration: _categoryFieldDecoration(label: 'Langue *', hasError: false),
            items: _languesLivre
                .map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l, style: GoogleFonts.outfit(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _langueLivre = v);
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Fichier du livre (PDF, 50 Mo max) *',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: (_ebookUploading || _isSubmitting) ? null : _pickEbook,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _ebookName != null ? const Color(0xFF16A34A) : AppTheme.outline,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _ebookName != null ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                    color: _ebookName != null ? const Color(0xFFDC2626) : AppTheme.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ebookUploading
                              ? 'Envoi en cours… ${(_ebookProgress * 100).toInt()} %'
                              : (_ebookName ?? 'Choisir le fichier PDF'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (_ebookUploading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: _ebookProgress > 0 ? _ebookProgress : null),
                        ] else if (_ebookName != null) ...[
                          Text(
                            [
                              if (_ebookSize != null && _ebookSize! > 0) _formatSize(_ebookSize!),
                              'Touchez pour remplacer',
                            ].join(' · '),
                            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Le fichier reste privé : seuls les clients qui ont acheté le livre peuvent le télécharger.",
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }

  // ── SPECIFICATIONS SECTION ─────────────────────────────────────────────────

  Widget _buildSpecificationsSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Spécificités', 'Marque, taille, couleur'),
          const SizedBox(height: 16),
          // Marque
          TextFormField(
            controller: _marqueController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Marque (optionnel)',
              hintText: 'Ex: Samsung, Artisanal...',
              prefixIcon: const Icon(
                Icons.branding_watermark_outlined,
                size: 20,
              ),
              labelStyle: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Taille
          Text(
            'Taille (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sizes.map((size) {
              final isSelected = _selectedSize == size;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedSize = isSelected ? null : size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryMuted
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    size,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // Couleur
          Text(
            'Couleur (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colorOptions.map((color) {
              final isSelected = _selectedColor == color;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedColor = isSelected ? null : color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryMuted
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    color,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PRICING SECTION ────────────────────────────────────────────────────────

  Widget _buildPricingSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            _isDigital ? 'Prix du livre' : 'Prix',
            _isDigital ? 'En FCFA (0 = livre gratuit)' : 'Prix unitaire en FCFA',
          ),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _prixController,
            label: 'Prix unitaire *',
            hintText: 'Ex: 5000',
            prefixIcon: Icons.sell_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            suffixText: 'FCFA',
            errorText: _prixError,
            isValid: _prixValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Prix requis';
              final price = int.tryParse(v);
              if (price == null || price < 0 || (price == 0 && !_isDigital)) {
                return 'Prix invalide';
              }
              return null;
            },
          ),
          if (!_isDigital) const SizedBox(height: 14),
          if (!_isDigital)
          _buildValidatedFormField(
            controller: _qteMinController,
            label: 'Quantité minimum de commande',
            hintText: 'Ex: 1',
            prefixIcon: Icons.shopping_basket_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ),
    );
  }

  // ── TIERED PRICING SECTION ─────────────────────────────────────────────────

  Widget _buildTieredPricingSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Prix dégressifs',
            'Optionnel — réductions par quantité',
          ),
          const SizedBox(height: 14),
          ..._tiers.asMap().entries.map((e) => _buildTierRow(e.key)),
          if (_tiers.length < 5)
            TextButton.icon(
              onPressed: _addTier,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Ajouter un palier',
                style: GoogleFonts.outfit(fontSize: 13),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildTierRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _tiers[index]['qte'],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Qté min',
                prefixIcon: const Icon(Icons.format_list_numbered, size: 18),
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.outfit(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _tiers[index]['prix'],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Prix FCFA',
                prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.outfit(fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          if (_tiers.length > 1 || _isEditMode)
            IconButton(
              onPressed: () => _removeTier(index),
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Color(0xFFDC2626),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  // ── STOCK SECTION ──────────────────────────────────────────────────────────

  Widget _buildStockSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Stock', 'Quantité disponible'),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _stockController,
            label: 'Quantité en stock *',
            hintText: 'Ex: 50',
            prefixIcon: Icons.warehouse_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            errorText: _stockError,
            isValid: _stockValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Stock requis';
              final stock = int.tryParse(v);
              if (stock == null || stock < 0) return 'Stock invalide';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── LOCATION SECTION ───────────────────────────────────────────────────────

  Widget _buildLocationSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Localisation', 'Lieu de vente ou d\'expédition'),
          const SizedBox(height: 16),
          _buildValidatedFormField(
            controller: _lieuController,
            label: 'Lieu *',
            hintText: 'Ex: Cotonou, Akpakpa (Bénin)',
            prefixIcon: Icons.location_on_outlined,
            textCapitalization: TextCapitalization.words,
            errorText: _lieuError,
            isValid: _lieuValid,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requis';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── SUBMIT BUTTON ──────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: _isSuccess
              ? const LinearGradient(
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : const LinearGradient(
                  colors: [AppTheme.primary, Color(0xFFFF8C42)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (_isSuccess ? const Color(0xFF16A34A) : AppTheme.primary)
                  .withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: (_isSubmitting || _isSuccess) ? null : _submitForm,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : _isSuccess
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isEditMode ? 'Produit mis à jour !' : 'Produit publié !',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isEditMode
                              ? Icons.save_rounded
                              : Icons.rocket_launch_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isEditMode ? 'Enregistrer les modifications' : 'Publier le produit',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
