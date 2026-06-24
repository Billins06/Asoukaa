import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
import '../../widgets/app_toast.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = true;
  final bool _isUpdating = false;

  String _promoCode = '';
  bool _promoApplied = false;
  double _promoDiscount = 0;
  final TextEditingController _promoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _loadCart() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.client.get('/api/v1/cart');
      final rawData = response.data;
      List<dynamic> rawList;
      if (rawData is List) {
        rawList = rawData;
      } else if (rawData is Map) {
        rawList = (rawData['items'] ??
                rawData['cartItems'] ??
                rawData['data'] ??
                []) as List<dynamic>;
      } else {
        rawList = [];
      }
      if (mounted) {
        setState(() {
          _cartItems = rawList
              .whereType<Map>()
              .map((e) => _normalizeCartItem(Map<String, dynamic>.from(e)))
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _normalizeCartItem(Map<String, dynamic> item) {
    final product =
        (item['product'] ?? item['products']) as Map<String, dynamic>?;
    if (product == null) return item;

    final images = product['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map) {
        imageUrl = first['url'] as String? ?? first['imageUrl'] as String? ?? '';
      } else if (first is String) {
        imageUrl = first;
      }
    }
    if (imageUrl.isEmpty) {
      imageUrl = product['imageUrl'] as String? ?? product['image_url'] as String? ?? '';
    }
    if (imageUrl.isEmpty) {
      imageUrl = 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
    }

    final shopData = product['shops'] ?? product['vendeur'] ?? product['shop_info'];
    final shopName = shopData is Map
        ? (shopData['shopName'] as String? ?? shopData['name'] as String? ?? 'Boutique')
        : (product['shop'] as String? ?? 'Boutique');
    final shopId = shopData is Map ? (shopData['id'] as String? ?? '') : '';

    final price = (product['price'] as num? ?? 0).toInt();
    final originalPrice =
        (product['original_price'] as num? ?? product['originalPrice'] as num? ?? price)
            .toInt();
    final stockQty =
        product['stock_quantity'] as int? ?? product['stockQuantity'] as int? ?? 10;

    return {
      'id': item['id'] ?? '',
      'product_id': product['id'] ?? item['productId'] ?? '',
      'name': product['name'] ?? '',
      'shop': shopName,
      'shop_id': shopId,
      'price': price,
      'originalPrice': originalPrice,
      'quantity': item['quantity'] as int? ?? 1,
      'imageUrl': imageUrl,
      'semanticLabel': 'Produit ${product['name'] ?? ''} dans le panier Asoukaa',
      'inStock': stockQty > 0,
      'stockQty': stockQty,
    };
  }

  int get _itemCount =>
      _cartItems.fold(0, (sum, item) => sum + (item['quantity'] as int));

  double get _subtotal => _cartItems.fold(
    0,
    (sum, item) =>
        sum + (item['price'] as int) * (item['quantity'] as int).toDouble(),
  );

  double get _savings => _cartItems.fold(
    0,
    (sum, item) =>
        sum +
        ((item['originalPrice'] as int) - (item['price'] as int)) *
            (item['quantity'] as int).toDouble(),
  );

  double get _deliveryFee => _subtotal > 50000 ? 0 : 2500;

  double get _total => _subtotal - _promoDiscount + _deliveryFee;

  Future<void> _incrementQty(int index) async {
    final item = _cartItems[index];
    final newQty = (item['quantity'] as int) + 1;
    final stockQty = item['stockQty'] as int? ?? 99;
    if (newQty > stockQty) {
      AppToast.show(
        context,
        message: 'Stock insuffisant (max $stockQty)',
        type: ToastType.info,
      );
      return;
    }
    setState(() => _cartItems[index]['quantity'] = newQty);
    await _updateQtyInDb(item['id'] as String, newQty);
  }

  Future<void> _decrementQty(int index) async {
    final item = _cartItems[index];
    final qty = item['quantity'] as int;
    if (qty > 1) {
      final newQty = qty - 1;
      setState(() => _cartItems[index]['quantity'] = newQty);
      await _updateQtyInDb(item['id'] as String, newQty);
    } else {
      _confirmRemove(index);
    }
  }

  Future<void> _updateQtyInDb(String cartItemId, int qty) async {
    try {
      await ApiService.instance.client.patch(
        '/api/v1/cart/items/$cartItemId',
        data: {'quantity': qty},
      );
    } catch (_) {}
  }

  Future<void> _removeItem(int index) async {
    final item = _cartItems[index];
    final cartItemId = item['id'] as String;
    setState(() => _cartItems.removeAt(index));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item['name']} retiré du panier'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await ApiService.instance.client.delete('/api/v1/cart/items/$cartItemId');
    } catch (_) {}
  }

  void _confirmRemove(int index) {
    final item = _cartItems[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(
              Icons.delete_outline_rounded,
              size: 44,
              color: AppTheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Retirer cet article ?',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item['name'] as String,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      final idx = _cartItems.indexWhere(
                        (i) => i['id'] == item['id'],
                      );
                      if (idx != -1) _removeItem(idx);
                    },
                    child: const Text('Retirer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCart() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!isLoggedIn) return;
    setState(() => _cartItems.clear());
    try {
      await ApiService.instance.client.delete('/api/v1/cart');
    } catch (_) {}
  }

  void _applyPromo() {
    if (_promoController.text.trim().toUpperCase() == 'ASOUKAA10') {
      setState(() {
        _promoApplied = true;
        _promoDiscount = _subtotal * 0.10;
        _promoCode = _promoController.text.trim().toUpperCase();
      });
      AppToast.show(
        context,
        message: 'Code promo appliqué — 10% de réduction',
        type: ToastType.success,
      );
    } else {
      AppToast.show(
        context,
        message: 'Code promo invalide',
        type: ToastType.error,
      );
    }
  }

  void _proceedToCheckout() {
    final inStockItems = _cartItems.where((i) => i['inStock'] == true).toList();
    if (inStockItems.isEmpty) {
      AppToast.show(
        context,
        message: 'Aucun article disponible en stock pour commander',
        type: ToastType.error,
      );
      return;
    }

    // Enforce single-shop constraint
    final shopIds = inStockItems
        .map((i) => i['shop_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (shopIds.length > 1) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Articles de plusieurs boutiques',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Une commande ne peut contenir des articles que d\'une seule boutique. Veuillez retirer les articles des autres boutiques avant de continuer.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Compris',
                style: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Pass cart items to checkout
    Navigator.pushNamed(
      context,
      AppRoutes.checkout,
      arguments: {
        'cartItems': inStockItems,
        'subtotal': _subtotal,
        'promoDiscount': _promoDiscount,
        'deliveryFee': _deliveryFee,
        'total': _total,
      },
    );
  }

  String _formatPrice(double price) {
    final p = price.toInt();
    return p.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 15 : 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              color: isBold ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mon Panier',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (_cartItems.isNotEmpty)
              Text(
                '$_itemCount article${_itemCount > 1 ? 's' : ''}',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          if (_cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Text(
                      'Vider le panier ?',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                    content: Text(
                      'Tous les articles seront retirés.',
                      style: GoogleFonts.outfit(color: AppTheme.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _clearCart();
                        },
                        child: Text(
                          'Vider',
                          style: GoogleFonts.outfit(color: AppTheme.error),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: Text(
                'Vider',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _cartItems.isEmpty
          ? _buildEmptyCart()
          : isTablet
          ? _buildTabletLayout()
          : _buildPhoneLayout(),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Votre panier est vide',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez des articles pour commencer vos achats',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Découvrir les produits'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _loadCart,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                ..._cartItems.asMap().entries.map(
                  (e) => _buildCartItem(e.key, e.value),
                ),
                const SizedBox(height: 8),
                _buildPromoSection(),
                const SizedBox(height: 8),
                _buildPriceSummary(),
                const SizedBox(height: 8),
                _buildDeliveryNote(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _buildCheckoutBar(),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: _cartItems
                .asMap()
                .entries
                .map((e) => _buildCartItem(e.key, e.value))
                .toList(),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 340,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildPromoSection(),
                    const SizedBox(height: 12),
                    _buildPriceSummary(),
                    const SizedBox(height: 12),
                    _buildDeliveryNote(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildCheckoutButton(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartItem(int index, Map<String, dynamic> item) {
    final bool inStock = item['inStock'] as bool? ?? true;
    final int qty = item['quantity'] as int;
    final int price = item['price'] as int;
    final int originalPrice = item['originalPrice'] as int;
    final bool hasDiscount = originalPrice > price;

    return Dismissible(
      key: Key(item['id'] as String),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppTheme.error,
          size: 26,
        ),
      ),
      confirmDismiss: (_) async {
        _confirmRemove(index);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: inStock ? AppTheme.outline : AppTheme.errorContainer,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomImageWidget(
                    imageUrl: item['imageUrl'] as String,
                    fit: BoxFit.cover,
                    semanticLabel: item['semanticLabel'] as String,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item['name'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _confirmRemove(index),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['shop'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (!inStock)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Rupture de stock',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatPrice((price * qty).toDouble())} FCFA',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                              if (hasDiscount)
                                Text(
                                  '${_formatPrice((originalPrice * qty).toDouble())} FCFA',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: AppTheme.muted,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _qtyButton(
                                icon: qty == 1
                                    ? Icons.delete_outline_rounded
                                    : Icons.remove_rounded,
                                color: qty == 1
                                    ? AppTheme.error
                                    : AppTheme.textPrimary,
                                onTap: () => _decrementQty(index),
                              ),
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '$qty',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              _qtyButton(
                                icon: Icons.add_rounded,
                                color: AppTheme.primary,
                                onTap: () => _incrementQty(index),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildPromoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_offer_outlined,
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Code promo',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_promoApplied)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.successContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppTheme.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Code "$_promoCode" appliqué — 10% de réduction',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _promoApplied = false;
                        _promoDiscount = 0;
                        _promoCode = '';
                        _promoController.clear();
                      });
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promoController,
                    textCapitalization: TextCapitalization.characters,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Entrez votre code',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _applyPromo,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Appliquer',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPriceSummary() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Récapitulatif',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          _summaryRow(
            'Sous-total ($_itemCount article${_itemCount > 1 ? 's' : ''})',
            '${_formatPrice(_subtotal)} FCFA',
          ),
          if (_savings > 0)
            _summaryRow(
              'Économies',
              '-${_formatPrice(_savings)} FCFA',
              valueColor: AppTheme.success,
            ),
          if (_promoApplied)
            _summaryRow(
              'Code promo',
              '-${_formatPrice(_promoDiscount)} FCFA',
              valueColor: AppTheme.success,
            ),
          _summaryRow(
            'Livraison',
            _deliveryFee == 0 ? 'Gratuite' : '${_deliveryFee.toInt()} FCFA',
            valueColor: _deliveryFee == 0 ? AppTheme.success : null,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '${_formatPrice(_total)} FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryNote() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _deliveryFee == 0
            ? AppTheme.successContainer
            : AppTheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _deliveryFee == 0
                ? Icons.local_shipping_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: _deliveryFee == 0 ? AppTheme.success : AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _deliveryFee == 0
                  ? 'Livraison gratuite pour cette commande !'
                  : 'Ajoutez ${_formatPrice(50000 - _subtotal)} FCFA pour la livraison gratuite',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _deliveryFee == 0 ? AppTheme.success : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(top: false, child: _buildCheckoutButton()),
    );
  }

  Widget _buildCheckoutButton() {
    final inStockCount = _cartItems.where((i) => i['inStock'] == true).length;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: inStockCount > 0 ? _proceedToCheckout : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'Passer la commande',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_formatPrice(_total)} FCFA',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}