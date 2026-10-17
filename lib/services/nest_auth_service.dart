import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'api_service.dart';
import 'deliverer_availability.dart';
import 'notification_service.dart';
import 'presence_service.dart';
import 'token_storage_service.dart';
import 'wishlist_service.dart';
import '../utils/telephone.dart';

/// Interrupteur de la connexion administrateur DE TEST.
///
/// Pourquoi : le compte admin du site web vit dans la table des
/// administrateurs, alors que l'application se connecte via la table des
/// utilisateurs. Pour pouvoir seulement VOIR l'écran admin pendant les tests,
/// on autorise un repli vers /auth/admin/login, mais uniquement :
///  - en debug (`flutter run`), ou
///  - dans un APK compilé exprès avec
///    `--dart-define=ALLOW_ADMIN_LOGIN=true`.
/// Dans un APK de production normal, les deux valeurs sont fausses et ce
/// chemin n'est jamais exécuté.
const bool kAllowAdminLogin =
    bool.fromEnvironment('ALLOW_ADMIN_LOGIN', defaultValue: false);

/// Vrai seulement en version de test (voir [kAllowAdminLogin]).
const bool kAdminLoginActif = kDebugMode || kAllowAdminLogin;

enum EtatSessionPerdue { visiteur, definitive, temporaire }

class NestAuthResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;

  NestAuthResult._({required this.success, this.error, this.data});

  factory NestAuthResult.success([Map<String, dynamic>? data]) =>
      NestAuthResult._(success: true, data: data);

  factory NestAuthResult.failure(String error) =>
      NestAuthResult._(success: false, error: error);
}

class NestAuthService {
  static NestAuthService? _instance;
  static NestAuthService get instance => _instance ??= NestAuthService._();
  NestAuthService._();

  Dio get _client => ApiService.instance.client;

  // ── Mapping : rôle NestJS → route Flutter ────────────────────────────────

  static String nestRoleToFlutterRoute(String nestRole) {
    switch (nestRole.toLowerCase()) {
      case 'vendor':
        return 'vendeur';
      case 'delivery_agent':
        return 'livreur';
      case 'admin':
      case 'superadmin':
        return 'admin';
      default:
        return 'acheteur';
    }
  }

  // ── Register ──────────────────────────────────────────────────────────────
  // Tous les comptes démarrent en CLIENT — le rôle vendeur/livreur
  // est accordé par l'admin après validation des documents (Phase 2).

  Future<NestAuthResult> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final parts = fullName.trim().split(RegExp(r'\s+'));
      final prenom = parts.first;
      final name =
          parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;

