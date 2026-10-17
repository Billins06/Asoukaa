import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:sizer/sizer.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/upload_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String _liveStatus = 'en attente';
  // Libellés d'une commande « en attente » (mêmes textes que la liste des
  // commandes de buyer_dashboard_screen.dart).
  static const String _libelleConfVendeur =
      'En attente de confirmation du vendeur';
  static const String _libellePaiement = 'En attente de paiement';
  static const String _libelleNeutre = 'En attente';

  // Libellé précis d'une commande « en attente » (paiement réussi ou non).
  // Transmis par l'écran appelant s'il le connaît ; sinon déduit du paiement
  // renvoyé par le serveur dans le détail de la commande
  // (GET /orders/me/:id → `payment`). Null/« En attente » = on reste neutre.
  String? _pendingLabel;
  // Vrai si le libellé vient de l'écran appelant (on ne l'écrase alors pas) ;
  // faux s'il est déduit du serveur (recalculé à chaque rafraîchissement).
  bool _pendingLabelFromArgs = false;
  String? _productId;
  Timer? _statusPollTimer;

  // Vraie commande recuperee depuis le serveur (adresse reelle avec sa
  // position GPS, livraison + livreur assigne). Reste null tant que la
  // premiere requete n'a pas abouti : on affiche alors les valeurs par
  // defaut/arguments de navigation comme avant.
  Map<String, dynamic>? _realOrder;

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
  bool _isSubmittingRating = false;
  bool _isSubmittingBusTaxiAction = false;

  // Status → step index mapping
  static const Map<String, int> _statusStepMap = {
    'en attente': 0,
    'en cours': 1,
    'livreur affecté': 1,
    'expedié': 2,
    'en transit': 3,
    'livré': 4,
  };

  int get _currentStep => _statusStepMap[_liveStatus] ?? 0;
  bool get _isDelivered => _liveStatus == 'livré';

  final List<_TrackingStep> _steps = [
    _TrackingStep(
      icon: Icons.check_circle_rounded,
      title: 'Commande reçue',
      // Texte de repli : l'affichage réel dépend du paiement, voir
      // _sousTitreCommandeRecue().
      subtitle: 'Votre commande est enregistrée et transmise au vendeur',
    ),
    _TrackingStep(
      icon: Icons.inventory_2_rounded,
      title: 'En préparation',
      subtitle: 'Le vendeur a confirmé et prépare votre colis',
    ),
    _TrackingStep(
      icon: Icons.local_shipping_rounded,
      title: 'Expédiée',
      subtitle: 'Votre colis a été remis au transporteur',
    ),
    _TrackingStep(
      icon: Icons.route_rounded,
      title: 'En transit',
      subtitle: 'Votre colis est en route vers vous',
    ),
    _TrackingStep(
      icon: Icons.home_rounded,
      title: 'Livré',
      subtitle: 'Colis livré à l\'adresse indiquée',
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
    _productId = args?['productId'] as String?;
    final argLabel = args?['pendingLabel'] as String?;
    _pendingLabel = argLabel;
    // Un libellé précis transmis par l'appelant est conservé ; null, vide ou
    // « En attente » (neutre) = on le déduira du paiement renvoyé par le serveur.
    _pendingLabelFromArgs =
        argLabel != null && argLabel.isNotEmpty && argLabel != _libelleNeutre;
    if (initialStatus != null) _liveStatus = initialStatus;
    // didChangeDependencies peut être appelé plusieurs fois (changement de
    // thème/locale, etc.) : on ne démarre le polling qu'une seule fois pour
    // éviter d'empiler plusieurs Timer.periodic concurrents.
    if (orderId != null && _statusPollTimer == null) {
      _startStatusPolling(orderId);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _ratingCommentController.dispose();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  void _startStatusPolling(String orderId) {
    // Premiere recuperation immediate : sans ca, la page afficherait des
    // donnees fictives pendant les 15 premieres secondes.
    _fetchOrderDetails(orderId);
    _statusPollTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      await _fetchOrderDetails(orderId, timer: timer);
    });
  }

  Future<void> _fetchOrderDetails(String orderId, {Timer? timer}) async {
      try {
        final response =
            await ApiService.instance.client.get('/api/v1/orders/me/$orderId');
        final data = response.data as Map<String, dynamic>?;
        if (data == null || !mounted) return;
        final status = data['status'] as String?;
        final statusChanged = status != null && status != _liveStatus;
        setState(() {
          _realOrder = data;
          if (status != null) _liveStatus = status;
          // Libellé d'attente non transmis : déduit de `data['payment']`.
          if (!_pendingLabelFromArgs && _liveStatus == 'en attente') {
            _pendingLabel = _libelleAttenteDepuisCommande(data);
          }
        });
        if (statusChanged) {
          _showStatusNotification(status!);
          if (status == 'livré') {
            timer?.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _showRatingView = true);
            });
          }
        }
      } catch (e) {
        // Commande introuvable (404) ou erreur définitive : on arrête le
        // polling plutôt que d'interroger indéfiniment un écran qui n'est
        // peut-être plus visible (ex. resté vivant plus bas dans la pile
        // de navigation).
        if (e is DioException && e.response?.statusCode == 404) {
          timer?.cancel();
        }
      }
  }

  // Même règle que la liste des commandes (buyer_dashboard_screen.dart) :
  // paiement réussi (ou paiement à la livraison en attente) → c'est au vendeur
  // de confirmer ; sinon → en attente de paiement ; si la réponse ne contient
  // pas du tout la clé `payment` → neutre « En attente ».
  static String _libelleAttenteDepuisCommande(Map<String, dynamic> data) {
    if (!data.containsKey('payment')) return _libelleNeutre;
    final payment = data['payment'];
    String? paymentStatus;
    String? payMethod;
    if (payment is Map) {
      final s = payment['status'];
      final m = payment['method'];
      paymentStatus = s is String ? s : null;
      payMethod = m is String ? m : null;
    }
    final auVendeur = paymentStatus == 'success' ||
        (payMethod == 'cash_on_delivery' && paymentStatus == 'en attente');
    return auVendeur ? _libelleConfVendeur : _libellePaiement;
  }

  // Sous-titre de l'étape « Commande reçue » : « transmise au vendeur »
  // seulement si le paiement est réussi (ou si la commande a déjà avancé).
  String _sousTitreCommandeRecue() {
    if (_liveStatus == 'annulé') return 'Votre commande a été enregistrée';
    if (_liveStatus != 'en attente') {
      return 'Votre commande est enregistrée et transmise au vendeur';
    }
    if (_pendingLabel == _libelleConfVendeur) {
      return 'Votre commande est enregistrée et transmise au vendeur';
    }
    if (_pendingLabel == _libellePaiement) {
      return 'Votre commande est enregistrée : réglez-la pour qu\'elle soit transmise au vendeur';
    }
    return 'Votre commande est enregistrée';
  }

  String _messageCommandeEnAttente() {
    if (_pendingLabel == _libelleConfVendeur) {
      return '🕓 Commande transmise au vendeur';
    }
    if (_pendingLabel == _libellePaiement) {
      return '🕓 Commande enregistrée, en attente de paiement';
    }
    return '🕓 Commande enregistrée';
  }

  void _showStatusNotification(String status) {
    final messages = {
      'en attente': _messageCommandeEnAttente(),
      'en cours': '✅ Commande confirmée par le vendeur, en préparation',
      'livreur affecté': '🚴 Livreur affecté',
      'expedié': '🚚 Commande expédiée',
      'en transit': '📍 Livreur en route',
      'livré': '🎉 Commande livrée !',
      'annulé': '❌ Commande annulée',
    };
    final msg = messages[status];
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: status == 'livré'
            ? AppTheme.success
            : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickRatingPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _ratingPhotoUrl = image.path);
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
    if (orderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Commande introuvable, réessayez depuis le suivi de commande',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final productId = _productId;
    if (productId == null || productId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Produit introuvable pour cette commande',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSubmittingRating = true);
    try {
      // Le backend n'expose pas de route "/orders/:id/rating" — les avis
      // passent par le module Reviews (POST /reviews), qui vérifie que la
      // commande est bien livrée et appartient à l'utilisateur avant
      // d'enregistrer l'avis (statut PENDING, en attente de modération).
      await ApiService.instance.client.post(
        '/api/v1/reviews',
        data: {
          'productId': productId,
          'orderId': orderId,
          'notation': _selectedRating,
          'comment': _ratingCommentController.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        _isSubmittingRating = false;
        _ratingSubmitted = true;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingRating = false);
      String message = 'Erreur lors de l\'envoi de votre avis';
      if (e is DioException) {
        final data = e.response?.data;
        final serverMessage = data is Map ? data['message'] : null;
        if (serverMessage is String) {
          message = serverMessage;
        } else if (serverMessage is List && serverMessage.isNotEmpty) {
          message = serverMessage.first.toString();
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    // Tant que la vraie commande n'est pas encore arrivée du serveur
    // (_realOrder == null), on affiche les arguments de navigation reçus
    // de l'écran précédent — dès qu'elle arrive, ses champs prennent le
    // dessus partout ci-dessous.
    final realAddress = _realOrder?['address'] as Map<String, dynamic>?;
    final realDelivery = _realOrder?['delivery'] as Map<String, dynamic>?;
    final realAgentUser =
        (realDelivery?['agent'] as Map<String, dynamic>?)?['user']
            as Map<String, dynamic>?;

    final String orderNumber =
        (_realOrder?['orderNumber'] as String?) ??
        args?['orderNumber'] as String? ??
        'ASK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final String recipientName =
        (realAddress?['nom_destinataire'] as String?) ??
        '${args?['firstName'] ?? 'Aminata'} ${args?['lastName'] ?? 'Konaté'}';
    final String address =
        (realAddress?['quartier'] as String?) ??
        args?['address'] as String? ?? 'Rue 42, Badalabougou';
    final String city =
        (realAddress?['ville'] as String?) ??
        args?['city'] as String? ?? 'Bamako';
    final String country =
        (realAddress?['country'] as String?) ??
        args?['country'] as String? ?? 'Mali';
    final String phone =
        (realAddress?['phone_destinataire'] as String?) ??
        args?['phone'] as String? ?? '+223 76 00 00 00';
    final double? addressLat = (realAddress?['latitude'] as num?)?.toDouble();
    final double? addressLng = (realAddress?['longitude'] as num?)?.toDouble();

    final deliveryDate = DateTime.now().add(const Duration(days: 2));
    final deliveryDateStr =
        '${deliveryDate.day} ${_monthName(deliveryDate.month)} ${deliveryDate.year}';

    // Code de remise : secret aléatoire fourni par le serveur
    // (GET /orders/me/:id -> handoverCode, visible seulement par le client
    // propriétaire). Le QR encode CE code, plus le numéro de commande. Null
    // tant que le serveur ne le fournit pas : aucun QR, aucun repli.
    final dynamic rawHandover = _realOrder?['handoverCode'];
    final String? handoverCode =
        (rawHandover == null || '$rawHandover'.trim().isEmpty)
            ? null
            : '$rawHandover'.trim();

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
              if (_liveStatus == 'en transit') ...[
                _buildGpsTrackingCard(),
                SizedBox(height: 2.h),
              ],

              // Cas C (bus/taxi) — confirmation ou contestation de
              // réception, uniquement pendant la fenêtre des 3 jours.
              if ((_realOrder?['transportMode'] != null) &&
                  _liveStatus == 'expedié' &&
                  _realOrder?['disputeOuverte'] != true) ...[
                _buildBusTaxiConfirmationCard(),
                SizedBox(height: 2.h),
              ],
              if (_realOrder?['disputeOuverte'] == true) ...[
                _buildDisputeOpenCard(),
                SizedBox(height: 2.h),
              ],

              // Estimated delivery card
              _buildDeliveryCard(deliveryDateStr),
              SizedBox(height: 2.h),

              // QR Code section
              _buildSectionTitle('Code de remise'),
              SizedBox(height: 1.5.h),
              _buildQrCodeCard(handoverCode),
              SizedBox(height: 2.h),

              // Step-by-step progression
              _buildSectionTitle('Progression de la livraison'),
              SizedBox(height: 1.5.h),
              _buildStepperCard(),
              SizedBox(height: 2.h),

              // Carrier info
              _buildSectionTitle('Transporteur'),
              SizedBox(height: 1.5.h),
              _buildCarrierCard(orderNumber, realAgentUser),
              SizedBox(height: 2.h),

              // Delivery address
              _buildSectionTitle('Adresse de livraison'),
              SizedBox(height: 1.5.h),
              _buildAddressCard(
                recipientName,
                address,
                city,
                country,
                phone,
                addressLat,
                addressLng,
              ),
              SizedBox(height: 2.h),

              // Rating section — shown after delivery
              if (_isDelivered) ...[
                _buildSectionTitle('Évaluer la livraison'),
                SizedBox(height: 1.5.h),
                // On envoie l'UUID réel de la commande (celui attendu par
                // POST /reviews), pas le numéro affiché "ASK-..." — c'est ce
                // dernier qui était envoyé par erreur et provoquait
                // "ID commande invalide" côté backend.
                _buildRatingCard(
                  (_realOrder?['id'] as String?) ?? (args?['orderId'] as String?) ?? '',
                ),
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
    // Libellé de l'état « en attente » selon le paiement (voir _pendingLabel).
    const confVendeur = _libelleConfVendeur;
    const attPaiement = _libellePaiement;
    final (String, String) enAttente = _pendingLabel == confVendeur
        ? (
            confVendeur,
            'Votre paiement est reçu : le vendeur doit confirmer votre commande',
          )
        : _pendingLabel == attPaiement
            ? (
                attPaiement,
                'Réglez votre commande pour que le vendeur puisse la confirmer',
              )
            : ('En attente', 'Votre commande est en attente de traitement');
    final statusLabels = {
      'en attente': enAttente,
      'en cours': ('En préparation', 'Le vendeur prépare votre colis'),
      'livreur affecté': ('Livreur affecté', 'Un livreur va récupérer votre colis'),
      'expedié': ('Colis expédié', 'Votre colis a été remis pour livraison'),
      'en transit': ('En transit', 'Votre colis est en route vers vous'),
      'livré': ('Commande livrée !', 'Votre colis a été livré avec succès'),
      'annulé': ('Commande annulée', 'Cette commande a été annulée'),
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

  // ─────────────────────────────────────────────────────
  // CAS C (bus/taxi) — le client confirme la réception ou conteste,
  // dans le délai de 3 jours après la remise au transporteur.
  // ─────────────────────────────────────────────────────
  Widget _buildBusTaxiConfirmationCard() {
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus_filled_rounded, color: AppTheme.primary, size: 18),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Text(
                  'Avez-vous reçu votre colis ?',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          SizedBox(height: 1.h),
          Text(
            'Votre colis a été remis au transporteur. Confirmez sa réception avec '
            'une photo, ou signalez un problème. Sans réponse de votre part sous '
            '3 jours, la réception sera considérée comme confirmée.',
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
          SizedBox(height: 1.5.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.report_problem_outlined, size: 16),
                  label: Text('Signaler un problème', style: GoogleFonts.outfit(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                  ),
                  onPressed: _isSubmittingBusTaxiAction ? null : () => _openDispute(context),
                ),
              ),
              SizedBox(width: 2.w),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text('Confirmer réception', style: GoogleFonts.outfit(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSubmittingBusTaxiAction ? null : () => _confirmReception(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeOpenCard() {
    return _InfoCard(
      child: Row(
        children: [
          const Icon(Icons.report_problem_rounded, color: AppTheme.error, size: 20),
          SizedBox(width: 3.w),
          Expanded(
            child: Text(
              'Votre litige a été transmis à notre équipe. Nous revenons vers vous rapidement.',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReception(BuildContext context) async {
    final orderId = _realOrder?['id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isSubmittingBusTaxiAction = true);
    try {
      final url = await UploadService.instance.uploadFile(picked, 'proofs');
      await ApiService.instance.client.post(
        '/api/v1/orders/$orderId/reception-proof',
        data: {'photoUrl': url},
      );
      if (!mounted) return;
      setState(() {
        _isSubmittingBusTaxiAction = false;
        _liveStatus = 'livré';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Réception confirmée, merci !', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmittingBusTaxiAction = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de la confirmation. Réessayez.', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openDispute(BuildContext context) async {
    final orderId = _realOrder?['id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Décrire le problème', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Ex: je n\'ai rien reçu à la gare',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (motif == null || motif.isEmpty || !context.mounted) return;

    setState(() => _isSubmittingBusTaxiAction = true);
    try {
      await ApiService.instance.client.post(
        '/api/v1/orders/$orderId/dispute',
        data: {'motif': motif},
      );
      if (!mounted) return;
      setState(() {
        _isSubmittingBusTaxiAction = false;
        _realOrder = {...?_realOrder, 'disputeOuverte': true};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmittingBusTaxiAction = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de l\'envoi. Réessayez.', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  Widget _buildRatingCard(String orderId) {
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
            onTap: _pickRatingPhoto,
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
              child: _ratingPhotoUrl.isNotEmpty
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
                  : () => _submitRating(orderId),
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
          final isLast = index == _steps.length - 1;
          // ⚠️ Avant : isCompleted = index < _currentStep pour TOUTES les
          // étapes, y compris la dernière ("Livrée"). Résultat : quand la
          // commande est livrée (_currentStep pointe justement sur cette
          // dernière étape), elle ne pouvait jamais passer "complétée" —
          // elle restait affichée comme l'étape "Actuel" (isActive), donnant
          // l'impression que la livraison est encore en cours alors qu'elle
          // est terminée. La dernière étape doit être marquée complétée dès
          // qu'on l'atteint, pas seulement quand on la dépasse.
          final isCompleted = isLast ? index <= _currentStep : index < _currentStep;
          final isActive = !isLast && index == _currentStep;
          final isPending = index > _currentStep;

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
                        index == 0 ? _sousTitreCommandeRecue() : step.subtitle,
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
                        isCompleted
                            ? 'Terminée'
                            : isActive
                            ? 'En cours'
                            : 'À venir',
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

  Widget _buildCarrierCard(
    String orderNumber,
    Map<String, dynamic>? agentUser,
  ) {
    final agentName = agentUser != null
        ? '${agentUser['prenom'] ?? ''} ${agentUser['name'] ?? ''}'.trim()
        : '';
    final isAssigned = agentName.isNotEmpty;
    final agentPhone = agentUser?['phone'] as String?;

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
                      isAssigned ? agentName : 'En attente d\'affectation',
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
                  color: isAssigned
                      ? AppTheme.successContainer
                      : AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Text(
                  isAssigned ? 'Actif' : 'En attente',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isAssigned ? AppTheme.success : AppTheme.primary,
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
                orderNumber,
              ),
              SizedBox(width: 4.w),
              _buildCarrierDetail(
                Icons.phone_rounded,
                'Contact',
                isAssigned && agentPhone != null && agentPhone.isNotEmpty
                    ? agentPhone
                    : '—',
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

  Future<void> _openAddressInMaps(
    BuildContext context,
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir Maps')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir Maps')),
        );
      }
    }
  }

  Widget _buildAddressCard(
    String recipientName,
    String address,
    String city,
    String country,
    String phone,
    double? latitude,
    double? longitude,
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
                  recipientName,
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
                // Position GPS partagée par le client au paiement — absente
                // pour les commandes passées avant l'ajout de cette
                // fonctionnalité, ou en cas de retrait en boutique.
                if (latitude != null && longitude != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () =>
                        _openAddressInMaps(context, latitude, longitude),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.map_rounded,
                          size: 15,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Voir sur la carte',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Carte « Code de remise » (côté CLIENT). Le code est un secret aléatoire
  /// généré par le serveur (`handoverCode`), à ne donner qu'au livreur au
  /// moment de la réception. Ce n'est PLUS le numéro de commande (qui n'est
  /// pas secret). S'il n'est pas fourni (null), aucun QR n'est affiché et on
  /// ne se rabat jamais sur le numéro de commande.
  Widget _buildQrCodeCard(String? handoverCode) {
    final String code = handoverCode ?? '';
    final bool hasCode = code.isNotEmpty;
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
                      'Code de remise',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Code de remise — à donner uniquement au livreur à la réception',
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
          if (!hasCode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Text(
                'Le code de remise n\'est pas disponible pour le moment. '
                'Il s\'affichera ici dès que la commande sera prête.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else ...[
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
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: PrettyQrView.data(
                    data: code,
                    decoration: const PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(color: Color(0xFF1A1A2E)),
                    ),
                    errorCorrectLevel: QrErrorCorrectLevel.M,
                  ),
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
                  Flexible(
                    child: SelectableText(
                      code,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
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
  const _TrackingStep({
    required this.icon,
    required this.title,
    required this.subtitle,
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