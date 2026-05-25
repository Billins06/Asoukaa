import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/app_toast.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String password;
  final String accountType;

  // Vendeur
  final String? shopName;
  final String? shopAddress;
  final String? activityType;
  final String? shopDescription;

  // Livreur
  final String? ville;
  final String? quartier;
  final String? preciseAddress;
  final String? vehicleType;
  final String? availability;
  final String? licensePlate;

  // Fichiers
  final XFile? idDocumentFile;
  final XFile? selfieFile;
  final List<XFile>? sampleProductFiles;
  final XFile? vehiclePhotoFile;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.password = '',
    this.accountType = 'acheteur',
    this.shopName,
    this.shopAddress,
    this.activityType,
    this.shopDescription,
    this.ville,
    this.quartier,
    this.preciseAddress,
    this.vehicleType,
    this.availability,
    this.licensePlate,
    this.idDocumentFile,
    this.selfieFile,
    this.sampleProductFiles,
    this.vehiclePhotoFile,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  bool _isProcessing = false;
  String _processingStep = '';

  // Compte à rebours 3 minutes
  int _expirySeconds = 180;
  bool _isExpired = false;

  // Anti-spam renvoyer (60 secondes)
  int _resendCooldown = 0;

  Timer? _expiryTimer;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startExpiryCountdown();
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  void _startExpiryCountdown() {
    _expiryTimer?.cancel();
    setState(() {
      _expirySeconds = 180;
      _isExpired = false;
    });
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_expirySeconds > 0) {
          _expirySeconds--;
        } else {
          _isExpired = true;
          timer.cancel();
        }
      });
    });
  }

  String get _expiryLabel {
    final m = _expirySeconds ~/ 60;
    final s = _expirySeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── OTP ───────────────────────────────────────────────────────────────────

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
    if (_otpCode.length == 6 && !_isExpired) _verifyOtp();
  }

  Future<void> _verifyOtp() async {
    if (_isVerifying || _otpCode.length < 6 || _isExpired) return;
    setState(() => _isVerifying = true);

    final result = await NestAuthService.instance.verifyOtp(
      email: widget.email,
      code: _otpCode,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result.success) {
      _expiryTimer?.cancel();

      final isVendorOrAgent =
          widget.accountType == 'vendeur' || widget.accountType == 'livreur';

      if (isVendorOrAgent && widget.password.isNotEmpty) {
        await _autoLoginAndSubmitProfile();
      } else if (widget.password.isNotEmpty) {
        // Acheteur : auto-login puis HomeScreen
        await _autoLoginAcheteur();
      } else {
        AppToast.show(
          context,
          message: 'Email vérifié ! Connectez-vous pour accéder à votre compte.',
          type: ToastType.success,
        );
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.signUpLogin,
          (_) => false,
        );
      }
    } else {
      AppToast.show(
        context,
        message: result.error ?? 'Code invalide ou expiré.',
        type: ToastType.error,
      );
      for (final c in _controllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    }
  }

  // ── Auto-login + Upload + Submit profile ───────────────────────────────────

  Future<void> _autoLoginAndSubmitProfile() async {
    setState(() { _isProcessing = true; _processingStep = 'Connexion en cours…'; });

    try {
      // 1. Auto-login
      final loginResult = await NestAuthService.instance.login(
        identifier: widget.email,
        password: widget.password,
      );

      if (!mounted) return;

      if (!loginResult.success) {
        _fallbackToLogin('Email vérifié. Connectez-vous manuellement.');
        return;
      }

      // 2. Upload pièce d'identité
      setState(() => _processingStep = 'Upload de la pièce d\'identité…');
      final idDocFile = widget.idDocumentFile;
      if (idDocFile == null) { _fallbackToLogin('Document manquant.'); return; }
      final idDocUrl = await UploadService.instance.uploadFile(idDocFile, 'documents');

      // 3. Upload selfie
      if (!mounted) return;
      setState(() => _processingStep = 'Upload du selfie…');
      final selfieFile = widget.selfieFile;
      if (selfieFile == null) { _fallbackToLogin('Selfie manquant.'); return; }
      final selfieUrl = await UploadService.instance.uploadFile(selfieFile, 'selfies');

      if (!mounted) return;

      if (widget.accountType == 'vendeur') {
        // 4. Upload photos produits
        setState(() => _processingStep = 'Upload des photos produits…');
        final sampleUrls = await UploadService.instance.uploadMultiple(
          widget.sampleProductFiles ?? [],
          'products',
        );

        // 5. Soumettre profil vendeur
        if (!mounted) return;
        setState(() => _processingStep = 'Envoi du dossier vendeur…');
        final profileResult = await NestAuthService.instance.submitVendorProfile(
          shopName: widget.shopName ?? '',
          shopAddress: widget.shopAddress ?? '',
          activityType: widget.activityType ?? '',
          description: widget.shopDescription ?? '',
          idDocumentUrl: idDocUrl,
          selfieUrl: selfieUrl,
          sampleProductUrls: sampleUrls,
        );

        if (!mounted) return;

        if (profileResult.success) {
          AppToast.show(
            context,
            message: 'Dossier soumis ! En attente de validation par l\'admin.',
            type: ToastType.success,
            duration: const Duration(seconds: 5),
          );
        } else {
          AppToast.show(
            context,
            message: profileResult.error ?? 'Erreur lors de la soumission.',
            type: ToastType.error,
          );
        }
      }

      if (widget.accountType == 'livreur') {
        // 4. Upload photo véhicule
        setState(() => _processingStep = 'Upload de la photo du véhicule…');
        final vehicleFile = widget.vehiclePhotoFile;
        if (vehicleFile == null) { _fallbackToLogin('Photo véhicule manquante.'); return; }
        final vehicleUrl = await UploadService.instance.uploadFile(vehicleFile, 'vehicles');

        // 5. Soumettre profil livreur
        if (!mounted) return;
        setState(() => _processingStep = 'Envoi du dossier livreur…');
        final profileResult = await NestAuthService.instance.submitAgentProfile(
          vehicleType: widget.vehicleType ?? 'MOTO',
          availability: widget.availability ?? 'Temps_plein',
          ville: widget.ville ?? '',
          quartier: widget.quartier ?? '',
          preciseAddress: widget.preciseAddress ?? '',
          idDocumentUrl: idDocUrl,
          selfieUrl: selfieUrl,
          vehiclePhotoUrl: vehicleUrl,
          licensePlate: widget.licensePlate ?? '',
        );

        if (!mounted) return;

        if (profileResult.success) {
          AppToast.show(
            context,
            message: 'Dossier soumis ! En attente de validation par l\'admin.',
            type: ToastType.success,
            duration: const Duration(seconds: 5),
          );
        } else {
          AppToast.show(
            context,
            message: profileResult.error ?? 'Erreur lors de la soumission.',
            type: ToastType.error,
          );
        }
      }

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
    } catch (_) {
      if (!mounted) return;
      _fallbackToLogin('Une erreur est survenue. Connectez-vous manuellement.');
    }
  }

  Future<void> _autoLoginAcheteur() async {
    setState(() { _isProcessing = true; _processingStep = 'Connexion en cours…'; });
    try {
      final loginResult = await NestAuthService.instance.login(
        identifier: widget.email,
        password: widget.password,
      );
      if (!mounted) return;
      if (loginResult.success) {
        AppToast.show(
          context,
          message: 'Bienvenue ! Votre compte est prêt.',
          type: ToastType.success,
        );
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
      } else {
        _fallbackToLogin('Email vérifié. Connectez-vous pour continuer.');
      }
    } catch (_) {
      if (!mounted) return;
      _fallbackToLogin('Email vérifié. Connectez-vous pour continuer.');
    }
  }

  void _fallbackToLogin(String message) {
    setState(() => _isProcessing = false);
    AppToast.show(context, message: message, type: ToastType.info);
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.signUpLogin, (_) => false);
  }

  // ── Resend ────────────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    if (_isResending || _resendCooldown > 0) return;
    setState(() => _isResending = true);

    final result = await NestAuthService.instance.resendOtp(widget.email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.success) {
      AppToast.show(
        context,
        message: 'Nouveau code envoyé à ${widget.email}',
        type: ToastType.success,
      );
      _startExpiryCountdown();
      _startResendCooldown();
      for (final c in _controllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    } else {
      AppToast.show(
        context,
        message: result.error ?? 'Erreur lors du renvoi.',
        type: ToastType.error,
      );
    }
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFFAFAFA),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: _isProcessing
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      color: Color(0xFF1A1A1A),
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDE3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      color: Color(0xFFFF6210),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Vérification email',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Code envoyé à',
                    style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF616161)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.email,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF6210),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  _buildExpiryTimer(),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, _buildDigitBox),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_isVerifying || _otpCode.length < 6 || _isExpired || _isProcessing)
                          ? null
                          : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6210),
                        disabledBackgroundColor: const Color(0xFFE0E0E0),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Vérifier mon compte',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildResendButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        // Overlay de traitement (upload / soumission profil)
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6210)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Finalisation de votre inscription',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _processingStep,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: const Color(0xFF616161),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpiryTimer() {
    if (_isExpired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDC2626).withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_rounded, color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 8),
            Text(
              'Code expiré — demandez un nouveau code',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      );
    }

    final isUrgent = _expirySeconds <= 30;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isUrgent ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUrgent
              ? const Color(0xFFDC2626).withAlpha(60)
              : const Color(0xFF16A34A).withAlpha(60),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Code valide encore ',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            ),
          ),
          Text(
            _expiryLabel,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResendButton() {
    final canResend = _resendCooldown <= 0 && !_isResending && !_isProcessing;

    return GestureDetector(
      onTap: canResend ? _resendOtp : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: canResend
              ? const Color(0xFFFF6210).withAlpha(15)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canResend
                ? const Color(0xFFFF6210).withAlpha(80)
                : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isResending)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF6210),
                ),
              )
            else
              Icon(
                Icons.refresh_rounded,
                size: 16,
                color: canResend ? const Color(0xFFFF6210) : const Color(0xFF9E9E9E),
              ),
            const SizedBox(width: 8),
            Text(
              _isResending
                  ? 'Envoi en cours...'
                  : _resendCooldown > 0
                      ? 'Renvoyer dans ${_resendCooldown}s'
                      : 'Renvoyer le code',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: canResend ? const Color(0xFFFF6210) : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        enabled: !_isExpired && !_isProcessing,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: (_isExpired || _isProcessing) ? const Color(0xFFF5F5F5) : Colors.white,
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
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
        ),
        onChanged: (v) => _onDigitChanged(index, v),
      ),
    );
  }
}
