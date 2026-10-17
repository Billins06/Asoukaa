import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../services/delivery_zone_service.dart';

/// Choix de livraison exposé par [DeliverySelectorWidget] à chaque
/// changement : mode (livraison/retrait), commune, frais correspondants,
/// et mode de transport pour les communes du Nord (bus/taxi — prix
/// différents, voir OrdersService.getFraisLivraisonForCommune côté
/// backend).
class DeliverySelection {
  final String mode; // 'livraison' ou 'retrait'
  final String city;
  final double fee; // 0 si mode == 'retrait'
  final bool isNordZone;
  final String? transportMode; // 'bus' / 'taxi', uniquement zone Nord

  const DeliverySelection({
    required this.mode,
    required this.city,
    required this.fee,
    required this.isNordZone,
    required this.transportMode,
  });

  /// false si une commune du Nord est sélectionnée sans mode de transport,
  /// ou si aucune commune n'est renseignée en mode livraison — le parent
  /// (panier) doit alors bloquer le passage à l'étape suivante.
  bool get isComplete =>
      mode == 'retrait' ||
      (city.trim().isNotEmpty && (!isNordZone || transportMode != null));
}

/// Sélecteur "Être livré / Retrait en boutique" + commune (avec bus/taxi
/// pour les communes du Nord où Asoukaa n'a pas de livreur propre).
///
/// Vit désormais dans le panier (panier_screen) — pour que le client ait
/// une idée du total avant même d'arriver à l'écran de paiement. Le
/// paiement (checkout_screen) n'en affiche plus qu'un récapitulatif en
/// lecture seule, avec un lien pour revenir ici si besoin.
class DeliverySelectorWidget extends StatefulWidget {
  final String initialMode;
  final String initialCity;
  final String? initialTransportMode;
  final ValueChanged<DeliverySelection> onChanged;

  const DeliverySelectorWidget({
    super.key,
    this.initialMode = 'livraison',
    this.initialCity = '',
    this.initialTransportMode,
    required this.onChanged,
  });

  @override
  State<DeliverySelectorWidget> createState() =>
      _DeliverySelectorWidgetState();
}

class _DeliverySelectorWidgetState extends State<DeliverySelectorWidget> {
  late String _mode = widget.initialMode;
  late final TextEditingController _cityController =
      TextEditingController(text: widget.initialCity);
  String? _transportMode;
  List<String> _communes = [];
  double _fee = 0;
  bool _isNordZone = false;
  bool _loadingFee = true;

  @override
  void initState() {
    super.initState();
    _transportMode = widget.initialTransportMode;
    _init();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final names = await DeliveryZoneService.instance.communeNames();
    if (mounted) setState(() => _communes = names);
    await _recompute(notify: false);
    if (mounted) setState(() => _loadingFee = false);
    _notify();
  }

  Future<void> _recompute({bool notify = true}) async {
    if (_mode == 'retrait') {
      if (mounted) {
        setState(() {
          _fee = 0;
          _isNordZone = false;
        });
      }
    } else {
      setState(() => _loadingFee = true);
      final fee =
          await DeliveryZoneService.instance.feeForCommune(_cityController.text);
      final isNord =
          await DeliveryZoneService.instance.isNordCommune(_cityController.text);
      if (!mounted) return;
      setState(() {
        _fee = fee.toDouble();
        _isNordZone = isNord;
        _loadingFee = false;
        // Une commune non-Nord n'a pas besoin de mode de transport ; on
        // réinitialise pour ne pas garder une ancienne sélection obsolète
        // si le client change finalement de commune.
        if (!isNord) _transportMode = null;
      });
    }
    if (notify) _notify();
  }

  void _notify() {
    widget.onChanged(DeliverySelection(
      mode: _mode,
      city: _cityController.text.trim(),
      fee: _fee,
      isNordZone: _isNordZone,
      transportMode: _transportMode,
    ));
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _recompute();
  }

  void _setTransportMode(String mode) {
    setState(() => _transportMode = mode);
    _notify();
  }

  String _formatPrice(double price) {
    final p = price.toInt().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < p.length; i++) {
      if (i > 0 && (p.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(p[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModeToggle(),
        if (_mode != 'retrait') ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Choisissez votre commune pour voir les frais de livraison',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          _buildCityAutocomplete(),
          if (_isNordZone) ...[
            const SizedBox(height: 12),
            _buildTransportModeSelector(),
          ],
          if (_isNordZone && _transportMode != null) ...[
            const SizedBox(height: 10),
            _buildBusTaxiWarning(),
          ],
          const SizedBox(height: 10),
          _buildFeeLine(),
        ],
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeOption(
              mode: 'livraison',
              icon: Icons.local_shipping_outlined,
              label: 'Etre livré',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildModeOption(
              mode: 'retrait',
              icon: Icons.storefront_outlined,
              label: 'Retrait en boutique',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required String mode,
    required IconData icon,
    required String label,
  }) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCityAutocomplete() {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue value) {
        if (value.text.isEmpty) return _communes;
        final q = value.text.toLowerCase();
        return _communes.where((cm) => cm.toLowerCase().contains(q));
      },
      initialValue: TextEditingValue(text: _cityController.text),
      onSelected: (String selection) {
        _cityController.text = selection;
        _recompute();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (v) {
            _cityController.text = v;
            _recompute();
          },
          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Ville / Commune',
            prefixIcon: const Icon(
              Icons.location_city_outlined,
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
          ),
        );
      },
    );
  }

  // Avertissement affiché dès qu'un mode de transport (bus/taxi) est
  // choisi pour une commune du Nord : Asoukaa n'a pas de livreur propre
  // là-bas, donc pas de suivi GPS ni de preuve de remise signée par le
  // client. Le client doit savoir, AVANT de payer, que les fonds seront
  // versés au vendeur automatiquement après 3 jours s'il ne confirme ni
  // ne signale de problème (règle mise en oeuvre côté backend par
  // OrdersService.checkAutoConfirmBusTaxiOrders).
  Widget _buildBusTaxiWarning() {
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
              'Cette commune est desservie par bus/taxi, sans livreur Asoukaa. '
              'À la réception, vous aurez 3 jours pour confirmer votre colis ou '
              'signaler un problème. Passé ce délai sans réponse de votre part, '
              'la réception sera automatiquement confirmée et le vendeur sera payé.',
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

  // Commune du Nord uniquement : Asoukaa n'y a pas de livreur propre, le
  // colis part par bus ou taxi inter-urbain. Les deux prix sont
  // différents (bus = tarif de base de la zone, taxi = tarif réduit — voir
  // OrdersService.getFraisLivraisonForCommune côté backend, qui reste dans
  // tous les cas la source de vérité au moment de la commande).
  Widget _buildTransportModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cette commune est desservie par bus ou taxi. Choisissez votre préférence :',
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTransportModeOption(
                  mode: 'bus',
                  icon: Icons.directions_bus_filled_outlined,
                  label: 'Bus',
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildTransportModeOption(
                  mode: 'taxi',
                  icon: Icons.local_taxi_outlined,
                  label: 'Taxi',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransportModeOption({
    required String mode,
    required IconData icon,
    required String label,
  }) {
    final selected = _transportMode == mode;
    return GestureDetector(
      onTap: () => _setTransportMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeLine() {
    if (_loadingFee) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Calcul des frais de livraison...',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(
          Icons.local_shipping_outlined,
          size: 16,
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          _fee == 0
              ? 'Frais de livraison : Gratuit'
              : 'Frais de livraison : ${_formatPrice(_fee)} FCFA',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
