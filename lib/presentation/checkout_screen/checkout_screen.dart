import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/nest_auth_service.dart';
import '../../services/user_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/token_storage_service.dart';
import '../../utils/lecture_json.dart';
import '../../utils/paiement_annulation.dart';
import '../../utils/telephone.dart';

/// Dernière tentative de commande en cours de paiement (commandes déjà créées
/// côté serveur, pas encore payées). Si le client reclique sur « Commander »
/// pour le MÊME panier, on réutilise ces commandes au lieu d'en recréer.
class _TentativeCommande {
  final String signature;
  final List<Map<String, dynamic>> commandes;
  const _TentativeCommande(this.signature, this.commandes);
}

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

  // Tentative de commande réutilisable (voir _TentativeCommande). Statique :
  // elle survit à un retour au panier puis à un nouveau passage ici.
  static _TentativeCommande? _tentativeEnCours;

  // Vrai dès que l'issue du paiement en cours est connue (confirmé, ou en
  // vérification) : évite d'afficher deux fois la confirmation / le message
  // quand le polling et le bouton « Annuler l'attente » se croisent.
  bool _paiementResolu = false;

  // Code promo validé dans le panier : envoyé à la création de la commande
  // (champ `couponCode` du serveur) pour que le total facturé soit celui
  // affiché.
  String? _couponCode;

  String _selectedCountry = 'Bénin';
  String _selectedOperator = 'MTN';
  // 'livraison' (defaut) ou 'retrait' (le client vient chercher en boutique)
  String _deliveryMode = 'livraison';
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

  // Mode de réception, commune et transport (bus/taxi, communes du Nord où
  // Asoukaa n'a pas de livreur propre — les deux prix sont différents,
  // voir OrdersService.getFraisLivraisonForCommune côté backend) : choisis
  // désormais dans le panier (voir DeliverySelectorWidget) et simplement
  // reçus ici via les arguments de navigation. Cet écran n'en affiche plus
  // qu'un récapitulatif en lecture seule (_buildDeliveryRecap).
  bool _isNordZone = false;
  String? _transportMode;

  // Frais de livraison reellement appliques : nul en mode retrait
  double get _currentDeliveryFee => _deliveryMode == 'retrait' ? 0 : _deliveryFee;

  // Created order ID (pending state before payment)
  // Panier réparti sur plusieurs boutiques -> une commande par boutique
  // (voir OrdersService.createFromCart), toutes réglées par UN SEUL
  // paiement (voir PaymentsService.initiateGroupPayment).
  List<Map<String, dynamic>> _pendingOrders = [];

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
      _subtotal = lireDouble(args['subtotal']);
      _promoDiscount = lireDouble(args['promoDiscount']);
      _deliveryFee = lireDouble(args['deliveryFee'], 2500);
      _total = lireDouble(args['total']);
      final coupon = args['couponCode'];
      _couponCode =
          (coupon is String && coupon.trim().isNotEmpty) ? coupon.trim() : null;
      if (_total == 0) _total = _subtotal + _currentDeliveryFee - _promoDiscount;
      // Mode/commune/transport choisis dans le panier (voir
      // DeliverySelectorWidget) — repris tels quels ici.
      _deliveryMode = (args['deliveryMode'] as String?) ?? _deliveryMode;
      _cityController.text = (args['city'] as String?) ?? _cityController.text;
      _transportMode = args['transportMode'] as String?;
      _isNordZone = (args['isNordZone'] as bool?) ?? false;
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

  // ⚠️ Avant ce correctif : coordonnées de Cotonou codées en dur, peu importe
  // où se trouvait réellement le client. On utilise maintenant la vraie
  // position GPS de l'appareil (même mécanisme que le suivi livreur dans
  // delivery_proof_screen.dart).
  Future<void> _shareLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Le service de localisation est désactivé sur cet appareil.',
        type: ToastType.error,
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Permission de localisation refusée.',
        type: ToastType.error,
      );
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      position = null;
    }

    if (!mounted) return;

    if (position == null) {
      AppToast.show(
        context,
        message: 'Impossible d\'obtenir votre position. Réessayez.',
        type: ToastType.error,
      );
      return;
    }

    setState(() {
      _locationShared = true;
      _latitude = position!.latitude;
      _longitude = position.longitude;
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
          'phone_destinataire': normaliserTelephone(_phoneController.text),
          'quartier': _addressController.text.trim(),
          'ville': _cityController.text.trim(),
          'country': _selectedCountry,
          'isDefault': _saveAddress,
          if (_latitude != null) 'latitude': _latitude,
          if (_longitude != null) 'longitude': _longitude,
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

    if (_deliveryMode != 'retrait' && _isNordZone && _transportMode == null) {
      AppToast.show(
        context,
        message: 'Choisissez bus ou taxi pour cette commune',
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

      // Même panier, mêmes coordonnées qu'une tentative précédente non
      // payée : on réutilise ses commandes (pas de doublons).
      final signature = await _signatureTentative();
      final tentative = _tentativeEnCours;
      final reutiliser = tentative != null &&
          tentative.signature == signature &&
          tentative.commandes.isNotEmpty;

      if (reutiliser) {
        _pendingOrders = List<Map<String, dynamic>>.from(tentative!.commandes);
      } else {
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

        // Étape 2 : créer la/les commande(s) depuis le panier
        // Le backend lit le panier automatiquement — on envoie uniquement
        // addressId. S'il contient des articles de plusieurs boutiques, le
        // backend crée automatiquement une commande par boutique.
        final instructions = _notesController.text.trim();
        _pendingOrders = await _createOrders(
          addressId: addressId,
          instructions: instructions.isNotEmpty ? instructions : null,
          deliveryMode: _deliveryMode,
          transportMode: _isNordZone ? _transportMode : null,
        );
        if (_pendingOrders.isNotEmpty) {
          _tentativeEnCours = _TentativeCommande(
            signature,
            List<Map<String, dynamic>>.from(_pendingOrders),
          );
        }

        // Mettre à jour le téléphone si demandé
        if (_saveAddress) {
          try {
            await UserService.instance.updateProfile(
              phone: normaliserTelephone(_phoneController.text),
            );
          } catch (_) {}
        }
      }

      setState(() => _isPlacingOrder = false);

      if (!mounted) return;

      if (_pendingOrders.isEmpty) {
        AppToast.show(
          context,
          message: 'Impossible de créer la commande. Réessayez.',
          type: ToastType.error,
        );
        setState(() => _isPlacingOrder = false);
        return;
      }

      // Le paiement passe par notre backend (route POST /payments/initiate),
      // qui appelle FeexPay lui-même — la clé API n'est plus embarquée dans
      // l'appli (SDK feexpay_flutter retiré de cet écran). Une fois la demande
      // envoyée, on affiche une boîte d'attente et on interroge
      // GET /payments/{id}/status jusqu'à confirmation, échec ou délai
      // dépassé, puis on redirige vers l'écran de confirmation.
      try {
        final orderIds = _pendingOrders
            .map((o) => o['id'] as String?)
            .whereType<String>()
            .toList();

        // Un paiement de cette commande vient d'être mis « en cours de
        // vérification » : on ne relance pas un second paiement tout de suite.
        if (PaiementsEnVerification.estEnVerification(orderIds)) {
          await _afficherVerificationEnCours(messagePaiementEnVerification);
          return;
        }

        // Le total facturé est celui calculé par le SERVEUR (somme des
        // commandes créées). S'il diffère de celui affiché dans l'appli
        // (ex. code promo refusé ou prix changé), on le dit au client et on
        // lui demande de confirmer avant de lancer le paiement.
        final totalServeur = _pendingOrders.fold<double>(
          0,
          (s, o) => s + lireDouble(o['total']),
        );
        if (totalServeur > 0 && (totalServeur - _total).abs() >= 1) {
          if (mounted) setState(() => _total = totalServeur);
          final accepte = await _confirmerTotalServeur(totalServeur);
          if (!accepte) return;
        }
        final payResp = await ApiService.instance.client.post(
          '/api/v1/payments/initiate',
          data: {
            // Une seule boutique -> orderId comme avant. Plusieurs
            // boutiques -> orderIds : le backend crée une ligne de
            // paiement par commande mais ne demande qu'UN SEUL montant
            // au client (voir initiateGroupPayment côté serveur).
            if (orderIds.length <= 1)
              'orderId': orderIds.isNotEmpty ? orderIds.first : null
            else
              'orderIds': orderIds,
            'method': 'mobile_money',
            'operator': _selectedOperator,
            'phoneNumber': normaliserTelephone(_phoneController.text),
          },
        );
        final payData = payResp.data;
        final paymentId = payData is Map ? payData['paymentId'] as String? : null;
        final payMessage = payData is Map ? payData['message'] as String? : null;
        if (!mounted) return;
        AppToast.show(
          context,
          message: payMessage ?? 'Demande de paiement envoyée.',
          type: ToastType.success,
        );

        if (paymentId != null) {
          final orderNumbers = _pendingOrders
              .map((o) => o['orderNumber']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          final confirmationArgs = <String, dynamic>{
            'orderNumber': orderNumbers.join(', '),
            // Utilisée par l'écran de confirmation pour permettre ensuite un
            // vrai suivi (voir order_confirmation_screen.dart). En cas de
            // commande groupée multi-boutiques, on ne peut suivre qu'une
            // commande à la fois : on prend la première.
            'orderId': orderIds.isNotEmpty ? orderIds.first : null,
            'firstName': _firstNameController.text.trim(),
            'lastName': _lastNameController.text.trim(),
            'address': _addressController.text.trim(),
            'city': _cityController.text.trim(),
            'country': _selectedCountry,
            'phone': _phoneController.text.trim(),
            'paymentMethod': '$_selectedOperator (Mobile Money)',
            // Montant réellement facturé (calculé par le serveur).
            'total': (totalServeur > 0 ? totalServeur : _total).round(),
          };
          _pollPaymentStatus(
            paymentId,
            confirmationArgs,
            orderIds: orderIds,
          );
        }
      } on DioException catch (e) {
        final errData = e.response?.data;
        final backendMessage = errData is Map ? errData['message'] : null;
        final texte = backendMessage is String
            ? backendMessage
            : (backendMessage is List && backendMessage.isNotEmpty
                ? backendMessage.first.toString()
                : '');
        // Commande réutilisée mais devenue inutilisable (annulée, introuvable)
        // ou déjà payée : on oublie la tentative pour repartir proprement.
        if (e.response?.statusCode == 404 ||
            texte.contains('ne peut plus être payée') ||
            texte.contains('déjà payée')) {
          _tentativeEnCours = null;
        }
        if (texte.contains('déjà payée')) {
          // Le paiement est en fait passé : le panier doit être vidé.
          await _viderPanierServeur();
        }
        if (!mounted) return;
        setState(() => _isPlacingOrder = false);
        if (estMessageVerificationEnCours(texte)) {
          // Le serveur refuse un second paiement : le premier est encore en
          // cours de vérification. Message du serveur affiché tel quel (dans
          // une boîte, pour qu'il ne soit pas tronqué), puis « Mes commandes ».
          await _afficherVerificationEnCours(texte);
          return;
        }
        AppToast.show(
          context,
          message: texte.isNotEmpty ? texte : 'Le paiement a échoué. Réessayez.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      // Erreur serveur lisible (ex. code promo refusé, article épuisé).
      String message = 'Une erreur est survenue. Réessayez.';
      if (e is DioException) {
        final d = e.response?.data;
        final m = d is Map ? d['message'] : null;
        if (m is String && m.isNotEmpty) {
          message = m;
        } else if (m is List && m.isNotEmpty) {
          message = m.first.toString();
        }
      }
      if (mounted) {
        AppToast.show(context, message: message, type: ToastType.error);
        setState(() => _isPlacingOrder = false);
      }
    }
  }

  /// Empreinte du panier + des coordonnées saisies : deux tentatives avec la
  /// même empreinte concernent la même commande.
  Future<String> _signatureTentative() async {
    String userId = '';
    try {
      userId = (await TokenStorageService.instance.getUserId()) ?? '';
    } catch (_) {}
    final articles = _orderItems
        .map((i) => '${i['variantId'] ?? i['id'] ?? ''}x${i['quantity'] ?? 1}')
        .toList()
      ..sort();
    return [
      userId,
      articles.join(','),
      _couponCode ?? '',
      _deliveryMode,
      _isNordZone ? (_transportMode ?? '') : '',
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
      normaliserTelephone(_phoneController.text),
      _addressController.text.trim(),
      _cityController.text.trim(),
      _selectedCountry,
      _notesController.text.trim(),
      '${_latitude ?? ''}',
      '${_longitude ?? ''}',
    ].join('|');
  }

  /// Vide le panier côté serveur (paiement confirmé). Sans effet si ça échoue :
  /// le serveur reste la référence.
  Future<void> _viderPanierServeur() async {
    try {
      await ApiService.instance.client
          .delete('/api/v1/cart')
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<bool> _confirmerTotalServeur(double totalServeur) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Total mis à jour'),
        content: Text(
          'Le total de votre commande est de ${_formatPrice(totalServeur)}. '
          'Voulez-vous continuer vers le paiement ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (ok != true && mounted) setState(() => _isPlacingOrder = false);
    return ok == true;
  }

  /// Paiement confirmé (par le polling OU par la réponse du cancel) : on vide
  /// le panier, on oublie la tentative et on affiche la confirmation de
  /// commande. Ne s'exécute qu'une seule fois par paiement (_paiementResolu).
  Future<void> _finaliserPaiementReussi(
    Map<String, dynamic> confirmationArgs,
    List<String> orderIds,
    String? orderNumberServeur,
  ) async {
    if (_paiementResolu) return;
    _paiementResolu = true;
    PaiementsEnVerification.oublier(orderIds);
    // Paiement confirmé : seulement maintenant on vide le panier et on
    // oublie la tentative (plus de double paiement possible).
    _tentativeEnCours = null;
    await _viderPanierServeur();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.orderConfirmation,
      arguments: {
        ...confirmationArgs,
        'orderNumber': orderNumberServeur ?? confirmationArgs['orderNumber'],
      },
    );
  }

  /// Paiement non confirmé mais NON annulé (FeexPay n'a pas encore répondu) :
  /// on prévient clairement le client, SANS parler d'échec et SANS proposer
  /// de repayer, puis on le ramène vers « Mes commandes ». Le panier n'est
  /// pas vidé et la tentative de commande est conservée : un nouveau clic sur
  /// « Commander » réutilisera la même commande (le serveur refusera alors un
  /// second paiement tant que la vérification est en cours).
  Future<void> _afficherVerificationEnCours(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Vérification en cours',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            content: Text(
              message,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'Voir mes commandes',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.buyerDashboard,
      (route) => false,
    );
  }

  /// Abandon de l'attente : appelle PATCH /payments/{id}/cancel puis applique
  /// la réponse du serveur :
  ///  - 'success'  -> le paiement était en fait confirmé : même chemin que le
  ///    succès du polling ;
  ///  - 'en attente' + verificationEnCours -> non confirmé mais non annulé :
  ///    message de vérification, pas de nouveau paiement immédiat ;
  ///  - 'échoué', réponse sans `status` (ancien serveur) ou appel impossible
  ///    (réseau coupé) -> comportement d'avant : rien (bouton) ou message
  ///    « Confirmation non reçue » (délai dépassé).
  Future<void> _annulerPaiement(
    String paymentId,
    Map<String, dynamic> confirmationArgs,
    List<String> orderIds, {
    required bool apresDelai,
  }) async {
    ReponseAnnulationPaiement? reponseBrute;
    try {
      final resp = await ApiService.instance.client
          .patch('/api/v1/payments/$paymentId/cancel');
      reponseBrute = lireReponseAnnulation(resp.data);
    } catch (_) {
      // best-effort : si ça échoue (réseau coupé...), on ne sait pas ce qu'a
      // fait le serveur ; on garde le comportement d'avant.
      reponseBrute = null;
    }
    final reponse = reponseBrute;

    if (reponse != null && reponse.issue == IssueAnnulation.reussi) {
      await _finaliserPaiementReussi(confirmationArgs, orderIds, null);
      return;
    }

    if (reponse != null &&
        reponse.issue == IssueAnnulation.verificationEnCours) {
      if (_paiementResolu) return;
      _paiementResolu = true;
      PaiementsEnVerification.marquer(orderIds);
      await _afficherVerificationEnCours(reponse.messageVerification);
      return;
    }

    // Échec confirmé / ancien serveur / appel impossible.
    if (reponse != null) PaiementsEnVerification.oublier(orderIds);
    if (apresDelai && mounted) {
      if (reponse != null && reponse.echecConfirme) {
        // Le serveur a confirmé l'échec : on montre son message.
        AppToast.show(
          context,
          message: reponse.messageEchec,
          type: ToastType.error,
        );
      } else {
        AppToast.show(
          context,
          message:
              'Confirmation non reçue. Vérifiez le statut dans "Mes commandes".',
          type: ToastType.info,
        );
      }
    }
  }

  /// Interroge GET /payments/{id}/status jusqu'à confirmation, échec ou
  /// délai dépassé, pendant qu'une boîte d'attente non-fermable informe le
  /// client de valider le paiement mobile money sur son téléphone.
  Future<void> _pollPaymentStatus(
    String paymentId,
    Map<String, dynamic> confirmationArgs, {
    List<String> orderIds = const <String>[],
  }) async {
    const maxAttempts = 40; // ~2 minutes à 3s d'intervalle
    const pollInterval = Duration(seconds: 3);
    var dialogOpen = true;
    _paiementResolu = false;
    // Passe à true après ~90 s : le texte de la boîte d'attente change.
    final attenteLongue = ValueNotifier<bool>(false);

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Confirmez le paiement sur votre téléphone',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: attenteLongue,
                  builder: (builderContext, longue, _) {
                    return Text(
                      longue
                          ? 'Toujours en attente de votre validation sur le '
                              'téléphone… Ne fermez pas l\'application et ne '
                              'payez pas une seconde fois.'
                          : 'Validez la demande de paiement mobile money reçue '
                              'sur votre téléphone. Ne fermez pas '
                              'l\'application.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _annulerPaiement(
                    paymentId,
                    confirmationArgs,
                    orderIds,
                    apresDelai: false,
                  );
                },
                child: Text(
                  'Annuler l\'attente',
                  style: GoogleFonts.outfit(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => dialogOpen = false);

    void closeDialog() {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      dialogOpen = false;
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(pollInterval);
      if (!dialogOpen || !mounted) return;

      // ~90 s écoulées (30 interrogations x 3 s) : message plus rassurant.
      if (attempt == 29) attenteLongue.value = true;

      try {
        final statusResp = await ApiService.instance.client.get(
          '/api/v1/payments/$paymentId/status',
        );
        final statusData = statusResp.data;
        final status =
            statusData is Map ? statusData['status']?.toString() : null;

        if (status == 'success') {
          final numeroBrut =
              statusData is Map ? statusData['orderNumber'] : null;
          closeDialog();
          await _finaliserPaiementReussi(
            confirmationArgs,
            orderIds,
            numeroBrut is String ? numeroBrut : null,
          );
          return;
        }

        if (status == 'échoué') {
          closeDialog();
          PaiementsEnVerification.oublier(orderIds);
          if (!mounted) return;
          AppToast.show(
            context,
            message:
                'Le paiement a échoué ou a été annulé. Vous pouvez réessayer.',
            type: ToastType.error,
          );
          return;
        }
        // Sinon toujours "en attente" — on continue le polling.
      } catch (_) {
        // Erreur réseau ponctuelle pendant le polling — on retente au
        // prochain cycle plutôt que d'abandonner tout de suite.
      }
    }

    // Délai dépassé sans confirmation ni échec explicite : on demande au
    // serveur d'annuler, mais il peut répondre « déjà confirmé » ou
    // « en cours de vérification » (voir _annulerPaiement).
    if (dialogOpen) {
      closeDialog();
      await _annulerPaiement(
        paymentId,
        confirmationArgs,
        orderIds,
        apresDelai: true,
      );
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
                      Icons.local_shipping_outlined,
                      'Mode de réception',
                    ),
                    const SizedBox(height: 12),
                    _buildDeliveryRecap(),
                    if (_deliveryMode != 'retrait' &&
                        _isNordZone &&
                        _transportMode != null) ...[
                      const SizedBox(height: 10),
                      _buildBusTaxiCheckoutWarning(),
                    ],
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      Icons.location_on_rounded,
                      _deliveryMode == 'retrait'
                          ? 'Coordonnées de contact'
                          : 'Adresse de livraison',
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
          Expanded(child: _stepDot(1, 'Panier', true)),
          _stepLine(true),
          Expanded(child: _stepDot(2, 'Livraison', true)),
          _stepLine(false),
          Expanded(child: _stepDot(3, 'Paiement', false)),
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

  Widget _buildDeliveryRecap() {
    final subtitle = _deliveryMode == 'retrait'
        ? 'Retrait en boutique'
        : (_cityController.text.trim().isEmpty
            ? 'Livraison'
            : 'Livraison à ${_cityController.text.trim()}');
    final feeLabel = _currentDeliveryFee == 0
        ? 'Gratuit'
        : '${_currentDeliveryFee.toInt()} FCFA';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          Icon(
            _deliveryMode == 'retrait'
                ? Icons.storefront_outlined
                : Icons.local_shipping_outlined,
            size: 20,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (_deliveryMode != 'retrait' &&
                    _isNordZone &&
                    _transportMode != null)
                  Text(
                    _transportMode == 'taxi' ? 'Par taxi' : 'Par bus',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                Text(
                  feeLabel,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Modifier',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Rappel de la règle des 3 jours (zone Nord, sans livreur Asoukaa),
  // affiché juste avant le paiement pour que le client la voie une
  // dernière fois avant de valider sa commande (le premier avertissement,
  // au moment du choix bus/taxi, est dans DeliverySelectorWidget côté
  // panier).
  Widget _buildBusTaxiCheckoutWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Livraison par bus/taxi : vous aurez 24 heures après l\'expédition '
              'pour confirmer la réception de votre colis ou signaler un '
              'problème. Sans réponse de votre part, la réception sera '
              'automatiquement confirmée et le vendeur sera payé.',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                color: AppTheme.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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
          _buildCountryDropdown(),
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
          _buildOperatorDropdown(),
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
      isExpanded: true,
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

  Widget _buildOperatorDropdown() {
    const operators = ['MTN', 'Moov'];
    return DropdownButtonFormField<String>(
      initialValue: _selectedOperator,
      isExpanded: true,
      onChanged: (v) => setState(() => _selectedOperator = v ?? 'MTN'),
      style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: 'Opérateur Mobile Money',
        prefixIcon: const Icon(
          Icons.sim_card_outlined,
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
      items: operators
          .map(
            (o) => DropdownMenuItem(
              value: o,
              child: Text(
                o,
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
                _buildPriceLine(
                  _deliveryMode == 'retrait' ? 'Retrait en boutique' : 'Livraison',
                  _currentDeliveryFee,
                  color: _deliveryMode == 'retrait' ? AppTheme.success : null,
                ),
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
                    _deliveryMode == 'retrait'
                        ? 'Retrait en boutique : disponible sous 24–48h, tu seras prévenu(e)'
                        : 'Livraison estimée : 2–4 jours ouvrables',
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

  /// Le panier peut être réparti sur plusieurs boutiques : le backend
  /// crée alors une commande par boutique (voir OrdersService.createFromCart)
  /// et renvoie la liste complète — on ne garde plus seulement la première.
  Future<List<Map<String, dynamic>>> _createOrders({
    required String addressId,
    String? instructions,
    String? deliveryMode,
    String? transportMode,
  }) async {
    final data = <String, dynamic>{'addressId': addressId};
    // Code promo validé dans le panier (nom du champ : `couponCode`, voir
    // CreateOrderDto côté serveur).
    if (_couponCode != null && _couponCode!.isNotEmpty) {
      data['couponCode'] = _couponCode;
    }
    if (instructions != null && instructions.isNotEmpty) {
      data['instructions'] = instructions;
    }
    if (deliveryMode != null && deliveryMode.isNotEmpty) {
      data['deliveryMode'] = deliveryMode;
    }
    if (transportMode != null && transportMode.isNotEmpty) {
      data['transportMode'] = transportMode;
    }
    final response = await ApiService.instance.client.post(
      '/api/v1/orders',
      data: data,
    );
    final resData = response.data;
    if (resData is Map) {
      final orders = resData['orders'];
      if (orders is List) {
        return orders.whereType<Map>().map(
          (o) => Map<String, dynamic>.from(o),
        ).toList();
      }
    }
    return [];
  }
}