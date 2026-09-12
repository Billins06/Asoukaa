import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/nest_auth_service.dart';
import './widgets/account_type_selector_widget.dart';
import './widgets/auth_form_widget.dart';
import './widgets/auth_logo_widget.dart';

class SignUpLoginScreen extends StatefulWidget {
  const SignUpLoginScreen({super.key});

  @override
  State<SignUpLoginScreen> createState() => _SignUpLoginScreenState();
}

class _SignUpLoginScreenState extends State<SignUpLoginScreen>
    with TickerProviderStateMixin {
  bool _isLogin = true;
  String _selectedAccountType = 'acheteur';
  bool _isLoading = false;

  // Base form data
  String _email = '';
  String _password = '';
  String _fullName = '';
  String _phone = '';

  // Vendeur data (stocké pour onboarding post-login)
  String _shopName = '';
  String _shopAddress = '';
  String _activityType = '';
  String _shopDescription = '';

  // Livreur data
  String _ville = '';
  String _quartier = '';
  String _preciseAddress = '';
  String _vehicleType = 'MOTO';
  String _availability = 'Temps_plein';
  String _licensePlate = '';

  // Fichiers photos (vendeur/livreur)
  XFile? _idDocumentFile;
  XFile? _selfieFile;
  List<XFile> _sampleProductFiles = [];
  XFile? _vehiclePhotoFile;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() => _isLogin = !_isLogin);
    _fadeController.reset();
    _slideController.reset();
    _fadeController.forward();
    _slideController.forward();
  }

  void _onFormDataChanged({
    String? email,
    String? password,
    String? fullName,
    String? phone,
    // Vendeur
    String? shopName,
    String? shopAddress,
    String? activityType,
    String? shopDescription,
    // Livreur
    String? ville,
    String? quartier,
    String? preciseAddress,
    String? vehicleType,
    String? availability,
    String? licensePlate,
  }) {
    if (email != null) _email = email;
    if (password != null) _password = password;
    if (fullName != null) _fullName = fullName;
    if (phone != null) _phone = phone;
    if (shopName != null) _shopName = shopName;
    if (shopAddress != null) _shopAddress = shopAddress;
    if (activityType != null) _activityType = activityType;
    if (shopDescription != null) _shopDescription = shopDescription;
    if (ville != null) _ville = ville;
    if (quartier != null) _quartier = quartier;
    if (preciseAddress != null) _preciseAddress = preciseAddress;
    if (vehicleType != null) _vehicleType = vehicleType;
    if (availability != null) _availability = availability;
    if (licensePlate != null) _licensePlate = licensePlate;
  }

  void _onFilesChanged({
    XFile? idDocument,
    XFile? selfie,
    List<XFile>? sampleProducts,
    XFile? vehiclePhoto,
  }) {
    if (idDocument != null) _idDocumentFile = idDocument;
    if (selfie != null) _selfieFile = selfie;
    if (sampleProducts != null) _sampleProductFiles = sampleProducts;
    if (vehiclePhoto != null) _vehiclePhotoFile = vehiclePhoto;
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final result = await NestAuthService.instance.login(
          identifier: _email,
          password: _password,
        );

        if (!mounted) return;

        if (result.success) {
          AppToast.show(
            context,
            message: 'Connexion réussie ! Bienvenue',
            type: ToastType.success,
          );
          await _navigateByRole();
        } else {
          AppToast.show(
            context,
            message: result.error ?? 'Erreur de connexion',
            type: ToastType.error,
          );
        }
      } else {
        final result = await NestAuthService.instance.register(
          fullName: _fullName,
          email: _email,
          phone: _phone,
          password: _password,
        );

        if (!mounted) return;

        if (result.success) {
          AppToast.show(
            context,
            message: 'Compte créé ! Vérifiez votre email.',
            type: ToastType.success,
          );
          if (!mounted) return;
          Navigator.pushNamed(
            context,
            AppRoutes.otpVerification,
            arguments: {
              'email': _email,
              'password': _password,
              'accountType': _selectedAccountType,
              'shopName': _shopName,
              'shopAddress': _shopAddress,
              'activityType': _activityType,
              'shopDescription': _shopDescription,
              'ville': _ville,
              'quartier': _quartier,
              'preciseAddress': _preciseAddress,
              'vehicleType': _vehicleType,
              'availability': _availability,
              'licensePlate': _licensePlate,
              'idDocumentFile': _idDocumentFile,
              'selfieFile': _selfieFile,
              'sampleProductFiles': _sampleProductFiles,
              'vehiclePhotoFile': _vehiclePhotoFile,
            },
          );
        } else {
          AppToast.show(
            context,
            message: result.error ?? 'Erreur lors de la création du compte',
            type: ToastType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur inattendue. Veuillez réessayer.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateByRole() async {
    String role;
    try {
      role = await NestAuthService.instance.getUserRole();
    } catch (_) {
      role = 'acheteur';
    }
    if (!mounted) return;
    switch (role) {
      case 'vendeur':
        Navigator.pushReplacementNamed(context, AppRoutes.sellerDashboard);
        break;
      case 'livreur':
        Navigator.pushReplacementNamed(context, AppRoutes.delivererDashboard);
        break;
      case 'admin':
        Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
        break;
      default:
        Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const AuthLogoWidget(),
                const SizedBox(height: 16),
                // Taglines
                _buildTaglines(),
                const SizedBox(height: 24),
                _buildModeToggle(),
                const SizedBox(height: 28),
                if (!_isLogin) ...[
                  AccountTypeSelectorWidget(
                    selectedType: _selectedAccountType,
                    onTypeChanged: (type) =>
                        setState(() => _selectedAccountType = type),
                  ),
                  const SizedBox(height: 24),
                ],
                AuthFormWidget(
                  isLogin: _isLogin,
                  accountType: _selectedAccountType,
                  isLoading: _isLoading,
                  onSubmit: _handleSubmit,
                  onFormDataChanged: _onFormDataChanged,
                  onFilesChanged: _onFilesChanged,
                ),
                const SizedBox(height: 20),
                _buildSwitchModeRow(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Center(
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 40),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 40,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLogoWidget(),
                  const SizedBox(height: 32),
                  _buildModeToggle(),
                  const SizedBox(height: 28),
                  if (!_isLogin) ...[
                    AccountTypeSelectorWidget(
                      selectedType: _selectedAccountType,
                      onTypeChanged: (type) =>
                          setState(() => _selectedAccountType = type),
                    ),
                    const SizedBox(height: 24),
                  ],
                  AuthFormWidget(
                    isLogin: _isLogin,
                    accountType: _selectedAccountType,
                    isLoading: _isLoading,
                    onSubmit: _handleSubmit,
                    onFormDataChanged: _onFormDataChanged,
                  ),
                  const SizedBox(height: 20),
                  _buildSwitchModeRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_isLogin) _switchMode();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _isLogin
                      ? [
                          BoxShadow(
                            color: Colors.black.withAlpha(15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Connexion',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: _isLogin ? FontWeight.w600 : FontWeight.w400,
                    color: _isLogin
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_isLogin) _switchMode();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !_isLogin
                      ? [
                          BoxShadow(
                            color: Colors.black.withAlpha(15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Inscription',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: !_isLogin ? FontWeight.w600 : FontWeight.w400,
                    color: !_isLogin
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchModeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? 'Pas encore de compte ? ' : 'Déjà un compte ? ',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF616161),
          ),
        ),
        GestureDetector(
          onTap: _switchMode,
          child: Text(
            _isLogin ? 'S\'inscrire' : 'Se connecter',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFF6210),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaglines() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          _TaglineItem(
            icon: Icons.inventory_2_outlined,
            text: 'Milliers de produits',
          ),
          const SizedBox(height: 10),
          _TaglineItem(icon: Icons.shield_outlined, text: 'Paiement sécurisé'),
          const SizedBox(height: 10),
          _TaglineItem(
            icon: Icons.local_shipping_outlined,
            text: 'Livraison rapide et partout',
          ),
        ],
      ),
    );
  }
}

// ─── Tagline Item Widget ──────────────────────────────────────────────────────

class _TaglineItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TaglineItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDE3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFFF6210), size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF616161),
          ),
        ),
      ],
    );
  }
}
