import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../routes/app_routes.dart';
import '../../../services/nest_auth_service.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/category_multi_select.dart';
import '../../../utils/telephone.dart';

class AuthFormWidget extends StatefulWidget {
  final bool isLogin;
  final String accountType;
  final bool isLoading;
  final VoidCallback onSubmit;
  final void Function({
    String? email,
    String? password,
    String? fullName,
    String? phone,
    // Vendeur
    String? shopName,
    String? shopAddress,
    List<String>? categoryIds,
    String? shopDescription,
    // Livreur
    String? ville,
    String? quartier,
    String? preciseAddress,
    String? vehicleType,
    String? availability,
    String? licensePlate,
  })? onFormDataChanged;

  final void Function({
    XFile? idDocument,
    XFile? selfie,
    List<XFile>? sampleProducts,
    XFile? vehiclePhoto,
  })? onFilesChanged;

  const AuthFormWidget({
    super.key,
    required this.isLogin,
    required this.accountType,
    required this.isLoading,
    required this.onSubmit,
    this.onFormDataChanged,
    this.onFilesChanged,
  });

  @override
  State<AuthFormWidget> createState() => _AuthFormWidgetState();
}

class _AuthFormWidgetState extends State<AuthFormWidget> {
  final _formKey = GlobalKey<FormState>();

  // Base controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Vendeur controllers
  final _shopNameController = TextEditingController();
  final _shopAddressController = TextEditingController();
  final _shopDescController = TextEditingController();
  List<String> _selectedCategoryIds = [];
  String? _categoryError;

  // Livreur controllers
  final _villeController = TextEditingController();
  final _quartierController = TextEditingController();
  final _preciseAddressController = TextEditingController();
  final _licensePlateController = TextEditingController();
  String _selectedVehicleType = 'moto';
  String _selectedAvailability = 'Temps_plein';

  bool _obscurePassword = true;
  bool _rememberMe = false;

  // Error/valid states
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _shopNameError;
  String? _shopAddressError;
  String? _shopDescError;
  String? _villeError;
  String? _quartierError;
  String? _preciseAddressError;
  String? _licensePlateError;

  bool _nameValid = false;
  bool _phoneValid = false;
  bool _emailValid = false;
  bool _passwordValid = false;
  bool _shopNameValid = false;
  bool _shopAddressValid = false;
  bool _shopDescValid = false;
  bool _villeValid = false;
  bool _quartierValid = false;
  bool _preciseAddressValid = false;
  bool _licensePlateValid = false;

  final List<Map<String, String>> _vehicleTypes = [
    {'value': 'moto', 'label': 'Moto'},
    {'value': 'voiture', 'label': 'Voiture'},
    {'value': 'tricycle', 'label': 'Tricycle'},
    {'value': 'velo', 'label': 'Vélo'},
  ];

  final List<Map<String, String>> _availabilities = [
    {'value': 'Temps_plein', 'label': 'Temps plein'},
    {'value': 'Temps_partiel', 'label': 'Temps partiel'},
  ];

  @override
  void initState() {
    super.initState();
    _attachValidators();
    _attachNotifiers();
  }

  void _attachValidators() {
    _nameController.addListener(_validateName);
    _phoneController.addListener(_validatePhone);
    _emailController.addListener(_validateEmail);
    _passwordController.addListener(_validatePassword);
    _shopNameController.addListener(_validateShopName);
    _shopAddressController.addListener(_validateShopAddress);
    _shopDescController.addListener(_validateShopDesc);
    _villeController.addListener(_validateVille);
    _quartierController.addListener(_validateQuartier);
    _preciseAddressController.addListener(_validatePreciseAddress);
    _licensePlateController.addListener(_validateLicensePlate);
  }

