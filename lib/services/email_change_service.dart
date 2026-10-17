import 'package:dio/dio.dart';

import 'api_service.dart';
import 'token_storage_service.dart';

/// Résultat simple d'une étape du changement d'e-mail.
class EmailChangeResult {
  final bool success;
  final String? error;
  final String? message;
  final int? expiresInSeconds;
  final String? email;

  const EmailChangeResult._({
    required this.success,
    this.error,
    this.message,
    this.expiresInSeconds,
    this.email,
  });

  factory EmailChangeResult.success({
    String? message,
    int? expiresInSeconds,
    String? email,
  }) =>
      EmailChangeResult._(
        success: true,
        message: message,
        expiresInSeconds: expiresInSeconds,
        email: email,
      );

  factory EmailChangeResult.failure(String error) =>
      EmailChangeResult._(success: false, error: error);
}

/// Changement d'adresse e-mail en 3 étapes (demande, renvoi, confirmation).
///
/// Contrat API :
/// - POST /api/v1/users/me/email/request  {newEmail, currentPassword}
/// - POST /api/v1/users/me/email/resend   (sans corps)
/// - POST /api/v1/users/me/email/confirm  {code}
class EmailChangeService {
  static EmailChangeService? _instance;
  static EmailChangeService get instance =>
      _instance ??= EmailChangeService._();
  EmailChangeService._();

  Dio get _client => ApiService.instance.client;

  static final RegExp _emailRegex =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// Contrôle local du format avant tout envoi.
  static bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

  Future<EmailChangeResult> requestChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    try {
      final response = await _client.post('/api/v1/users/me/email/request', data: {
        'newEmail': newEmail.trim().toLowerCase(),
        'currentPassword': currentPassword,
      });
      return _lireSucces(response.data);
    } on DioException catch (e) {
      return EmailChangeResult.failure(_extractError(e));
    } catch (_) {
      return EmailChangeResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  Future<EmailChangeResult> resendCode() async {
    try {
      final response = await _client.post('/api/v1/users/me/email/resend');
      return _lireSucces(response.data);
    } on DioException catch (e) {
      return EmailChangeResult.failure(_extractError(e));
    } catch (_) {
      return EmailChangeResult.failure('Erreur lors du renvoi du code.');
    }
  }

  Future<EmailChangeResult> confirm(String code) async {
    try {
      final response = await _client.post('/api/v1/users/me/email/confirm', data: {
        'code': code.trim(),
      });
      final result = _lireSucces(response.data);
      final email = result.email;
      if (email != null && email.isNotEmpty) {
        await saveEmailLocally(email);
      }
      return result;
    } on DioException catch (e) {
      return EmailChangeResult.failure(_extractError(e));
    } catch (_) {
      return EmailChangeResult.failure('Erreur inattendue. Veuillez réessayer.');
    }
  }

  /// Met à jour l'e-mail mémorisé sur l'appareil (le rôle et l'id restent
  /// inchangés).
  Future<void> saveEmailLocally(String email) async {
    try {
      final stockage = TokenStorageService.instance;
      final role = await stockage.getUserRole();
      final id = await stockage.getUserId();
      if (role == null || id == null || id.isEmpty) return;
      await stockage.saveUserInfo(role: role, userId: id, email: email);
    } catch (_) {}
  }

  EmailChangeResult _lireSucces(dynamic data) {
    String? message;
    int? expires;
    String? email;
    if (data is Map) {
      final m = data['message'];
      if (m is String) message = m;
      if (m is List && m.isNotEmpty) message = m.first.toString();
      final e = data['expiresInSeconds'];
      if (e is int) expires = e;
      if (e is num) expires = e.toInt();
      final mail = data['email'];
      if (mail is String) email = mail;
    }
    return EmailChangeResult.success(
      message: message,
      expiresInSeconds: expires,
      email: email,
    );
  }

  String _extractError(DioException e) {
    // 429 : texte français fixe (le serveur peut renvoyer un message technique
    // ou un compte à rebours déjà périmé côté appli).
    if (e.response?.statusCode == 429) {
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
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
        return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
      default:
        final status = e.response?.statusCode;
        if (status == 400) return 'Données invalides. Vérifiez vos informations.';
        if (status == 409) return 'Cette adresse e-mail est déjà utilisée.';
        if (status == 429) {
          return 'Trop de demandes. Réessayez dans quelques instants.';
        }
        return 'Erreur serveur. Veuillez réessayer.';
    }
  }
}
