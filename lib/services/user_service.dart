import 'package:dio/dio.dart';
import 'api_service.dart';

// ── Modèles ───────────────────────────────────────────────────────────────────

class UserProfile {
  final String id;
  final String email;
  final String phone;
  final String prenom;
  final String name;
  final String? avatarUrl;
  final bool isVerified;
  final bool isActive;
  final List<String> roles;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.phone,
    required this.prenom,
    required this.name,
    this.avatarUrl,
    required this.isVerified,
    required this.isActive,
    required this.roles,
    required this.createdAt,
  });

  String get fullName => '$prenom $name'.trim();

  String get initials {
    final parts = fullName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rolesList = (json['roles'] as List<dynamic>? ?? [])
        .map((r) => (r as Map)['role'] as String? ?? '')
        .where((r) => r.isNotEmpty)
        .toList();

    return UserProfile(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      roles: rolesList,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class UserAddress {
  final String id;
  final String label;
  final String nomDestinataire;
  final String phoneDestinataire;
  final String quartier;
  final String ville;
  final String? country;
  final bool isDefault;

  const UserAddress({
    required this.id,
    required this.label,
    required this.nomDestinataire,
    required this.phoneDestinataire,
    required this.quartier,
    required this.ville,
    this.country,
    required this.isDefault,
  });

  factory UserAddress.fromJson(Map<String, dynamic> json) => UserAddress(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        nomDestinataire: json['nom_destinataire'] as String? ?? '',
        phoneDestinataire: json['phone_destinataire'] as String? ?? '',
        quartier: json['quartier'] as String? ?? '',
        ville: json['ville'] as String? ?? '',
        country: json['country'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  String get displayLine => '$quartier, $ville${country != null ? ', $country' : ''}';
}

// ── Résultat générique ────────────────────────────────────────────────────────

class UserResult<T> {
  final bool success;
  final String? error;
  final T? data;

  const UserResult._({required this.success, this.error, this.data});

  factory UserResult.success([T? data]) =>
      UserResult._(success: true, data: data);

  factory UserResult.failure(String error) =>
      UserResult._(success: false, error: error);
}

// ── Service ───────────────────────────────────────────────────────────────────

class UserService {
  static UserService? _instance;
  static UserService get instance => _instance ??= UserService._();
  UserService._();

  Dio get _client => ApiService.instance.client;

  // ── Profil ─────────────────────────────────────────────────────────────────

  Future<UserResult<UserProfile>> getMyProfile() async {
    try {
      final response = await _client.get('/api/v1/users/me');
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      return UserResult.success(profile);
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors du chargement du profil.');
    }
  }

  Future<UserResult<UserProfile>> updateProfile({
    String? prenom,
    String? name,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (prenom != null) body['prenom'] = prenom.trim();
      if (name != null) body['name'] = name.trim();
      if (phone != null) body['phone'] = phone.trim();
      if (avatarUrl != null) body['avatarUrl'] = avatarUrl;

      final response = await _client.put('/api/v1/users/me', data: body);
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      return UserResult.success(profile);
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors de la mise à jour du profil.');
    }
  }

  Future<UserResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _client.patch('/api/v1/users/me/password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      });
      return UserResult.success();
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors du changement de mot de passe.');
    }
  }

  // ── Adresses ───────────────────────────────────────────────────────────────

  Future<UserResult<List<UserAddress>>> getAddresses() async {
    try {
      final response = await _client.get('/api/v1/users/me/addresses');
      final list = (response.data as List<dynamic>)
          .map((e) => UserAddress.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return UserResult.success(list);
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors du chargement des adresses.');
    }
  }

  Future<UserResult<UserAddress>> createAddress({
    required String label,
    required String nomDestinataire,
    required String phoneDestinataire,
    required String quartier,
    required String ville,
    String? country,
    bool isDefault = false,
  }) async {
    try {
      final response = await _client.post('/api/v1/users/me/addresses', data: {
        'label': label.trim(),
        'nom_destinataire': nomDestinataire.trim(),
        'phone_destinataire': phoneDestinataire.trim(),
        'quartier': quartier.trim(),
        'ville': ville.trim(),
        if (country != null && country.isNotEmpty) 'country': country.trim(),
        'isDefault': isDefault,
      });
      final address = UserAddress.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      return UserResult.success(address);
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors de la création de l\'adresse.');
    }
  }

  Future<UserResult<UserAddress>> updateAddress(
    String id, {
    String? label,
    String? nomDestinataire,
    String? phoneDestinataire,
    String? quartier,
    String? ville,
    String? country,
    bool? isDefault,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (label != null) body['label'] = label.trim();
      if (nomDestinataire != null) body['nom_destinataire'] = nomDestinataire.trim();
      if (phoneDestinataire != null) body['phone_destinataire'] = phoneDestinataire.trim();
      if (quartier != null) body['quartier'] = quartier.trim();
      if (ville != null) body['ville'] = ville.trim();
      if (country != null) body['country'] = country.trim();
      if (isDefault != null) body['isDefault'] = isDefault;

      final response = await _client.put('/api/v1/users/me/addresses/$id', data: body);
      final address = UserAddress.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      return UserResult.success(address);
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors de la modification de l\'adresse.');
    }
  }

  Future<UserResult<void>> deleteAddress(String id) async {
    try {
      await _client.delete('/api/v1/users/me/addresses/$id');
      return UserResult.success();
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors de la suppression de l\'adresse.');
    }
  }

  Future<UserResult<void>> setDefaultAddress(String id) async {
    try {
      await _client.patch('/api/v1/users/me/addresses/$id/default');
      return UserResult.success();
    } on DioException catch (e) {
      return UserResult.failure(_extractError(e));
    } catch (_) {
      return UserResult.failure('Erreur lors de la mise à jour de l\'adresse par défaut.');
    }
  }

  // ── Extraction d'erreur ────────────────────────────────────────────────────

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
        return 'Délai dépassé. Vérifiez votre connexion.';
      case DioExceptionType.connectionError:
        return 'Impossible de joindre le serveur.';
      default:
        final status = e.response?.statusCode;
        if (status == 401) return 'Session expirée. Reconnectez-vous.';
        if (status == 400) return 'Données invalides.';
        if (status == 409) return 'Ce téléphone est déjà utilisé.';
        return 'Erreur serveur. Veuillez réessayer.';
    }
  }
}