      await _client.post('/api/v1/auth/register', data: {
        'prenom': prenom,
        'name': name,
        'email': email.trim().toLowerCase(),
        'phone': normaliserTelephone(phone),
        'password': password,
      });

      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  Future<NestAuthResult> verifyOtp({
    required String email,
    required String code,
  }) async {
    try {
      await _client.post('/api/v1/auth/verify-otp', data: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'type': 'email_verification',
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────

  Future<NestAuthResult> resendOtp(String email) async {
    try {
      await _client.post('/api/v1/auth/resend-otp', data: {
        'email': email.trim().toLowerCase(),
        'type': 'email_verification',
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors du renvoi.');
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<NestAuthResult> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _client.post('/api/v1/auth/login', data: {
        'identifier': identifier.trim(),
        'password': password,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;
      final user = Map<String, dynamic>.from(data['user'] as Map);

      // Extraire le rôle principal depuis le tableau roles.
      // IMPORTANT : ne pas prendre roles.first — chaque compte a un rôle
      // 'client' cree a l'inscription PUIS un rôle 'vendor'/'delivery_agent'
      // ajoute plus tard (a l'approbation). L'ordre renvoye par la base n'est
      // pas garanti, donc on priorise le rôle metier sur le rôle client de base.
      String nestRole = 'client';
      final roles = user['roles'] as List<dynamic>?;
      if (roles != null && roles.isNotEmpty) {
        final roleValues = roles
            .map((r) => ((r as Map)['role'] as String?)?.toLowerCase())
            .whereType<String>()
            .toSet();
        const rolePriority = [
          'admin',
          'superadmin',
          'vendor',
          'delivery_agent',
          'client',
        ];
        nestRole = rolePriority.firstWhere(
          roleValues.contains,
          orElse: () => 'client',
        );
      }

      await Future.wait([
        TokenStorageService.instance.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        ),
        TokenStorageService.instance.saveUserInfo(
          role: nestRole,
          userId: user['id'] as String? ?? '',
          email: user['email'] as String? ?? '',
        ),
      ]);

      // Présence « En ligne » : premier ping tout de suite pour ce compte.
      PresenceService.instance.pingNow();

      // Nouvelle session : on oublie les échecs de renouvellement passés et on
      // démarre le sondage des notifications (avant, il ne démarrait qu'au
      // lancement à froid de l'appli).
      ApiService.reinitialiserRafraichissement();
      NotificationService.instance.subscribeToUserNotifications();

      return NestAuthResult.success(data);
    } on DioException catch (e) {
      // Version de test seulement : identifiants inconnus côté utilisateurs
      // (401) -> on essaie la table des administrateurs. Un 403 (compte
      // bloqué / e-mail non vérifié) prouve que le compte existe côté
      // utilisateurs : on ne tente pas l'admin dans ce cas.
      if (kAdminLoginActif && e.response?.statusCode == 401) {
        final admin = await _tenterConnexionAdminTest(identifier, password);
        if (admin != null) return admin;
      }
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  /// Connexion admin de test. Retourne null si elle échoue (le message
  /// d'erreur affiché reste alors celui de la connexion normale).
  /// La réponse serveur est { accessToken, admin: { id, email, role, ... } } :
  /// pas de refreshToken, pas de tableau `roles`.
  Future<NestAuthResult?> _tenterConnexionAdminTest(
    String identifier,
    String password,
  ) async {
    // Double verrou : même appelée par erreur, rien ne part en production.
    if (!kAdminLoginActif) return null;
    try {
      final response = await _client.post('/api/v1/auth/admin/login', data: {
        'identifier': identifier.trim(),
        'password': password,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['accessToken'] as String;
      final admin = Map<String, dynamic>.from(data['admin'] as Map);

      final roleAdmin = (admin['role'] as String? ?? 'admin').toLowerCase();
      final nestRole = roleAdmin == 'superadmin' ? 'superadmin' : 'admin';

      await Future.wait([
        // Refresh token vide : le serveur n'en fournit pas pour les admins
        // et l'application ne s'en sert nulle part.
        TokenStorageService.instance.saveTokens(
          accessToken: accessToken,
          refreshToken: '',
        ),
        TokenStorageService.instance.saveUserInfo(
          role: nestRole,
          userId: admin['id']?.toString() ?? '',
          email: admin['email'] as String? ?? '',
        ),
      ]);

      // Pas de PresenceService.pingNow() : le ping de présence concerne les
      // utilisateurs, pas la table des administrateurs.
      return NestAuthResult.success({...data, 'user': admin});
    } catch (_) {
      return null;
    }
  }

  // ── Vendor Profile ────────────────────────────────────────────────────────

  Future<NestAuthResult> submitVendorProfile({
    required String shopName,
    required String shopAddress,
    // Catégories de la plateforme (1 a 5) ; activityType n'est plus
    // envoye que si aucune categorie n'est fournie (repli ancien format).
    List<String>? categoryIds,
    String? activityType,
    required String description,
    String? idDocumentUrl,
    String? selfieUrl,
    List<String>? sampleProductUrls,
  }) async {
    try {
      final hasCategories = categoryIds != null && categoryIds.isNotEmpty;
      await _client.post('/api/v1/vendors/apply', data: {
        'shopName': shopName,
        'shopAddress': shopAddress,
        if (hasCategories) 'categoryIds': categoryIds,
        if (!hasCategories && (activityType ?? '').isNotEmpty)
          'activityType': activityType,
        'description': description,
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        if (selfieUrl != null) 'selfieUrl': selfieUrl,
        if (sampleProductUrls != null && sampleProductUrls.isNotEmpty)
          'sampleProductUrls': sampleProductUrls,
        'termsAccepted': true,
        'fraudPenaltiesAccepted': true,
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de la soumission du profil vendeur.');
    }
  }

  // ── Agent Profile ──────────────────────────────────────────────────────────

  Future<NestAuthResult> submitAgentProfile({
    required String vehicleType,
    required String availability,
    required String ville,
    required String quartier,
    required String preciseAddress,
    String? idDocumentUrl,
    String? selfieUrl,
    String? vehiclePhotoUrl,
    required String licensePlate,
  }) async {
    try {
      await _client.post('/api/v1/delivery-agents/apply', data: {
        'vehicleType': vehicleType,
        'availability': availability,
        'ville': ville,
        'quartier': quartier,
        'preciseAddress': preciseAddress,
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        if (selfieUrl != null) 'selfieUrl': selfieUrl,
        if (vehiclePhotoUrl != null) 'vehiclePhotoUrl': vehiclePhotoUrl,
        'licensePlate': licensePlate,
        'termsAccepted': true,
        'fraudPenaltiesAccepted': true,
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de la soumission du profil livreur.');
    }
  }

  // ── Compléter mes documents (vendeur, dossier en attente) ──────────────────

  Future<NestAuthResult> completeVendorDocuments({
    String? idDocumentUrl,
    String? selfieUrl,
    List<String>? sampleProductUrls,
  }) async {
    try {
      await _client.patch('/api/v1/vendors/me/documents', data: {
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        if (selfieUrl != null) 'selfieUrl': selfieUrl,
        if (sampleProductUrls != null && sampleProductUrls.isNotEmpty)
          'sampleProductUrls': sampleProductUrls,
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de la mise à jour des documents.');
    }
  }

  // ── Compléter mes documents (livreur, dossier en attente) ──────────────────

  Future<NestAuthResult> completeAgentDocuments({
    String? idDocumentUrl,
    String? selfieUrl,
    String? vehiclePhotoUrl,
  }) async {
    try {
      await _client.patch('/api/v1/delivery-agents/me/documents', data: {
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        if (selfieUrl != null) 'selfieUrl': selfieUrl,
        if (vehiclePhotoUrl != null) 'vehiclePhotoUrl': vehiclePhotoUrl,
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de la mise à jour des documents.');
    }
  }

  // ── Forgot Password ───────────────────────────────────────────────────────

  Future<NestAuthResult> forgotPassword(String email) async {
    try {
      await _client.post('/api/v1/auth/forgot-password', data: {
        'email': email.trim().toLowerCase(),
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de l\'envoi.');
    }
  }

  // Avant : rien n'appelait jamais POST /auth/reset-password — le code OTP
  // envoyé par forgotPassword() n'avait donc aucun endroit où être saisi.
  // Voir ResetPasswordScreen, qui appelle cette méthode.
  Future<NestAuthResult> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _client.post('/api/v1/auth/reset-password', data: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors de la réinitialisation.');
    }
  }

  // Renvoie un code de réinitialisation de mot de passe (type différent de
  // resendOtp() ci-dessus, qui est pour la vérification d'email).
  Future<NestAuthResult> resendPasswordResetOtp(String email) async {
    try {
      await _client.post('/api/v1/auth/resend-otp', data: {
        'email': email.trim().toLowerCase(),
        'type': 'réinitialisation du mot de passe',
      });
      return NestAuthResult.success();
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur lors du renvoi.');
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  Future<bool> isLoggedIn() async {
    if (await TokenStorageService.instance.hasValidSession()) return true;
    // Jeton d'accès périmé : si un jeton de rafraîchissement existe, on tente
    // de renouveler la session au lieu de renvoyer l'utilisateur à la
    // connexion (une seule tentative partagée, voir ApiService).
    final refresh = await TokenStorageService.instance.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    final r = await ApiService.rafraichirSession();
    return r == ResultatRafraichissement.reussi;
  }

  /// À appeler par un écran connecté quand [isLoggedIn] vient de répondre
  /// « non ». Distingue :
  ///  - [EtatSessionPerdue.visiteur] : personne n'a jamais été connecté ici ;
  ///  - [EtatSessionPerdue.definitive] : la session est perdue (jeton refusé
  ///    ou sans possibilité de renouvellement) -> déconnexion lancée ici ;
  ///  - [EtatSessionPerdue.temporaire] : renouvellement impossible pour
  ///    l'instant (réseau...) -> l'écran doit proposer « Réessayer ».
  Future<EtatSessionPerdue> gererSessionPerdue() async {
    final acces = await TokenStorageService.instance.getAccessToken();
    if (acces == null || acces.isEmpty) return EtatSessionPerdue.visiteur;
    final refresh = await TokenStorageService.instance.getRefreshToken();
    final sansRefresh = refresh == null || refresh.isEmpty;
    if (sansRefresh ||
        ApiService.derniereIssueRafraichissement ==
            ResultatRafraichissement.refuse) {
      ApiService.sessionExpiree();
      return EtatSessionPerdue.definitive;
    }
    return EtatSessionPerdue.temporaire;
  }

  Future<String> getUserRole() async {
    final stored = await TokenStorageService.instance.getUserRole();
    return nestRoleToFlutterRoute(stored ?? 'client');
  }

  Future<void> logout() {
    NotificationService.instance.unsubscribe();
    // Ne pas montrer au compte suivant l'état du compte précédent.
    DelivererAvailability.instance.reset();
    WishlistService.instance.reset();
    return TokenStorageService.instance.clearAll();
  }

  // ── Extraction d'erreur Dio ───────────────────────────────────────────────

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Délai dépassé. Vérifiez votre connexion internet.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Impossible de joindre le serveur. Vérifiez que le serveur est démarré et que votre téléphone est bien connecté.';
      default:
        final status = e.response?.statusCode;
        if (status == 401) return 'Identifiants incorrects.';
        if (status == 409) return 'Email ou téléphone déjà utilisé.';
        if (status == 400) return 'Données invalides. Vérifiez vos informations.';
        if (status == 403) return 'Compte non autorisé.';
        return 'Erreur serveur. Veuillez réessayer.';
    }
  }
}