  void _attachNotifiers() {
    _emailController.addListener(
      () => widget.onFormDataChanged?.call(email: _emailController.text),
    );
    _passwordController.addListener(
      () => widget.onFormDataChanged?.call(password: _passwordController.text),
    );
    _nameController.addListener(
      () => widget.onFormDataChanged?.call(fullName: _nameController.text),
    );
    _phoneController.addListener(
      () => widget.onFormDataChanged?.call(phone: _phoneController.text),
    );
    _shopNameController.addListener(
      () => widget.onFormDataChanged?.call(shopName: _shopNameController.text),
    );
    _shopAddressController.addListener(
      () => widget.onFormDataChanged?.call(shopAddress: _shopAddressController.text),
    );
    _shopDescController.addListener(
      () => widget.onFormDataChanged?.call(shopDescription: _shopDescController.text),
    );
    _villeController.addListener(
      () => widget.onFormDataChanged?.call(ville: _villeController.text),
    );
    _quartierController.addListener(
      () => widget.onFormDataChanged?.call(quartier: _quartierController.text),
    );
    _preciseAddressController.addListener(
      () => widget.onFormDataChanged?.call(preciseAddress: _preciseAddressController.text),
    );
    _licensePlateController.addListener(
      () => widget.onFormDataChanged?.call(licensePlate: _licensePlateController.text),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _shopDescController.dispose();
    _villeController.dispose();
    _quartierController.dispose();
    _preciseAddressController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  // ── Validators ──────────────────────────────────────────────────────────────

  void _validateName() {
    final v = _nameController.text;
    setState(() {
      if (v.isEmpty) {
        _nameError = null;
        _nameValid = false;
      } else if (v.trim().length < 2) {
        _nameError = 'Nom trop court (min. 2 caractères)';
        _nameValid = false;
      } else {
        _nameError = null;
        _nameValid = true;
      }
    });
  }

  void _validatePhone() {
    final v = _phoneController.text;
    setState(() {
      if (v.isEmpty) {
        _phoneError = null;
        _phoneValid = false;
      } else if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(v.replaceAll(' ', ''))) {
        _phoneError = 'Numéro invalide (ex: +229 97 000 000)';
        _phoneValid = false;
      } else {
        _phoneError = null;
        _phoneValid = true;
      }
    });
  }

  void _validateEmail() {
    final v = _emailController.text;
    setState(() {
      if (v.isEmpty) {
        _emailError = null;
        _emailValid = false;
      } else if (!RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(v)) {
        _emailError = 'Format email invalide';
        _emailValid = false;
      } else {
        _emailError = null;
        _emailValid = true;
      }
    });
  }

  void _validatePassword() {
    final v = _passwordController.text;
    if (v.isEmpty) {
      setState(() { _passwordError = null; _passwordValid = false; });
    } else if (!widget.isLogin && v.length < 8) {
      setState(() { _passwordError = 'Minimum 8 caractères requis'; _passwordValid = false; });
    } else if (!widget.isLogin && !RegExp(r'(?=.*[A-Z])').hasMatch(v)) {
      setState(() { _passwordError = 'Doit contenir au moins une majuscule'; _passwordValid = false; });
    } else if (!widget.isLogin && !RegExp(r'(?=.*[0-9])').hasMatch(v)) {
      setState(() { _passwordError = 'Doit contenir au moins un chiffre'; _passwordValid = false; });
    } else if (!widget.isLogin && !RegExp(r'(?=.*[^a-zA-Z0-9])').hasMatch(v)) {
      setState(() { _passwordError = 'Doit contenir au moins un caractère spécial'; _passwordValid = false; });
    } else {
      setState(() { _passwordError = null; _passwordValid = true; });
    }
  }

  void _validateShopName() {
    final v = _shopNameController.text;
    setState(() {
      if (v.isEmpty) {
        _shopNameError = null; _shopNameValid = false;
      } else if (v.trim().length < 3) {
        _shopNameError = 'Nom trop court (min. 3 caractères)'; _shopNameValid = false;
      } else if (v.trim().length > 255) {
        _shopNameError = 'Nom trop long (max. 255 caractères)'; _shopNameValid = false;
      } else {
        _shopNameError = null; _shopNameValid = true;
      }
    });
  }

  void _validateShopAddress() {
    final v = _shopAddressController.text;
    setState(() {
      if (v.isEmpty) {
        _shopAddressError = null; _shopAddressValid = false;
      } else if (v.trim().length < 5) {
        _shopAddressError = 'Adresse trop courte (min. 5 caractères)'; _shopAddressValid = false;
      } else {
        _shopAddressError = null; _shopAddressValid = true;
      }
    });
  }

  void _validateShopDesc() {
    final v = _shopDescController.text;
    setState(() {
      if (v.isEmpty) {
        _shopDescError = null; _shopDescValid = false;
      } else if (v.trim().length < 10) {
        _shopDescError = 'Description trop courte (min. 10 caractères)'; _shopDescValid = false;
      } else {
        _shopDescError = null; _shopDescValid = true;
      }
    });
  }

  void _validateVille() {
    final v = _villeController.text;
    setState(() {
      if (v.isEmpty) {
        _villeError = null; _villeValid = false;
      } else if (v.trim().length < 2) {
        _villeError = 'Ville trop courte'; _villeValid = false;
      } else if (v.trim().length > 100) {
        _villeError = 'Ville trop longue (max. 100 car.)'; _villeValid = false;
      } else {
        _villeError = null; _villeValid = true;
      }
    });
  }

  void _validateQuartier() {
    final v = _quartierController.text;
    setState(() {
      if (v.isEmpty) {
        _quartierError = null; _quartierValid = false;
      } else if (v.trim().length < 2) {
        _quartierError = 'Quartier trop court'; _quartierValid = false;
      } else if (v.trim().length > 100) {
        _quartierError = 'Quartier trop long (max. 100 car.)'; _quartierValid = false;
      } else {
        _quartierError = null; _quartierValid = true;
      }
    });
  }

  void _validatePreciseAddress() {
    final v = _preciseAddressController.text;
    setState(() {
      if (v.isEmpty) {
        _preciseAddressError = null; _preciseAddressValid = false;
      } else if (v.trim().length < 5) {
        _preciseAddressError = 'Adresse trop courte'; _preciseAddressValid = false;
      } else {
        _preciseAddressError = null; _preciseAddressValid = true;
      }
    });
  }

  void _validateLicensePlate() {
    final v = _licensePlateController.text;
    setState(() {
      if (v.isEmpty) {
        _licensePlateError = null; _licensePlateValid = false;
      } else if (!RegExp(r'^[A-Z0-9\s\-]{3,20}$', caseSensitive: false).hasMatch(v.trim())) {
        _licensePlateError = 'Format invalide (ex: AB 1234 CD)'; _licensePlateValid = false;
      } else {
        _licensePlateError = null; _licensePlateValid = true;
      }
    });
  }

  // ── Password strength ───────────────────────────────────────────────────────

  int _passwordStrength(String v) {
    if (v.isEmpty) return 0;
    int score = 0;
    if (v.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(v)) score++;
    if (RegExp(r'[0-9]').hasMatch(v)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(v)) score++;
    return score;
  }

  Widget _buildPasswordStrengthBar(String password) {
    if (widget.isLogin || password.isEmpty) return const SizedBox.shrink();
    final strength = _passwordStrength(password);
    final labels = ['', 'Faible', 'Moyen', 'Bon', 'Fort'];
    final colors = [
      Colors.transparent,
      const Color(0xFFDC2626),
      const Color(0xFFF59E0B),
      const Color(0xFF3B82F6),
      const Color(0xFF16A34A),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                height: 4,
                decoration: BoxDecoration(
                  color: i < strength ? colors[strength] : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 4),
          Text(
            strength > 0 ? 'Force: ${labels[strength]}' : '',
            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: colors[strength]),
          ),
        ],
      ),
    );
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  void _handleSubmit() {
    if (!widget.isLogin) {
      _validateName();
      _validatePhone();
    }
    _validateEmail();
    _validatePassword();
    if (widget.accountType == 'vendeur') {
      _validateShopName();
      _validateShopAddress();
      _validateShopDesc();
    }
    if (widget.accountType == 'livreur') {
      _validateVille();
      _validateQuartier();
      _validatePreciseAddress();
      _validateLicensePlate();
    }

    // Les documents (pièce d'identité, selfie, photos produits/véhicule) ne
    // sont plus exigés à l'inscription : ils pourront être complétés plus
    // tard depuis l'écran "compléter mon dossier". hasFileError reste donc
    // toujours false — conservé pour ne pas modifier la logique de validation
    // du formulaire ci-dessous.
    bool hasFileError = false;

    final formValid = _formKey.currentState?.validate() ?? false;

    // Vendeur : au moins une categorie de la plateforme est obligatoire.
    if (widget.accountType == 'vendeur' && _selectedCategoryIds.isEmpty) {
      setState(() => _categoryError =
          'Choisissez au moins une catégorie pour votre boutique');
      return;
    }
    if (!formValid || hasFileError) return;

    if (widget.accountType == 'vendeur') {
      widget.onFormDataChanged?.call(categoryIds: _selectedCategoryIds);
      widget.onFilesChanged?.call();
    }
    if (widget.accountType == 'livreur') {
      widget.onFormDataChanged?.call(
        vehicleType: _selectedVehicleType,
        availability: _selectedAvailability,
      );
      widget.onFilesChanged?.call();
    }
    widget.onSubmit();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.isLogin) ...[
            _buildValidatedField(
              controller: _nameController,
              label: 'Nom complet',
              icon: Icons.person_outline_rounded,
              errorText: _nameError,
              isValid: _nameValid,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Veuillez entrer votre nom';
                if (v.trim().length < 2) return 'Nom trop court (min. 2 caractères)';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildValidatedField(
              controller: _phoneController,
              label: 'Numéro de téléphone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              errorText: _phoneError,
              isValid: _phoneValid,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Numéro requis';
                if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(normaliserTelephone(v))) {
                  return 'Numéro invalide (ex: +229 97 000 000)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
          _buildValidatedField(
            controller: _emailController,
            label: 'Adresse email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            errorText: _emailError,
            isValid: _emailValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email requis';
              if (!RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(v)) {
                return 'Format email invalide';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildPasswordFieldWithStrength(),
          if (widget.isLogin) ...[
            const SizedBox(height: 12),
            _buildRememberForgot(),
          ],
          if (!widget.isLogin && widget.accountType == 'vendeur') ...[
            const SizedBox(height: 24),
            _buildVendorSection(),
          ],
          if (!widget.isLogin && widget.accountType == 'livreur') ...[
            const SizedBox(height: 24),
            _buildDeliverySection(),
          ],
          const SizedBox(height: 28),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildValidatedField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? errorText,
    bool isValid = false,
    bool obscureText = false,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    return _FloatingLabelField(
      controller: controller,
      label: label,
      prefixIcon: icon,
      keyboardType: keyboardType,
      validator: validator,
      externalError: errorText,
      isValid: isValid,
      obscureText: obscureText,
      suffixIcon: suffixIcon,
      maxLines: maxLines,
    );
  }

  Widget _buildPasswordFieldWithStrength() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FloatingLabelField(
          controller: _passwordController,
          label: 'Mot de passe',
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          externalError: _passwordError,
          isValid: _passwordValid,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
              color: const Color(0xFF9E9E9E),
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Mot de passe requis';
            if (!widget.isLogin && v.length < 8) return 'Minimum 8 caractères';
            return null;
          },
        ),
        _buildPasswordStrengthBar(_passwordController.text),
      ],
    );
  }

  Widget _buildRememberForgot() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _rememberMe ? const Color(0xFFFF6210) : Colors.transparent,
                  border: Border.all(
                    color: _rememberMe ? const Color(0xFFFF6210) : const Color(0xFFE0E0E0),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: _rememberMe
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Se souvenir de moi',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF616161),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => _showForgotPasswordDialog(context),
          child: Text(
            'Mot de passe oublié ?',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF6210),
            ),
          ),
        ),
      ],
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailController.text);
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Mot de passe oublié',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entrez votre adresse email pour recevoir un lien de réinitialisation.',
                style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF616161), height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.outfit(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Adresse email',
                  labelStyle: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF9E9E9E)),
                  prefixIcon: const Icon(Icons.email_outlined, size: 20, color: Color(0xFF9E9E9E)),
                  filled: true,
                  fillColor: const Color(0xFFF8F8F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFF6210), width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(ctx),
              child: Text('Annuler', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF9E9E9E))),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty || !RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
                        AppToast.show(context, message: 'Veuillez entrer un email valide', type: ToastType.error);
                        return;
                      }
                      setDialogState(() => isSending = true);
                      final result = await NestAuthService.instance.forgotPassword(email);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (result.success) {
                        // Avant : on affichait juste "Email envoyé" et on
                        // s'arrêtait là — rien n'amenait ensuite la
                        // personne vers un endroit où saisir le code reçu
                        // et son nouveau mot de passe.
                        if (context.mounted) {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.resetPassword,
                            arguments: email,
                          );
                        }
                      } else {
                        if (context.mounted) {
                          AppToast.show(context, message: result.error ?? 'Erreur lors de l\'envoi', type: ToastType.error);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6210),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isSending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Envoyer', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vendor Section ──────────────────────────────────────────────────────────

  Widget _buildVendorSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6210).withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFFFF6210)),
              const SizedBox(width: 8),
              Text(
                'Informations de la boutique',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _shopNameController,
            label: 'Nom de la boutique',
            prefixIcon: Icons.store_outlined,
            externalError: _shopNameError,
            isValid: _shopNameValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Nom requis';
              if (v.trim().length < 3) return 'Nom trop court (min. 3 caractères)';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _shopAddressController,
            label: 'Adresse de la boutique',
            prefixIcon: Icons.location_on_outlined,
            externalError: _shopAddressError,
            isValid: _shopAddressValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Adresse de la boutique requise';
              return null;
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Catégories de la boutique (5 maximum)',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF444444),
            ),
          ),
          const SizedBox(height: 8),
          CategoryMultiSelect(
            selectedIds: _selectedCategoryIds,
            maxSelection: 5,
            onChanged: (ids) {
              setState(() {
                _selectedCategoryIds = ids;
                _categoryError = null;
              });
              widget.onFormDataChanged?.call(categoryIds: ids);
            },
          ),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _categoryError!,
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.red.shade700),
              ),
            ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _shopDescController,
            label: 'Description de la boutique',
            prefixIcon: Icons.description_outlined,
            maxLines: 3,
            externalError: _shopDescError,
            isValid: _shopDescValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Description requise';
              if (v.trim().length < 10) return 'Description trop courte (min. 10 caractères)';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── Delivery Section ────────────────────────────────────────────────────────

  Widget _buildDeliverySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6210).withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded, size: 18, color: Color(0xFFFF6210)),
              const SizedBox(width: 8),
              Text(
                'Informations livreur',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDropdown(
            label: 'Type d\'engin',
            icon: Icons.two_wheeler_outlined,
            value: _selectedVehicleType,
            items: _vehicleTypes,
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedVehicleType = val);
                widget.onFormDataChanged?.call(vehicleType: val);
              }
            },
          ),
          const SizedBox(height: 14),
          _buildDropdown(
            label: 'Disponibilité',
            icon: Icons.schedule_outlined,
            value: _selectedAvailability,
            items: _availabilities,
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedAvailability = val);
                widget.onFormDataChanged?.call(availability: val);
              }
            },
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _villeController,
            label: 'Ville principale',
            prefixIcon: Icons.location_city_outlined,
            externalError: _villeError,
            isValid: _villeValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ville requise';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _quartierController,
            label: 'Quartier',
            prefixIcon: Icons.map_outlined,
            externalError: _quartierError,
            isValid: _quartierValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Quartier requis';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _preciseAddressController,
            label: 'Adresse précise',
            prefixIcon: Icons.location_on_outlined,
            externalError: _preciseAddressError,
            isValid: _preciseAddressValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Adresse précise requise';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FloatingLabelField(
            controller: _licensePlateController,
            label: 'Numéro de plaque',
            prefixIcon: Icons.badge_outlined,
            externalError: _licensePlateError,
            isValid: _licensePlateValid,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Numéro de plaque requis';
              if (!RegExp(r'^[A-Z0-9\s\-]{3,20}$', caseSensitive: false).hasMatch(v.trim())) {
                return 'Format invalide (ex: AB 1234 CD)';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ──────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF9E9E9E),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<Map<String, String>> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF9E9E9E)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF9E9E9E)),
                style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF1A1A1A)),
                items: items.map((item) => DropdownMenuItem<String>(
                  value: item['value'],
                  child: Text(item['label']!),
                )).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6210).withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : _handleSubmit,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withAlpha(40),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.isLogin ? 'Se connecter' : 'Créer mon compte',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Floating Label Field ──────────────────────────────────────────────────────

