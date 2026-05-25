import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/gps_tracking_service.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Live order status
  String _liveStatus = 'expedie';
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _positionChannel;

  // Deliverer live position
  double? _delivererLat;
  double? _delivererLng;
  bool _hasLivePosition = false;

  // Rating state
  bool _showRatingView = false;
  bool _ratingSubmitted = false;
  int _selectedRating = 0;
  final bool _isHoveringRating = false;
  final int _hoverRating = 0;
  final TextEditingController _ratingCommentController =
      TextEditingController();
  String _ratingPhotoUrl = '';
  bool _isUploadingRatingPhoto = false;
  bool _isSubmittingRating = false;

  // Status → step index mapping
  static const Map<String, int> _statusStepMap = {
    'en_attente': 0,
    'confirme': 0,
    'en_preparation': 1,
    'expedie': 2,
    'en_livraison': 3,
    'livre': 4,
  };

  int get _currentStep => _statusStepMap[_liveStatus] ?? 2;
  bool get _isDelivered => _liveStatus == 'livre';

  final List<_TrackingStep> _steps = [
    _TrackingStep(
      icon: Icons.check_circle_rounded,
      title: 'Commande confirmée',
      subtitle: 'Votre commande a été reçue et confirmée',
      time: 'Aujourd\'hui, 09:14',
    ),
    _TrackingStep(
      icon: Icons.inventory_2_rounded,
      title: 'En préparation',
      subtitle: 'Le vendeur prépare votre colis',
      time: 'Aujourd\'hui, 10:30',
    ),
    _TrackingStep(
      icon: Icons.local_shipping_rounded,
      title: 'Expédiée',
      subtitle: 'Votre colis a été remis au transporteur',
      time: 'Aujourd\'hui, 12:05',
    ),
    _TrackingStep(
      icon: Icons.route_rounded,
      title: 'En transit',
      subtitle: 'Votre colis est en route vers vous',
      time: 'Demain, estimé',
    ),
    _TrackingStep(
      icon: Icons.home_rounded,
      title: 'Livré',
      subtitle: 'Colis livré à l\'adresse indiquée',
      time: 'Dans 1–2 jours',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final orderId = args?['orderId'] as String?;
    final initialStatus = args?['status'] as String?;
    if (initialStatus != null) _liveStatus = initialStatus;
    if (orderId != null) {
      _subscribeToOrderStatus(orderId);
      _subscribeToDelivererPosition(orderId);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _ratingCommentController.dispose();
    _orderChannel?.unsubscribe();
    _positionChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToOrderStatus(String orderId) {
    _orderChannel = GpsTrackingService.instance.subscribeToOrderStatus(
      orderId: orderId,
      onStatusChange: (status) {
        if (!mounted) return;
        setState(() => _liveStatus = status);
        _showStatusNotification(status);
        if (status == 'livre') {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showRatingView = true);
          });
        }
      },
    );
  }

  void _subscribeToDelivererPosition(String orderId) {
    // Subscribe to any deliverer position updates for this order
    final channel = GpsTrackingService.instance.subscribeToDelivererPosition(
      delivererId:
          orderId, // fallback; real app would use deliverer_id from mission
      onPosition: (pos) {
        if (!mounted) return;
        setState(() {
          _delivererLat = (pos['latitude'] as num?)?.toDouble();
          _delivererLng = (pos['longitude'] as num?)?.toDouble();
          _hasLivePosition = true;
        });
      },
    );
    _positionChannel = channel;
  }

  void _showStatusNotification(String status) {
    final messages = {
      'confirme': '✅ Commande confirmée',
      'en_preparation': '📦 En cours de préparation',
      'expedie': '🚚 Commande expédiée',
      'en_livraison': '📍 Livreur en route',
      'livre': '🎉 Commande livrée !',
    };
    final msg = messages[status];
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: status == 'livre'
            ? AppTheme.success
            : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickRatingPhoto() async {
    final image = await StorageService.instance.pickImage(
      source: ImageSource.gallery,
    );
    if (image == null) return;
    setState(() => _isUploadingRatingPhoto = true);
    final url = await StorageService.instance.uploadDeliveryProof(
      image,
      'rating_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    setState(() {
      _isUploadingRatingPhoto = false;
      if (url != null) _ratingPhotoUrl = url;
    });
  }

  Future<void> _submitRating(String orderId) async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez sélectionner une note',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSubmittingRating = true);
    final userId = AuthService.instance.currentUser?.id ?? '';
    final success = await GpsTrackingService.instance.submitDeliveryRating(
      orderId: orderId,
      buyerId: userId,
      rating: _selectedRating,
      comment: _ratingCommentController.text.trim(),
      photoUrl: _ratingPhotoUrl,
    );
    if (!mounted) return;
    setState(() {
      _isSubmittingRating = false;
      if (success) _ratingSubmitted = true;
    });
    if (success) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final String orderNumber =
        args?['orderNumber'] as String? ??
        'ASK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final String firstName = args?['firstName'] as String? ?? 'Aminata';
    final String lastName = args?['lastName'] as String? ?? 'Konaté';
    final String address =
        args?['address'] as String? ?? 'Rue 42, Badalabougou';
    final String city = args?['city'] as String? ?? 'Bamako';
    final String country = args?['country'] as String? ?? 'Mali';
    final String phone = args?['phone'] as String? ?? '+223 76 00 00 00';

    final deliveryDate = DateTime.now().add(const Duration(days: 2));
    final deliveryDateStr =
        '${deliveryDate.day} ${_monthName(deliveryDate.month)} ${deliveryDate.year}';

    // Generate a unique QR data string for this order
    final String qrData = 'ASK-$orderNumber-${city.toUpperCase()}-2026';

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Suivi de commande',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Text(
              '#$orderNumber',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status banner
              _buildStatusBanner(),
              SizedBox(height: 2.h),

              // Live GPS position card (shown when deliverer is in transit)
              if (_liveStatus == 'en_livraison') ...[
                _buildGpsTrackingCard(),
                SizedBox(height: 2.h),
              ],

              // Estimated delivery card
              _buildDeliveryCard(deliveryDateStr),
              SizedBox(height: 2.h),

              // QR Code section
              _buildSectionTitle('QR Code de la commande'),
              SizedBox(height: 1.5.h),
              _buildQrCodeCard(orderNumber, qrData),
              SizedBox(height: 2.h),

              // Step-by-step progression
              _buildSectionTitle('Progression de la livraison'),
              SizedBox(height: 1.5.h),
              _buildStepperCard(),
              SizedBox(height: 2.h),

              // Carrier info
              _buildSectionTitle('Transporteur'),
              SizedBox(height: 1.5.h),
              _buildCarrierCard(),
              SizedBox(height: 2.h),

              // Delivery address
              _buildSectionTitle('Adresse de livraison'),
              SizedBox(height: 1.5.h),
              _buildAddressCard(
                firstName,
                lastName,
                address,
                city,
                country,
                phone,
              ),
              SizedBox(height: 2.h),

              // Rating section — shown after delivery
              if (_isDelivered) ...[
                _buildSectionTitle('Évaluer la livraison'),
                SizedBox(height: 1.5.h),
                _buildRatingCard(orderNumber),
                SizedBox(height: 2.h),
              ],

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
                  },
                  icon: const Icon(Icons.home_rounded, size: 20),
                  label: Text(
                    'Retour à l\'accueil',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 2.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final statusLabels = {
      'en_attente': (
        'En attente',
        'Votre commande est en attente de confirmation',
      ),
      'confirme': ('Commande confirmée', 'Votre commande a été confirmée'),
      'en_preparation': ('En préparation', 'Le vendeur prépare votre colis'),
      'expedie': ('Colis expédié', 'Votre colis est en route vers vous'),
      'en_livraison': ('En cours de livraison', 'Le livreur est en route'),
      'livre': ('Commande livrée !', 'Votre colis a été livré avec succès'),
    };
    final label =
        statusLabels[_liveStatus] ?? ('En cours', 'Suivi en temps réel');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDelivered
              ? [const Color(0xFF22C55E), const Color(0xFF16A34A)]
              : [const Color(0xFFFF6210), const Color(0xFFFF8C42)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: (_isDelivered ? AppTheme.success : AppTheme.primary)
                .withAlpha(50),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isDelivered
                  ? Icons.check_circle_rounded
                  : Icons.local_shipping_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.$1,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label.$2,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.white.withAlpha(220),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsTrackingCard() {
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _hasLivePosition
                      ? AppTheme.successContainer
                      : AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: _hasLivePosition ? AppTheme.success : AppTheme.primary,
                  size: 22,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Position du livreur',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _hasLivePosition
                          ? 'Mise à jour en temps réel'
                          : 'En attente de la position GPS...',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasLivePosition)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_hasLivePosition &&
              _delivererLat != null &&
              _delivererLng != null) ...[
            SizedBox(height: 1.5.h),
            // Live map
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(_delivererLat!, _delivererLng!),
                    initialZoom: 15,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.asoukaa.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_delivererLat!, _delivererLng!),
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withAlpha(100),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.delivery_dining_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 1.h),
            // ETA row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCoordInfo(
                    'Latitude',
                    _delivererLat!.toStringAsFixed(4),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppTheme.outlineVariant,
                  ),
                  _buildCoordInfo(
                    'Longitude',
                    _delivererLng!.toStringAsFixed(4),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppTheme.outlineVariant,
                  ),
                  _buildCoordInfo('Arrivée', '~15 min'),
                ],
              ),
            ),
          ] else ...[
            SizedBox(height: 1.5.h),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Localisation du livreur...',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordInfo(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 10, color: AppTheme.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingCard(String orderNumber) {
    if (_ratingSubmitted) {
      return _InfoCard(
        child: Column(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 48),
            const SizedBox(height: 12),
            Text(
              'Merci pour votre avis !',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Votre évaluation a été soumise.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (i) => Icon(
                  i < _selectedRating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF59E0B),
                  size: 22,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Évaluer la livraison',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Partagez votre expérience',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),

          // Star rating
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = starIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starIndex <= _selectedRating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: const Color(0xFFF59E0B),
                      size: 40,
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_selectedRating > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                _ratingLabel(_selectedRating),
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ),
          ],
          SizedBox(height: 2.h),

          // Comment
          Text(
            'Commentaire (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ratingCommentController,
            maxLines: 3,
            style: GoogleFonts.outfit(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Décrivez votre expérience de livraison...',
              hintStyle: GoogleFonts.outfit(
                color: AppTheme.muted,
                fontSize: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: AppTheme.background,
            ),
          ),
          SizedBox(height: 1.5.h),

          // Photo upload
          Text(
            'Ajouter une photo (optionnel)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isUploadingRatingPhoto ? null : _pickRatingPhoto,
            child: Container(
              height: _ratingPhotoUrl.isNotEmpty ? 140 : 72,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _ratingPhotoUrl.isNotEmpty
                      ? AppTheme.success
                      : AppTheme.outlineVariant,
                ),
              ),
              child: _isUploadingRatingPhoto
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _ratingPhotoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(
                        _ratingPhotoUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        semanticLabel:
                            'Photo de preuve pour l\'évaluation de livraison',
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppTheme.muted,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
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
          SizedBox(height: 2.h),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isSubmittingRating || _selectedRating == 0)
                  ? null
                  : () => _submitRating(orderNumber),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.outlineVariant,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmittingRating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Soumettre l\'évaluation',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Très mauvais';
      case 2:
        return 'Mauvais';
      case 3:
        return 'Correct';
      case 4:
        return 'Bien';
      case 5:
        return 'Excellent !';
      default:
        return '';
    }
  }

  Widget _buildDeliveryCard(String deliveryDateStr) {
    return _InfoCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: AppTheme.warning,
              size: 20,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Livraison estimée',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  deliveryDateStr,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.warningContainer,
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Text(
              '1–2 jours',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperCard() {
    return _InfoCard(
      child: Column(
        children: List.generate(_steps.length, (index) {
          final step = _steps[index];
          final isCompleted = index < _currentStep;
          final isActive = index == _currentStep;
          final isPending = index > _currentStep;
          final isLast = index == _steps.length - 1;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _buildStepIcon(step.icon, isCompleted, isActive, isPending),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 48,
                      color: isCompleted
                          ? AppTheme.primary
                          : AppTheme.outlineVariant,
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              step.title,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: isActive || isCompleted
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isPending
                                    ? AppTheme.muted
                                    : AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                              child: Text(
                                'Actuel',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: isPending
                              ? AppTheme.muted
                              : AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.time,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? AppTheme.primary
                              : isPending
                              ? AppTheme.muted
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepIcon(
    IconData icon,
    bool isCompleted,
    bool isActive,
    bool isPending,
  ) {
    Color bgColor;
    Color iconColor;
    if (isCompleted) {
      bgColor = AppTheme.primary;
      iconColor = Colors.white;
    } else if (isActive) {
      bgColor = AppTheme.primaryContainer;
      iconColor = AppTheme.primary;
    } else {
      bgColor = AppTheme.outlineVariant;
      iconColor = AppTheme.muted;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: AppTheme.primary, width: 2) : null,
      ),
      child: Icon(
        isCompleted ? Icons.check_rounded : icon,
        color: iconColor,
        size: 18,
      ),
    );
  }

  Widget _buildCarrierCard() {
    return _InfoCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: const Icon(
                  Icons.directions_bike_rounded,
                  color: AppTheme.primary,
                  size: 26,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Asoukaa Express',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Livraison rapide & sécurisée',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.successContainer,
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Text(
                  'Actif',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 1.5.h),
          const Divider(color: AppTheme.outlineVariant, height: 1),
          SizedBox(height: 1.5.h),
          Row(
            children: [
              _buildCarrierDetail(
                Icons.confirmation_number_rounded,
                'N° de suivi',
                'ASK-TRK-7842',
              ),
              SizedBox(width: 4.w),
              _buildCarrierDetail(
                Icons.phone_rounded,
                'Contact',
                '+223 20 22 00 00',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCarrierDetail(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(
    String firstName,
    String lastName,
    String address,
    String city,
    String country,
    String phone,
  ) {
    return _InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 2),
                Text(
                  '$city, $country',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
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
    );
  }

  Widget _buildQrCodeCard(String orderNumber, String qrData) {
    return _InfoCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QR Code de livraison',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'À présenter au livreur lors de la réception',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: PrettyQrView.data(
                data: qrData,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(color: Color(0xFF1A1A2E)),
                ),
                errorCorrectLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          SizedBox(height: 1.5.h),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.tag_rounded,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  qrData,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Code copié !',
                          style: GoogleFonts.outfit(),
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  },
                  child: const Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'jan.',
      'fév.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    return months[month - 1];
  }
}

class _TrackingStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  const _TrackingStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}