import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_toast.dart';

class ImportAssisteScreen extends StatefulWidget {
  const ImportAssisteScreen({super.key});

  @override
  State<ImportAssisteScreen> createState() => _ImportAssisteScreenState();
}

class _ImportAssisteScreenState extends State<ImportAssisteScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import Assisté',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Importez depuis la Chine',
              style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.muted,
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
          tabs: const [
            Tab(text: '🛍️ Sélection Semaine'),
            Tab(text: '📦 Ma Commande'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_WeeklyCuratedTab(), _CustomOrderTab()],
      ),
    );
  }
}

// ─── Weekly Curated Products Tab ─────────────────────────────────────────────

class _WeeklyCuratedTab extends StatefulWidget {
  const _WeeklyCuratedTab();

  @override
  State<_WeeklyCuratedTab> createState() => _WeeklyCuratedTabState();
}

class _WeeklyCuratedTabState extends State<_WeeklyCuratedTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _weeklyProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final result = await SupabaseService.instance.client
          .from('import_assiste_products')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        final products = List<Map<String, dynamic>>.from(result as List);
        setState(() {
          _weeklyProducts = products.map((p) => _normalizeProduct(p)).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _weeklyProducts = [];
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) {
    return {
      'id': p['id'],
      'name': p['name'] ?? '',
      'origin': p['origin'] ?? 'Chine',
      'price': (p['price'] as num? ?? 0).toInt(),
      'originalPrice': (p['original_price'] as num? ?? p['price'] as num? ?? 0)
          .toInt(),
      'image': p['image_url'] ?? '',
      'description': p['description'] ?? '',
      'minOrder': p['min_order'] as int? ?? 1,
      'stock': p['stock'] as int? ?? 0,
      'badge': p['badge'] ?? '',
      'badgeColor': const Color(0xFF3B82F6),
      'deliveryDays': p['delivery_days'] ?? '12-18 jours',
    };
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🇨🇳 Sélection de la Semaine',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Prix négociés directement en Chine. Commandez et payez maintenant — livraison en 10-18 jours.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withAlpha(220),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flight_land_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${_weeklyProducts.length} produits disponibles cette semaine',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        ..._weeklyProducts.map(
          (p) => _WeeklyProductCard(product: p, formatPrice: _formatPrice),
        ),
      ],
    );
  }
}

class _WeeklyProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final String Function(int) formatPrice;

  const _WeeklyProductCard({required this.product, required this.formatPrice});

  @override
  State<_WeeklyProductCard> createState() => _WeeklyProductCardState();
}

class _WeeklyProductCardState extends State<_WeeklyProductCard> {
  int _quantity = 1;
  bool _isOrdering = false;

