import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// Boîte de dialogue « Adresse du serveur » : permet de coller l'adresse du
/// jour (tunnel Cloudflare, IP Wi-Fi...) sans refaire d'APK.
/// Ouverte par un appui long sur le logo de la page de connexion.
Future<void> afficherDialogueAdresseServeur(BuildContext context) {
  // Inaccessible dans la version de production (voir kReglageServeurActif).
  if (!kReglageServeurActif) return Future<void>.value();
  return showDialog<void>(
    context: context,
    builder: (_) => _ServerAddressDialog(parentContext: context),
  );
}

class _ServerAddressDialog extends StatefulWidget {
  final BuildContext parentContext;
  const _ServerAddressDialog({required this.parentContext});

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _erreur;
  String? _succes;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ApiService.instance.adresseActuelle,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tester() async {
    setState(() {
      _busy = true;
      _erreur = null;
      _succes = null;
    });
    final res = await ApiService.testerAdresse(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res == null) {
        _succes = 'Le serveur répond.';
      } else {
        _erreur = res;
      }
    });
  }

  /// Demande une confirmation explicite en affichant le domaine saisi.
  /// Retourne true si l'utilisateur accepte.
  Future<bool> _confirmerDomaine(String adresse) async {
    final uri = Uri.tryParse(adresse);
    final domaine = (uri == null || uri.host.isEmpty)
        ? adresse
        : (uri.hasPort ? '${uri.host}:${uri.port}' : uri.host);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Confirmer ce serveur ?',
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'L\'appli enverra vos identifiants et vos données à :',
              style: GoogleFonts.outfit(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              domaine,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Continuez seulement si cette adresse vous a été donnée par '
              'l\'équipe Asoukaa.',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: const Color(0xFF6B6B6B),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Oui, utiliser ce serveur'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _enregistrer() async {
    setState(() {
      _busy = true;
      _erreur = null;
      _succes = null;
    });
    final erreur = ApiService.erreurAdresse(_controller.text);
    final propre = erreur == null
        ? ApiService.normaliserAdresse(_controller.text)
        : null;
    if (erreur != null || propre == null) {
      setState(() {
        _busy = false;
        _erreur = erreur ?? 'Adresse invalide ou refusée.';
      });
      return;
    }
    // Adresse différente de celle d'usine : confirmation explicite.
    if (propre != ApiService.instance.adresseParDefaut) {
      final confirme = await _confirmerDomaine(propre);
      if (!mounted) return;
      if (!confirme) {
        setState(() => _busy = false);
        return;
      }
    }
    final appliquee = await ApiService.instance.definirAdresse(propre);
    if (!mounted) return;
    if (appliquee == null) {
      setState(() {
        _busy = false;
        _erreur = 'Adresse invalide ou refusée.';
      });
      return;
    }
    final parent = widget.parentContext;
    Navigator.of(context).pop();
    if (!parent.mounted) return;
    AppToast.show(
      parent,
      message: 'Serveur enregistré : $appliquee',
      type: ToastType.success,
    );
  }

  Future<void> _reinitialiser() async {
    setState(() => _busy = true);
    final defaut = await ApiService.instance.definirAdresse(null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _erreur = null;
      _succes = null;
      _controller.text = defaut ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Adresse du serveur',
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Colle ici l\'adresse reçue (WhatsApp). Réservé aux tests.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: const Color(0xFF6B6B6B),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ne collez ici qu\'une adresse donnée par l\'équipe '
                      'Asoukaa : une mauvaise adresse peut voler vos '
                      'identifiants.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9A3A00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 3,
              style: GoogleFonts.outfit(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://xxxx.trycloudflare.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(
                _erreur!,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ],
            if (_succes != null) ...[
              const SizedBox(height: 8),
              Text(
                _succes!,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: const Color(0xFF16A34A),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _reinitialiser,
                child: Text(
                  'Revenir à l\'adresse d\'origine',
                  style: GoogleFonts.outfit(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _busy ? null : _tester,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Tester'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _enregistrer,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
