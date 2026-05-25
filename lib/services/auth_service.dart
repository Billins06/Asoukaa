import 'package:supabase_flutter/supabase_flutter.dart';

import './error_handler.dart';
import './supabase_service.dart';

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ── Current user ──────────────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Sign Up ───────────────────────────────────────────────────────────────

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String phone = '',
    String? shopName,
    String? shopCategory,
    String? shopDescription,
  }) async {
    try {
      final response = await ErrorHandler.withRetry(
        () => _client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': fullName, 'role': role, 'phone': phone},
        ),
        // Auth errors should not be retried — only network issues
        shouldRetry: (e) =>
            e is! AuthException &&
            ErrorHandler.classifyError(e) == SupabaseErrorType.network,
      );

      if (response.user == null) {
        return AuthResult.failure(
          'Inscription échouée. Veuillez réessayer.',
          type: SupabaseErrorType.unknown,
        );
      }

      // If seller, create shop after profile is created
      if (role == 'vendeur' && shopName != null && shopName.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          await ErrorHandler.withRetry(
            () => _client.from('shops').insert({
              'owner_id': response.user!.id,
              'name': shopName,
              'description': shopDescription ?? '',
              'category': shopCategory ?? 'Autres',
            }),
          );
        } catch (_) {
          // Shop creation failure is non-blocking
        }
      }

      return AuthResult.success(response.user!);
    } on AuthException catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: SupabaseErrorType.auth,
      );
    } catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await ErrorHandler.withRetry(
        () => _client.auth.signInWithPassword(email: email, password: password),
        shouldRetry: (e) =>
            e is! AuthException &&
            ErrorHandler.classifyError(e) == SupabaseErrorType.network,
      );

      if (response.user == null) {
        return AuthResult.failure(
          'Connexion échouée. Vérifiez vos identifiants.',
          type: SupabaseErrorType.auth,
        );
      }

      return AuthResult.success(response.user!);
    } on AuthException catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: SupabaseErrorType.auth,
      );
    } catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }

  // ── Forgot Password ───────────────────────────────────────────────────────

  Future<AuthResult> forgotPassword(String email) async {
    try {
      await ErrorHandler.withRetry(
        () => _client.auth.resetPasswordForEmail(
          email,
          redirectTo: 'https://asoukaa3389.builtwithrocket.new/reset-password',
        ),
        shouldRetry: (e) =>
            e is! AuthException &&
            ErrorHandler.classifyError(e) == SupabaseErrorType.network,
      );
      return AuthResult.success(
        _client.auth.currentUser ??
            User(
              id: '',
              appMetadata: {},
              userMetadata: {},
              aud: '',
              createdAt: DateTime.now().toIso8601String(),
            ),
      );
    } on AuthException catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: SupabaseErrorType.auth,
      );
    } catch (e) {
      return AuthResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }

  // ── Get user profile ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = currentUser;
      if (user == null) return null;

      final response = await ErrorHandler.withRetry(
        () => _client
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle(),
      );

      return response;
    } catch (_) {
      return null;
    }
  }

  // ── Get user role ─────────────────────────────────────────────────────────

  String getUserRole() {
    final user = currentUser;
    if (user == null) return 'acheteur';
    return user.userMetadata?['role'] as String? ?? 'acheteur';
  }

  // ── Update profile ────────────────────────────────────────────────────────

  Future<ServiceResult<bool>> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        return ServiceResult.failure(
          'Utilisateur non connecté.',
          type: SupabaseErrorType.auth,
        );
      }

      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      if (updates.isEmpty) return ServiceResult.success(true);

      await ErrorHandler.withRetry(
        () => _client.from('user_profiles').update(updates).eq('id', user.id),
      );

      return ServiceResult.success(true);
    } catch (e) {
      return ServiceResult.failure(
        ErrorHandler.friendlyMessage(e),
        type: ErrorHandler.classifyError(e),
      );
    }
  }
}

// ── Result type ───────────────────────────────────────────────────────────────

class AuthResult {
  final User? user;
  final String? error;
  final SupabaseErrorType? errorType;
  final bool success;

  AuthResult._({this.user, this.error, this.errorType, required this.success});

  factory AuthResult.success(User user) =>
      AuthResult._(user: user, success: true);

  factory AuthResult.failure(
    String error, {
    SupabaseErrorType type = SupabaseErrorType.unknown,
  }) => AuthResult._(error: error, errorType: type, success: false);
}
