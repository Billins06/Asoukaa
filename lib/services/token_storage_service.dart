import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage des tokens JWT.
/// - Web      : SharedPreferences (localStorage) — flutter_secure_storage v9.x
///              lève OperationError via window.crypto.subtle sur certains browsers.
/// - Mobile   : flutter_secure_storage (stockage chiffré natif).
class TokenStorageService {
  static TokenStorageService? _instance;
  static TokenStorageService get instance =>
      _instance ??= TokenStorageService._();
  TokenStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyAccessToken = 'nest_access_token';
  static const _keyRefreshToken = 'nest_refresh_token';
  static const _keyUserRole = 'nest_user_role';
  static const _keyUserId = 'nest_user_id';
  static const _keyUserEmail = 'nest_user_email';

  static const _webKeys = [
    _keyAccessToken,
    _keyRefreshToken,
    _keyUserRole,
    _keyUserId,
    _keyUserEmail,
  ];

  // ── Écriture ────────────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _write(_keyAccessToken, accessToken),
      _write(_keyRefreshToken, refreshToken),
    ]);
  }

  Future<void> saveUserInfo({
    required String role,
    required String userId,
    required String email,
  }) async {
    await Future.wait([
      _write(_keyUserRole, role),
      _write(_keyUserId, userId),
      _write(_keyUserEmail, email),
    ]);
  }

  // ── Lecture ─────────────────────────────────────────────────────────────────

  Future<String?> getAccessToken() => _read(_keyAccessToken);
  Future<String?> getRefreshToken() => _read(_keyRefreshToken);
  Future<String?> getUserRole() => _read(_keyUserRole);
  Future<String?> getUserId() => _read(_keyUserId);
  Future<String?> getUserEmail() => _read(_keyUserEmail);

  Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Suppression ─────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait(_webKeys.map((k) => prefs.remove(k)));
    } else {
      await _storage.deleteAll();
    }
  }

  // ── Implémentation interne ──────────────────────────────────────────────────

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      return _storage.read(key: key);
    }
  }
}
