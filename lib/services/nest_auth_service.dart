import 'package:dio/dio.dart';
import 'api_service.dart';
import 'token_storage_service.dart';

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
        'phone': phone.trim(),
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

      // Extraire le rôle principal depuis le tableau roles
      String nestRole = 'client';
      final roles = user['roles'] as List<dynamic>?;
      if (roles != null && roles.isNotEmpty) {
        nestRole =
            ((roles.first as Map)['role'] as String?)?.toLowerCase() ??
            'client';
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

      return NestAuthResult.success(data);
    } on DioException catch (e) {
      return NestAuthResult.failure(_extractError(e));
    } catch (_) {
      return NestAuthResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  // ── Vendor Profile ────────────────────────────────────────────────────────

  Future<NestAuthResult> submitVendorProfile({
    required String shopName,
    required String shopAddress,
    required String activityType,
    required String description,
    required String idDocumentUrl,
    required String selfieUrl,
    required List<String> sampleProductUrls,
  }) async {
    try {
      await _client.post('/api/v1/vendors/apply', data: {
        'shopName': shopName,
        'shopAddress': shopAddress,
        'activityType': activityType,
        'description': description,
        'idDocumentUrl': idDocumentUrl,
        'selfieUrl': selfieUrl,
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
    required String idDocumentUrl,
    required String selfieUrl,
    required String vehiclePhotoUrl,
    required String licensePlate,
  }) async {
    try {
      await _client.post('/api/v1/delivery-agents/apply', data: {
        'vehicleType': vehicleType,
        'availability': availability,
        'ville': ville,
        'quartier': quartier,
        'preciseAddress': preciseAddress,
        'idDocumentUrl': idDocumentUrl,
        'selfieUrl': selfieUrl,
        'vehiclePhotoUrl': vehiclePhotoUrl,
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

  // ── Session ───────────────────────────────────────────────────────────────

  Future<bool> isLoggedIn() => TokenStorageService.instance.hasValidSession();

  Future<String> getUserRole() async {
    final stored = await TokenStorageService.instance.getUserRole();
    return nestRoleToFlutterRoute(stored ?? 'client');
  }

  Future<void> logout() => TokenStorageService.instance.clearAll();

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
