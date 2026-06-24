import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../widgets/app_toast.dart';

class DeliveryRequestScreen extends StatefulWidget {
  const DeliveryRequestScreen({super.key});

  @override
  State<DeliveryRequestScreen> createState() => _DeliveryRequestScreenState();
}

class _DeliveryRequestScreenState extends State<DeliveryRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();

  String _urgency = 'normal';
  bool _isSubmitting = false;

  static const Map<String, Map<String, dynamic>> _urgencyOptions = {
    'normal': {
      'label': 'Normal',
      'subtitle': 'Livraison dans la journée',
      'icon': Icons.schedule_rounded,
      'color': Color(0xFF16A34A),
    },
    'urgent': {
      'label': 'Urgent',
      'subtitle': 'Livraison en 2–3 heures',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFFD97706),
    },
    'express': {
      'label': 'Express',
      'subtitle': 'Livraison en moins d\'1 heure',
      'icon': Icons.rocket_launch_rounded,
      'color': Color(0xFFDC2626),
    },
  };

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final isLoggedIn = await NestAuthService.instance
        .isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!isLoggedIn) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Vous devez être connecté pour faire une demande.',
          type: ToastType.error,
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final price =
          double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0;
      final notes = _notesController.text.trim();

      await ApiService.instance.client.post(
        '/api/v1/delivery-requests',
        data: {
          'pickupAddress': _pickupController.text.trim(),
          'dropoffAddress': _dropoffController.text.trim(),
          'packageDescription': _descriptionController.text.trim(),
          'urgency': _urgency,
          'proposedPrice': price,
          if (notes.isNotEmpty) 'notes': notes,
        },
      );

      if (mounted) {
        AppToast.show(
          context,
          message: 'Demande envoyée ! Un livreur va vous contacter.',
          type: ToastType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi. Veuillez réessayer.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInfoBanner(),
            const SizedBox(height: 20),
            _buildSectionTitle('Adresses', Icons.location_on_rounded),
            const SizedBox(height: 12),
            _buildAddressField(
              controller: _pickupController,
              label: 'Adresse de ramassage',
              hint: 'Ex: Quartier Cadjehoun, Cotonou',
              icon: Icons.radio_button_checked_rounded,
              iconColor: AppTheme.primary,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Adresse requise' : null,
            ),
            const SizedBox(height: 4),
            _buildRouteLine(),
            const SizedBox(height: 4),
            _buildAddressField(
              controller: _dropoffController,
              label: 'Adresse de livraison',
              hint: 'Ex: Akpakpa, Cotonou',
              icon: Icons.location_on_rounded,
              iconColor: AppTheme.error,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Adresse requise' : null,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Colis', Icons.inventory_2_rounded),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _descriptionController,
              label: 'Description du colis',
              hint: 'Ex: Documents administratifs, vêtements, médicaments...',
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Description requise'
                  : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _notesController,
              label: 'Instructions supplémentaires (optionnel)',
              hint: 'Ex: Appeler avant d\'arriver, colis fragile...',
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Urgence', Icons.timer_rounded),
            const SizedBox(height: 12),
            _buildUrgencySelector(),
            const SizedBox(height: 24),
            _buildSectionTitle('Prix proposé', Icons.payments_rounded),
            const SizedBox(height: 12),
            _buildPriceField(),
            const SizedBox(height: 8),
            Text(
              'Proposez un montant juste. Le livreur peut négocier avant d\'accepter.',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 32),
            _buildSubmitButton(),
            const SizedBox(height: 24),
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
        'Demander un livreur',
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

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Course express',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  'Envoyez n\'importe quel colis sans passer par la boutique.',
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

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    String? Function(String?)? validator,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, right: 10),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            validator: validator,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 9),
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            width: 2,
            height: 6,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.outline,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  Widget _buildUrgencySelector() {
    return Column(
      children: _urgencyOptions.entries.map((entry) {
        final key = entry.key;
        final opt = entry.value;
        final isSelected = _urgency == key;
        final color = opt['color'] as Color;

        return GestureDetector(
          onTap: () => setState(() => _urgency = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withAlpha(20) : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : AppTheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(opt['icon'] as IconData, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opt['label'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? color : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        opt['subtitle'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: color, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Prix requis';
        final price = double.tryParse(v.replaceAll(',', '.'));
        if (price == null || price <= 0) return 'Prix invalide';
        return null;
      },
      style: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: 'Montant proposé',
        hintText: '2500',
        suffixText: 'FCFA',
        suffixStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.muted,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withAlpha(120),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Envoyer la demande',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}