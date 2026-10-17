import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/email_change_service.dart';

/// Changement d'adresse e-mail, partagé par les profils client, vendeur et
/// livreur. Trois étapes : avertissement + saisie, code à 6 chiffres reçu sur
/// la nouvelle adresse, confirmation.
///
/// Ferme l'écran avec la nouvelle adresse (String) en résultat quand le
/// changement a réussi, sinon avec null.
class ChangeEmailScreen extends StatefulWidget {
  /// Adresse actuelle (affichage seulement).
  final String currentEmail;

  const ChangeEmailScreen({super.key, this.currentEmail = ''});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  static const int _etapeSaisie = 0;
  static const int _etapeCode = 1;
  static const int _etapeSucces = 2;

  static const int _delaiRenvoiSecondes = 60;
  static const int _validiteParDefautSecondes = 600;

  int _etape = _etapeSaisie;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isBusy = false;
  String? _error;

  String _nouvelEmail = '';
  String? _emailConfirme;

  Timer? _timer;
  int _secondesRestantes = 0; // validité du code
  int _secondesAvantRenvoi = 0; // délai avant de pouvoir renvoyer

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Compte à rebours ───────────────────────────────────────────────────────

  void _demarrerCompteARebours(int validiteSecondes) {
    _timer?.cancel();
    _secondesRestantes = validiteSecondes;
    _secondesAvantRenvoi = _delaiRenvoiSecondes;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_secondesRestantes > 0) _secondesRestantes--;
        if (_secondesAvantRenvoi > 0) _secondesAvantRenvoi--;
      });
      if (_secondesRestantes == 0 && _secondesAvantRenvoi == 0) t.cancel();
    });
  }

  String _formaterDuree(int secondes) {
    final m = (secondes ~/ 60).toString().padLeft(2, '0');
    final s = (secondes % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _envoyerCode() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!EmailChangeService.isValidEmail(email)) {
      setState(() => _error = 'Saisissez une adresse e-mail valide.');
      return;
    }
    if (widget.currentEmail.isNotEmpty &&
        email.toLowerCase() == widget.currentEmail.trim().toLowerCase()) {
      setState(() => _error = 'Cette adresse est déjà la vôtre.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Saisissez votre mot de passe actuel.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });
    final result = await EmailChangeService.instance.requestChange(
      newEmail: email,
      currentPassword: password,
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _isBusy = false;
        _nouvelEmail = email.toLowerCase();
        _codeCtrl.clear();
        _etape = _etapeCode;
      });
      _demarrerCompteARebours(
        result.expiresInSeconds ?? _validiteParDefautSecondes,
      );
    } else {
      setState(() {
        _isBusy = false;
        _error = result.error ?? 'Erreur. Veuillez réessayer.';
      });
    }
  }

  Future<void> _renvoyerCode() async {
    if (_isBusy || _secondesAvantRenvoi > 0) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final result = await EmailChangeService.instance.resendCode();
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _isBusy = false;
        _codeCtrl.clear();
      });
      _demarrerCompteARebours(
        result.expiresInSeconds ?? _validiteParDefautSecondes,
      );
      AppToast.show(
        context,
        message: 'Un nouveau code a été envoyé.',
        type: ToastType.success,
      );
    } else {
      setState(() {
        _isBusy = false;
        _error = result.error ?? 'Erreur lors du renvoi du code.';
      });
    }
  }

  Future<void> _confirmerCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Saisissez le code à 6 chiffres.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final result = await EmailChangeService.instance.confirm(code);
    if (!mounted) return;
    if (result.success) {
      _timer?.cancel();
      setState(() {
        _isBusy = false;
        _emailConfirme = (result.email != null && result.email!.isNotEmpty)
            ? result.email
            : _nouvelEmail;
        _etape = _etapeSucces;
      });
    } else {
      // Le message du serveur est affiché tel quel (tentatives restantes,
      // code expiré, etc.).
      setState(() {
        _isBusy = false;
        _error = result.error ?? 'Code incorrect.';
      });
    }
  }

  void _terminer() {
    Navigator.pop(context, _emailConfirme);
  }

  void _retourEtapePrecedente() {
    _timer?.cancel();
    setState(() {
      _etape = _etapeSaisie;
      _error = null;
    });
  }

  // ── Construction ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Le retour système doit faire la même chose que la flèche de l'AppBar :
      // il ne quitte l'écran qu'à l'étape de saisie. À l'étape du code il
      // revient à l'étape 1 ; à l'étape de succès il renvoie quand même la
      // nouvelle adresse à l'écran précédent.
      canPop: _etape == _etapeSaisie,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_etape == _etapeSucces) {
          _terminer();
        } else if (_etape == _etapeCode) {
          _retourEtapePrecedente();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary,
              size: 20,
            ),
            onPressed: () {
              if (_etape == _etapeSucces) {
                _terminer();
              } else if (_etape == _etapeCode) {
                _retourEtapePrecedente();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            'Modifier mon e-mail',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: _etape == _etapeSaisie
                ? _buildEtapeSaisie()
                : _etape == _etapeCode
                    ? _buildEtapeCode()
                    : _buildEtapeSucces(),
          ),
        ),
      ),
    );
  }

  Widget _buildEtapeSaisie() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(90)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cette adresse sert à vous connecter et à récupérer votre '
                  'compte. Si vous la changez, vous devrez utiliser la '
                  'nouvelle adresse pour vous connecter. Ne la changez que si '
                  'vous avez accès à la nouvelle boîte mail.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.currentEmail.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Adresse actuelle',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.currentEmail,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildLabel('Nouvelle adresse e-mail'),
        const SizedBox(height: 6),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
          decoration: _decoration(
            hint: 'nouvelle.adresse@exemple.com',
            icon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('Mot de passe actuel'),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) {
            if (!_isBusy) _envoyerCode();
          },
          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.textPrimary),
          decoration: _decoration(
            hint: 'Votre mot de passe',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.muted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _buildErreur(_error!),
        ],
        const SizedBox(height: 24),
        _buildBoutonPrincipal(
          label: 'Envoyer le code',
          onPressed: _isBusy ? null : _envoyerCode,
        ),
      ],
    );
  }

  Widget _buildEtapeCode() {
    final expire = _secondesRestantes == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mark_email_read_outlined,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nous avons envoyé un code à 6 chiffres à $_nouvelEmail. '
                  'Saisissez-le ci-dessous pour confirmer le changement.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildLabel('Code de vérification'),
        const SizedBox(height: 6),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => _error = null),
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
            color: AppTheme.textPrimary,
          ),
          decoration: _decoration(hint: '------').copyWith(counterText: ''),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              expire ? Icons.timer_off_outlined : Icons.timer_outlined,
              size: 16,
              color: expire ? AppTheme.error : AppTheme.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                expire
                    ? 'Le code a expiré. Demandez-en un nouveau.'
                    : 'Le code expire dans ${_formaterDuree(_secondesRestantes)}',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: expire ? AppTheme.error : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _buildErreur(_error!),
        ],
        const SizedBox(height: 20),
        _buildBoutonPrincipal(
          label: 'Confirmer',
          onPressed: (_isBusy || _codeCtrl.text.trim().length != 6)
              ? null
              : _confirmerCode,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: (_isBusy || _secondesAvantRenvoi > 0)
                ? null
                : _renvoyerCode,
            child: Text(
              _secondesAvantRenvoi > 0
                  ? 'Renvoyer le code (${_secondesAvantRenvoi}s)'
                  : 'Renvoyer le code',
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _secondesAvantRenvoi > 0 || _isBusy
                    ? AppTheme.muted
                    : AppTheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEtapeSucces() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: AppTheme.successContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppTheme.success, size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          'Adresse modifiée',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        if (_emailConfirme != null) ...[
          const SizedBox(height: 6),
          Text(
            _emailConfirme!,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Nous avons envoyé une alerte à votre ancienne adresse ; si ce '
          'n\'était pas vous, elle contient un bouton pour annuler pendant '
          '7 jours.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 13.5,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        _buildBoutonPrincipal(label: 'Retour au profil', onPressed: _terminer),
      ],
    );
  }

  // ── Éléments communs ───────────────────────────────────────────────────────

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

  Widget _buildErreur(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.error.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoutonPrincipal({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.outline,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isBusy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
      prefixIcon:
          icon == null ? null : Icon(icon, color: AppTheme.muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppTheme.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }
}
