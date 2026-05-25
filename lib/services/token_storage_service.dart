import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
    ]);
  }

  Future<void> saveUserInfo({
    required String role,
    required String userId,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: _keyUserRole, value: role),
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyUserEmail, value: email),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  Future<String?> getUserRole() => _storage.read(key: _keyUserRole);
  Future<String?> getUserId() => _storage.read(key: _keyUserId);
  Future<String?> getUserEmail() => _storage.read(key: _keyUserEmail);

  Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearAll() => _storage.deleteAll();
}