  Future<void> _placeOrder() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, '/sign-up-login-screen');
      return;
    }
    setState(() => _isOrdering = true);
    try {
      await SupabaseService.instance.client.from('import_requests').insert({
        'user_id': user.id,
        'description': widget.product['name'],
        'quantity': _quantity,
        'category': 'Électronique',
        'origin': 'Chine',
        'budget': '${widget.formatPrice(widget.product['price'] as int)} FCFA',
        'status': 'pending',
        'request_type': 'curated',
        'product_name': widget.product['name'],
        'unit_price': widget.product['price'],
      });
      if (mounted) {
        AppToast.show(
          context,
          message: 'Commande envoyée ! Nous vous contacterons sous 24h.',
          type: ToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de la commande. Réessayez.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isOrdering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final price = p['price'] as int;
    final originalPrice = p['originalPrice'] as int;
    final discount = (((originalPrice - price) / originalPrice) * 100).round();
    final badge = p['badge'] as String;
    final badgeColor = p['badgeColor'] as Color;
    final stock = p['stock'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image + badge
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Image.network(
                  p['image'] as String,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    color: AppTheme.surfaceVariant,
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppTheme.muted,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '-$discount%',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p['name'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  p['description'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 14,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Livraison: ${p['deliveryDays']}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: stock <= 10
                            ? const Color(0xFFFEF3C7)
                            : AppTheme.successContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$stock en stock',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: stock <= 10
                              ? const Color(0xFFD97706)
                              : AppTheme.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.formatPrice(price)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          '${widget.formatPrice(originalPrice)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Quantity selector
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_quantity > 1) setState(() => _quantity--);
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$_quantity',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (_quantity < stock) {
                                setState(() => _quantity++);
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.add_rounded,
                                size: 16,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isOrdering ? null : _placeOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isOrdering
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Commander — ${widget.formatPrice(price * _quantity)} FCFA',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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
  }
}

// ─── Custom Order Tab ─────────────────────────────────────────────────────────

class _CustomOrderTab extends StatefulWidget {
  const _CustomOrderTab();

  @override
  State<_CustomOrderTab> createState() => _CustomOrderTabState();
}

class _CustomOrderTabState extends State<_CustomOrderTab> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _urlController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _specsController = TextEditingController();
  String? _imageUrl;
  bool _isUploading = false;
  bool _isSubmitting = false;
  bool _isSubmitted = false;

  static const int _depositAmount = 10000;

  @override
  void dispose() {
    _descController.dispose();
    _urlController.dispose();
    _quantityController.dispose();
    _specsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 70,
    );
    if (picked == null) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = 'import_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await SupabaseService.instance.client.storage
          .from('product-images')
          .uploadBinary(fileName, bytes);
      final url = SupabaseService.instance.client.storage
          .from('product-images')
          .getPublicUrl(fileName);
      if (mounted) setState(() => _imageUrl = url);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Impossible d\'uploader l\'image. Réessayez.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, '/sign-up-login-screen');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.instance.client.from('import_requests').insert({
        'user_id': user.id,
        'product_url': _urlController.text.trim().isEmpty
            ? null
            : _urlController.text.trim(),
        'description': _descController.text.trim(),
        'quantity': int.tryParse(_quantityController.text.trim()) ?? 1,
        'category': 'Autre',
        'origin': 'Chine',
        'budget': 'À définir',
        'needs_customs': true,
        'needs_quality_check': true,
        'status': 'pending',
        'request_type': 'custom',
        'specs': _specsController.text.trim(),
        'deposit_amount': _depositAmount,
        'deposit_paid': false,
        if (_imageUrl != null) 'product_image_url': _imageUrl,
      });
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isSubmitted = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi. Réessayez.',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSubmitted) {
      return _SuccessView(onBack: () => setState(() => _isSubmitted = false));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withAlpha(60),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Comment ça marche ?',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _infoStep(
                    '1',
                    'Décrivez votre produit avec image et/ou lien',
                  ),
                  _infoStep('2', 'Payez 10 000 FCFA de dépôt de sourcing'),
                  _infoStep(
                    '3',
                    'Nous trouvons les meilleurs prix et vous envoyons un devis',
                  ),
                  _infoStep(
                    '4',
                    'Validez et payez le reste (moins le dépôt) ou annulez',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Décrivez votre produit *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: _inputDecoration(
                hint:
                    'Ex: Chaussures de sport Nike Air Max taille 42, couleur noir/blanc...',
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Description trop courte (min. 10 caractères)'
                  : null,
            ),
            const SizedBox(height: 16),
            _sectionTitle('Lien produit (optionnel)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _urlController,
              decoration: _inputDecoration(
                hint: 'https://www.alibaba.com/product/...',
                prefixIcon: Icons.link_rounded,
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Photo du produit (optionnel)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isUploading ? null : _pickImage,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _imageUrl != null
                        ? AppTheme.primary
                        : AppTheme.outline,
                    style: BorderStyle.solid,
                  ),
                ),
                child: _isUploading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      )
                    : _imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          _imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 32,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ajouter une photo',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Quantité *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(hint: '1'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return (n == null || n < 1)
                              ? 'Quantité invalide'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle('Spécifications (taille, couleur, matière...)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _specsController,
              maxLines: 2,
              decoration: _inputDecoration(
                hint: 'Ex: Taille L, couleur rouge, matière coton 100%...',
              ),
            ),
            const SizedBox(height: 24),
            // Deposit info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dépôt de sourcing: 10 000 FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          'Déduit du montant final si vous validez le devis.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Envoyer ma demande',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _infoStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: const Color(0xFF1E40AF),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: AppTheme.muted)
          : null,
      filled: true,
      fillColor: AppTheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ─── Success View ─────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final VoidCallback onBack;

  const _SuccessView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.successContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.success,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Demande envoyée !',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nous allons sourcer les meilleurs prix pour vous et vous envoyer un devis dans votre compte et par email sous 24-48h.',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Si vous validez le devis, le dépôt de 10 000 FCFA sera déduit du montant final.',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppTheme.muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Faire une autre demande',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Retour à l\'accueil',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
