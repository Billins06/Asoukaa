import 'package:feexpay_flutter/feexpay_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/user_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/custom_image_widget.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController(text: 'Cotonou');
  final _notesController = TextEditingController();

  String _selectedCountry = 'Bénin';
  bool _saveAddress = true;
  bool _isPlacingOrder = false;
  bool _isLoadingProfile = true;
  bool _locationShared = false;
  double? _latitude;
  double? _longitude;

  // Cart data from arguments
  List<Map<String, dynamic>> _orderItems = [];
  double _subtotal = 0;
  double _promoDiscount = 0;
  double _deliveryFee = 2500;
  double _total = 0;

  // Created order ID (pending state before payment)
  String? _pendingOrderId;

  static const String _feexpayToken = String.fromEnvironment('FEEXPAY_API_KEY');
  static const String _feexpayShopId = String.fromEnvironment(
    'FEEXPAY_SHOP_ID',
  );

  final List<String> _countries = [
    'Bénin',
    'Togo',
    'Côte d\'Ivoire',
    'Burkina Faso',
    'Guinée',
    'Niger',
    'Sénégal',
    'Mali',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load cart args from navigation
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final cartItems = args['cartItems'];
      if (cartItems is List) {
        _orderItems = List<Map<String, dynamic>>.from(cartItems);
      }
      _subtotal = (args['subtotal'] as num? ?? 0).toDouble();
      _promoDiscount = (args['promoDiscount'] as num? ?? 0).toDouble();
      _deliveryFee = (args['deliveryFee'] as num? ?? 2500).toDouble();
      _total = (args['total'] as num? ?? 0).toDouble();
      if (_total == 0) _total = _subtotal + _deliveryFee - _promoDiscount;
    }
  }

  Future<void> _loadUserProfile() async {
    final isLoggedIn = await NestAuthService.instance.isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final result = await UserService.instance.getMyProfile();
      if (mounted && result.success && result.data != null) {
        final profile = result.data!;
        _firstNameController.text = profile.prenom;
        _lastNameController.text = profile.name;
        _phoneController.text = profile.phone;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingProfile = false);
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateTransKey() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'ASK${ts.substring(ts.length - 12)}';
  }

  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]} ',
        );
    return '$formatted FCFA';
  }

  Future<void> _shareLocation() async {
    setState(() {
      _locationShared = true;
      _latitude = 6.3703;
      _longitude = 2.3912;
    });
    AppToast.show(
      context,
      message: 'Localisation partagée avec le livreur',
      type: ToastType.success,
    );
  }

  // Crée l'adresse de livraison dans le backend et retourne son UUID.
  Future<String?> _createDeliveryAddress() async {
    try {
      final resp = await ApiService.instance.client.post(
        '/api/v1/users/me/addresses',
        data: {
          'label': 'Domicile',
          'nom_destinataire':
              '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
          'phone_destinataire': _phoneController.text.trim(),
          'quartier': _addressController.text.trim(),
          'ville': _cityController.text.trim(),
          'country': _selectedCountry,
          'isDefault': _saveAddress,
        },
      );
      final data = resp.data;
      return (data is Map) ? data['id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) {
      AppToast.show(
        context,
        message: 'Veuillez remplir tous les champs requis',
        type: ToastType.error,
      );
      return;
    }

    if (_orderItems.isEmpty) {
      AppToast.show(
        context,
        message: 'Votre panier est vide',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) {
          AppToast.show(
            context,
            message: 'Veuillez vous connecter',
            type: ToastType.error,
          );
          setState(() => _isPlacingOrder = false);
        }
        return;
      }

      // Étape 1 : créer l'adresse de livraison et récupérer son UUID
      final addressId = await _createDeliveryAddress();
      if (addressId == null) {
        if (mounted) {
          AppToast.show(
            context,
            message: 'Impossible de créer l\'adresse de livraison.',
            type: ToastType.error,
          );
          setState(() => _isPlacingOrder = false);
        }
        return;
      }

      // Étape 2 : créer la commande depuis le panier
      // Le backend lit le panier automatiquement — on envoie uniquement addressId.
      final instructions = _notesController.text.trim();
      _pendingOrderId = await _createOrder(
        addressId: addressId,
        instructions: instructions.isNotEmpty ? instructions : null,
      );

      // Mettre à jour le téléphone si demandé
      if (_saveAddress) {
        try {
          await UserService.instance.updateProfile(
            phone: _phoneController.text.trim(),
          );
        } catch (_) {}
      }

      setState(() => _isPlacingOrder = false);

      if (!mounted) return;

      final orderId = _pendingOrderId ?? _generateTransKey();

      final token = _feexpayToken.isNotEmpty
          ? _feexpayToken
          : 'fp_8Q22dR4r5omd6bBonmqjicDDzkuE3Vgg49bkWVuRvFKZbM4iG5BlcIa45lYocd2Y';
      final shopIdFee = _feexpayShopId.isNotEmpty
          ? _feexpayShopId
          : '6787b9c315c7bc2e9dbb906a';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChoicePage(
            token: token,
            id: shopIdFee,
            amount: _total.toInt().toString(),
            redirecturl: AppRoutes.feexpaySuccess,
            errorredirecturl: AppRoutes.feexpayError,
            trans_key: orderId,
          ),
        ),
      ).then((_) async {
        // FeexpayResultScreen gère la mise à jour du statut et le vidage du panier
      });
    } catch (e) {
      AppToast.show(
        context,
        message: 'Une erreur est survenue. Réessayez.',
        type: ToastType.error,
      );
      setState(() => _isPlacingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Finaliser la commande',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildStepIndicator(),
        ),
      ),
      body: _isLoadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      Icons.location_on_rounded,
                      'Adresse de livraison',
                    ),
                    const SizedBox(height: 12),
                    _buildShippingForm(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      Icons.payment_rounded,
                      'Mode de paiement',
                    ),
                    const SizedBox(height: 12),
                    _buildPaymentSection(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      Icons.receipt_long_rounded,
                      'Récapitulatif de commande',
                    ),
                    const SizedBox(height: 12),
                    _buildOrderReview(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildPlaceOrderBar(),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _stepDot(1, 'Panier', true),
          _stepLine(true),
          _stepDot(2, 'Livraison', true),
          _stepLine(false),
          _stepDot(3, 'Paiement', false),
        ],
      ),
    );
  }

  Widget _stepDot(int step, String label, bool completed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: completed ? AppTheme.primary : AppTheme.outline,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: completed
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : Text(
                    '$step',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
            color: completed ? AppTheme.primary : AppTheme.muted,
          ),
        ),
      ],
    );
  }

  Widget _stepLine(bool completed) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: completed ? AppTheme.primary : AppTheme.outline,
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildShippingForm() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _lastNameController,
                  label: 'Nom',
                  icon: Icons.person_outline_rounded,
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField(
                  controller: _firstNameController,
                  label: 'Prénom',
                  icon: Icons.person_outline_rounded,
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildCountryDropdown()),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField(
                  controller: _cityController,
                  label: 'Ville',
                  icon: Icons.location_city_outlined,
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _addressController,
            label: 'Adresse complète',
            icon: Icons.home_outlined,
            hint: 'Quartier et localisation précise',
            validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _phoneController,
            label: 'Téléphone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _notesController,
            label: 'Instructions de livraison (optionnel)',
            icon: Icons.notes_rounded,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _locationShared
                  ? const Color(0xFF10B981).withAlpha(15)
                  : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _locationShared
                    ? const Color(0xFF10B981).withAlpha(80)
                    : AppTheme.outline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _locationShared
                      ? Icons.location_on_rounded
                      : Icons.location_off_outlined,
                  color: _locationShared
                      ? const Color(0xFF10B981)
                      : AppTheme.muted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _locationShared
                            ? 'Localisation partagée'
                            : 'Partager ma localisation GPS',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _locationShared
                              ? const Color(0xFF10B981)
                              : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _locationShared
                            ? 'Le livreur peut voir votre position exacte'
                            : 'Permet au livreur de vous trouver facilement',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_locationShared)
                  ElevatedButton(
                    onPressed: _shareLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Partager',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => setState(() {
                      _locationShared = false;
                      _latitude = null;
                      _longitude = null;
                    }),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.muted,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _saveAddress,
                  onChanged: (v) => setState(() => _saveAddress = v ?? false),
                  activeColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: const BorderSide(color: AppTheme.outline),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sauvegarder cette adresse',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.muted),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
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
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.error),
        ),
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          color: AppTheme.textSecondary,
        ),
        hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
      ),
    );
  }

  Widget _buildCountryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCountry,
      onChanged: (v) => setState(() => _selectedCountry = v ?? 'Bénin'),
      style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: 'Pays',
        prefixIcon: const Icon(
          Icons.flag_outlined,
          size: 18,
          color: AppTheme.muted,
        ),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
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
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          color: AppTheme.textSecondary,
        ),
      ),
      items: _countries
          .map(
            (c) => DropdownMenuItem(
              value: c,
              child: Text(
                c,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildPaymentSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.payment_rounded, color: AppTheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paiement via FeeXPay',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Mobile Money (MTN, Moov, Wave...)',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Sécurisé',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderReview() {
    if (_orderItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Center(
          child: Text(
            'Panier vide — retournez au panier',
            style: GoogleFonts.outfit(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        children: [
          ..._orderItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == _orderItems.length - 1;
            final price = (item['price'] as num? ?? 0).toInt();
            final qty = item['quantity'] as int? ?? 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CustomImageWidget(
                          imageUrl: item['imageUrl'] as String? ?? '',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          semanticLabel:
                              item['semanticLabel'] as String? ??
                              'Produit dans la commande',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['name'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['shop'] as String? ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatPrice((price * qty).toDouble()),
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Qté: $qty',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  const Divider(height: 1, color: AppTheme.outlineVariant),
              ],
            );
          }),
          const Divider(height: 1, color: AppTheme.outline),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildPriceLine('Sous-total', _subtotal),
                if (_promoDiscount > 0) ...[
                  const SizedBox(height: 8),
                  _buildPriceLine(
                    'Réduction promo',
                    -_promoDiscount,
                    color: AppTheme.success,
                  ),
                ],
                const SizedBox(height: 8),
                _buildPriceLine('Livraison', _deliveryFee),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: AppTheme.outlineVariant),
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
                      _formatPrice(_total),
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
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.successContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: AppTheme.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Livraison estimée : 2–4 jours ouvrables',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.success,
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

  Widget _buildPriceLine(String label, double amount, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          amount < 0 ? '-${_formatPrice(-amount)}' : _formatPrice(amount),
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceOrderBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.outline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total à payer',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                _formatPrice(_total),
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isPlacingOrder ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF112C56),
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primaryLight,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isPlacingOrder
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Création de la commande...',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Payer avec FeeXPay',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _createOrder({
    required String addressId,
    String? instructions,
  }) async {
    final data = <String, dynamic>{'addressId': addressId};
    if (instructions != null && instructions.isNotEmpty) {
      data['instructions'] = instructions;
    }
    final response = await ApiService.instance.client.post(
      '/api/v1/orders',
      data: data,
    );
    final resData = response.data;
    if (resData is Map) {
      final orders = resData['orders'];
      if (orders is List && orders.isNotEmpty) {
        return (orders.first as Map<String, dynamic>?)?['id'] as String?;
      }
    }
    return null;
  }
}