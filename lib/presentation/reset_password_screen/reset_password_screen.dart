import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../services/nest_auth_service.dart';

/// Écran manquant du parcours "mot de passe oublié".
///
/// Avant : la boîte de dialogue "Mot de passe oublié" (voir
/// auth_form_widget.dart → _showForgotPasswordDialog) appelait
/// NestAuthService.forgotPassword(email), qui déclenche bien l'envoi d'un
/// code OTP par email (AuthService.forgotPassword côté serveur), mais
/// s'arrêtait ensuite sur un simple message "Email envoyé" — sans jamais
/// donner à la personne un endroit où taper ce code et son nouveau mot de
/// passe. Le serveur, lui, attendait bien ces informations sur
/// POST /auth/reset-password (voir AuthService.resetPassword), mais rien
/// dans l'app ne les envoyait jamais. Cet écran comble ce manque.
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _passwordStrongEnough {
    final v = _passwordController.text;
    return v.length >= 8 &&
        RegExp(r'[a-z]').hasMatch(v) &&
        RegExp(r'[A-Z]').hasMatch(v) &&
        RegExp(r'\d').hasMatch(v) &&
        RegExp(r'[^a-zA-Z0-9]').hasMatch(v);
  }

  Future<void> _handleSubmit() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      AppToast.show(context,
          message: 'Le code doit contenir 6 chiffres.', type: ToastType.error);
      return;
    }
    if (!_passwordStrongEnough) {
      AppToast.show(
        context,
        message:
            'Le mot de passe doit contenir au moins 8 caractères, une majuscule, '
            'une minuscule, un chiffre et un caractère spécial.',
        type: ToastType.error,
      );
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      AppToast.show(context,
          message: 'Les mots de passe ne correspondent pas.',
          type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await NestAuthService.instance.resetPassword(
      email: widget.email,
      code: code,
      newPassword: _passwordController.text,
      confirmPassword: _confirmController.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      AppToast.show(
        context,
        message: 'Mot de passe réinitialisé ! Connectez-vous avec le nouveau.',
        type: ToastType.success,
        duration: const Duration(seconds: 4),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.signUpLogin,
        (route) => false,
      );
    } else {
      AppToast.show(
        context,
        message: result.error ?? 'Code invalide ou expiré.',
        type: ToastType.error,
      );
    }
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    final result =
        await NestAuthService.instance.resendPasswordResetOtp(widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);
    AppToast.show(
      context,
      message: result.success
          ? 'Nouveau code envoyé à ${widget.email}.'
          : (result.error ?? 'Erreur lors du renvoi.'),
      type: result.success ? ToastType.success : ToastType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Réinitialiser le mot de passe',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Un code à 6 chiffres a été envoyé à ${widget.email}. '
              'Saisissez-le ci-dessous avec votre nouveau mot de passe.',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            _buildLabel('Code reçu par email'),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: AppTheme.textPrimary,
              ),
              decoration: _fieldDecoration(hint: '••••••').copyWith(counterText: ''),
            ),
            const SizedBox(height: 16),
            _buildLabel('Nouveau mot de passe'),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
              decoration: _fieldDecoration(hint: 'Min. 8 caractères').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Majuscule, minuscule, chiffre et caractère spécial requis.',
              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            _buildLabel('Confirmer le mot de passe'),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
              decoration: _fieldDecoration(hint: 'Retapez le mot de passe').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Réinitialiser le mot de passe',
                        style: GoogleFonts.outfit(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _isResending ? null : _handleResend,
                child: Text(
                  _isResending ? 'Envoi en cours…' : 'Renvoyer le code',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
      filled: true,
      fillColor: AppTheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }
}
