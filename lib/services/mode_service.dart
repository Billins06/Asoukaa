import 'package:shared_preferences/shared_preferences.dart';

import 'nest_auth_service.dart';
import 'token_storage_service.dart';

/// Mémoire du dernier mode utilisé par un compte qui cumule client + vendeur.
///
/// Un vendeur peut « passer en mode client » (acheter comme n'importe quel
/// client) puis revenir. On mémorise le dernier choix pour rouvrir l'appli du
/// bon côté. La valeur est rangée sous la clé `dernier_mode_<userId>` : un
/// autre compte connecté sur le même téléphone ne voit jamais ce choix.
///
/// Valeurs : [client] ou [vendeur]. Les livreurs et admins ne sont pas
/// concernés (leur rôle n'est jamais modifié ici).
class ModeService {
  static ModeService? _instance;
  static ModeService get instance => _instance ??= ModeService._();
  ModeService._();

  static const String client = 'client';
  static const String vendeur = 'vendeur';

  Future<String?> _cle() async {
    final id = await TokenStorageService.instance.getUserId();
    if (id == null || id.isEmpty) return null;
    return 'dernier_mode_$id';
  }

  /// Dernier mode mémorisé pour le compte connecté, ou null.
  Future<String?> getLastMode() async {
    try {
      final cle = await _cle();
      if (cle == null) return null;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(cle);
    } catch (_) {
      return null;
    }
  }

  /// Mémorise le mode choisi ([client] ou [vendeur]) pour le compte connecté.
  Future<void> setLastMode(String mode) async {
    if (mode != client && mode != vendeur) return;
    try {
      final cle = await _cle();
      if (cle == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cle, mode);
    } catch (_) {}
  }

  /// Rôle à utiliser pour choisir la page d'ouverture : identique à
  /// [NestAuthService.getUserRole], sauf pour un vendeur dont le dernier mode
  /// est « client » (il retrouve alors l'accueil client).
  Future<String> getEffectiveRole() async {
    final role = await NestAuthService.instance.getUserRole();
    if (role == 'vendeur') {
      final mode = await getLastMode();
      if (mode == client) return 'acheteur';
    }
    return role;
  }

  /// Un compte client dont la demande vendeur vient d'être approuvée garde
  /// le rôle « client » en mémoire locale jusqu'à sa prochaine connexion.
  /// On le passe à « vendor » quand il bascule en mode vendeur, pour que
  /// l'appli le rouvre ensuite côté vendeur. Sans effet pour les autres rôles.
  Future<void> promoteStoredRoleToVendor() async {
    try {
      final stockage = TokenStorageService.instance;
      final role = (await stockage.getUserRole() ?? 'client').toLowerCase();
      if (role != 'client') return;
      final id = await stockage.getUserId() ?? '';
      final email = await stockage.getUserEmail() ?? '';
      if (id.isEmpty) return;
      await stockage.saveUserInfo(role: 'vendor', userId: id, email: email);
    } catch (_) {}
  }
}