class _FloatingLabelField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final String? externalError;
  final bool isValid;

  const _FloatingLabelField({
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.externalError,
    this.isValid = false,
  });

  @override
  State<_FloatingLabelField> createState() => _FloatingLabelFieldState();
}

class _FloatingLabelFieldState extends State<_FloatingLabelField>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _hasText = false;
  bool _hasTouched = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);

    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isFocused = _focusNode.hasFocus;
        if (_focusNode.hasFocus) _hasTouched = true;
      });
      if (_focusNode.hasFocus || widget.controller.text.isNotEmpty) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });

    widget.controller.addListener(() {
      if (!mounted) return;
      final hasText = widget.controller.text.isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
        if (hasText) {
          _animController.forward();
        } else if (!_isFocused) {
          _animController.reverse();
        }
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Color get _borderColor {
    if (widget.externalError != null && _hasTouched) return const Color(0xFFDC2626);
    if (widget.isValid) return const Color(0xFF16A34A);
    if (_isFocused) return const Color(0xFFFF6210);
    return const Color(0xFFE0E0E0);
  }

  Color get _fillColor {
    if (widget.externalError != null && _hasTouched) return const Color(0xFFFEF2F2);
    if (widget.isValid) return const Color(0xFFF0FDF4);
    if (_isFocused) return const Color(0xFFFFF8F5);
    return const Color(0xFFF8F8F8);
  }

  Color get _iconColor {
    if (widget.externalError != null && _hasTouched) return const Color(0xFFDC2626);
    if (widget.isValid) return const Color(0xFF16A34A);
    if (_isFocused) return const Color(0xFFFF6210);
    return const Color(0xFF9E9E9E);
  }

  @override
  Widget build(BuildContext context) {
    final showError = widget.externalError != null && _hasTouched;
    final showSuccess = widget.isValid && !showError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          maxLines: widget.maxLines,
          validator: widget.validator,
          onChanged: (_) => setState(() => _hasTouched = true),
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w400, color: const Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w400, color: _iconColor),
            floatingLabelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: _iconColor),
            prefixIcon: Icon(widget.prefixIcon, size: 20, color: _iconColor),
            suffixIcon: widget.suffixIcon ??
                (showSuccess
                    ? const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF16A34A))
                    : showError
                        ? const Icon(Icons.error_rounded, size: 20, color: Color(0xFFDC2626))
                        : null),
            filled: true,
            fillColor: _fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor, width: showSuccess ? 1.5 : 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
            ),
            errorStyle: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFDC2626)),
          ),
        ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFDC2626)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.externalError!,
                    style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFDC2626)),
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
                const Icon(Icons.check_circle_outline_rounded, size: 13, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  'Valide ✓',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
