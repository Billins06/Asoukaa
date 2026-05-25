import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Classifies the type of error for appropriate user messaging
enum SupabaseErrorType {
  network,
  auth,
  notFound,
  permission,
  conflict,
  serverError,
  timeout,
  unknown,
}

/// Wraps a Supabase operation result with error details
class ServiceResult<T> {
  final T? data;
  final String? errorMessage;
  final SupabaseErrorType? errorType;
  final bool isSuccess;

  const ServiceResult._({
    this.data,
    this.errorMessage,
    this.errorType,
    required this.isSuccess,
  });

  factory ServiceResult.success(T data) =>
      ServiceResult._(data: data, isSuccess: true);

  factory ServiceResult.failure(
    String message, {
    SupabaseErrorType type = SupabaseErrorType.unknown,
  }) =>
      ServiceResult._(errorMessage: message, errorType: type, isSuccess: false);

  bool get isFailure => !isSuccess;
}

/// Central error handler for all Supabase service calls
class ErrorHandler {
  ErrorHandler._();

  // ── Retry configuration ────────────────────────────────────────────────────

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);

  // ── Retry wrapper ──────────────────────────────────────────────────────────

  /// Executes [operation] with automatic retry on transient errors.
  /// Retries up to [maxRetries] times with exponential backoff.
  /// Only retries on network/timeout errors, not on auth/permission errors.
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    Duration delay = _retryDelay,
    bool Function(Object error)? shouldRetry,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        final retryable = shouldRetry?.call(e) ?? _isRetryable(e);
        if (!retryable || attempt >= maxRetries) {
          rethrow;
        }
        // Exponential backoff: 1s, 2s, 4s
        await Future.delayed(delay * (1 << (attempt - 1)));
      }
    }
  }

  /// Returns true if the error is transient and worth retrying.
  /// Uses string-based checks instead of dart:io types for web compatibility.
  static bool _isRetryable(Object error) {
    if (error is TimeoutException) return true;
    if (error is PostgrestException) {
      // Retry on server errors (5xx), not on client errors (4xx)
      final code = int.tryParse(error.code ?? '') ?? 0;
      return code >= 500;
    }
    if (error is AuthException) return false; // Never retry auth errors
    // String-based checks — work on both web and mobile
    final msg = error.toString().toLowerCase();
    return msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused');
  }

  // ── Error classification ───────────────────────────────────────────────────

  static SupabaseErrorType classifyError(Object error) {
    if (error is AuthException) return SupabaseErrorType.auth;
    if (error is TimeoutException) return SupabaseErrorType.timeout;
    if (error is PostgrestException) {
      final code = int.tryParse(error.code ?? '') ?? 0;
      if (code == 404 || error.code == 'PGRST116') {
        return SupabaseErrorType.notFound;
      }
      if (code == 403 || code == 401) return SupabaseErrorType.permission;
      if (code == 409 || error.code == '23505') {
        return SupabaseErrorType.conflict;
      }
      if (code >= 500) return SupabaseErrorType.serverError;
    }
    // String-based network detection — works on web and mobile
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused')) {
      return SupabaseErrorType.network;
    }
    if (msg.contains('timeout')) return SupabaseErrorType.timeout;
    return SupabaseErrorType.unknown;
  }

  static String friendlyMessage(Object error) {
    final type = classifyError(error);
    switch (type) {
      case SupabaseErrorType.network:
        return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
      case SupabaseErrorType.timeout:
        return 'La requête a expiré. Vérifiez votre connexion et réessayez.';
      case SupabaseErrorType.auth:
        if (error is AuthException) {
          return _mapAuthMessage(error.message);
        }
        return 'Session expirée. Veuillez vous reconnecter.';
      case SupabaseErrorType.permission:
        return 'Vous n\'avez pas les droits pour effectuer cette action.';
      case SupabaseErrorType.notFound:
        return 'L\'élément demandé est introuvable.';
      case SupabaseErrorType.conflict:
        return 'Cette entrée existe déjà.';
      case SupabaseErrorType.serverError:
        return 'Erreur serveur. Veuillez réessayer dans quelques instants.';
      case SupabaseErrorType.unknown:
        return 'Une erreur inattendue s\'est produite. Veuillez réessayer.';
    }
  }

  static String _mapAuthMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (lower.contains('email already registered') ||
        lower.contains('already registered')) {
      return 'Cet email est déjà utilisé.';
    }
    if (lower.contains('password should be at least')) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }
    if (lower.contains('invalid email')) {
      return 'Format d\'email invalide.';
    }
    if (lower.contains('rate limit')) {
      return 'Trop de tentatives. Attendez quelques minutes.';
    }
    return 'Erreur d\'authentification: $message';
  }

  // ── User-facing error dialog ───────────────────────────────────────────────

  /// Shows a user-facing error dialog with an optional retry callback.
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String message,
    String title = 'Erreur',
    VoidCallback? onRetry,
    String retryLabel = 'Réessayer',
    String dismissLabel = 'Fermer',
  }) async {
    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
        ),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onRetry();
              },
              child: Text(
                retryLabel,
                style: const TextStyle(
                  color: Color(0xFF1A237E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              dismissLabel,
              style: TextStyle(
                color: onRetry != null
                    ? const Color(0xFF888888)
                    : const Color(0xFF1A237E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows an error dialog derived directly from a caught exception.
  static Future<void> showExceptionDialog(
    BuildContext context,
    Object error, {
    String? title,
    VoidCallback? onRetry,
  }) {
    return showErrorDialog(
      context,
      message: friendlyMessage(error),
      title: title ?? _titleForError(error),
      onRetry: onRetry,
    );
  }

  static String _titleForError(Object error) {
    final type = classifyError(error);
    switch (type) {
      case SupabaseErrorType.network:
        return 'Connexion requise';
      case SupabaseErrorType.timeout:
        return 'Délai dépassé';
      case SupabaseErrorType.auth:
        return 'Authentification';
      case SupabaseErrorType.permission:
        return 'Accès refusé';
      case SupabaseErrorType.serverError:
        return 'Erreur serveur';
      default:
        return 'Erreur';
    }
  }
}
