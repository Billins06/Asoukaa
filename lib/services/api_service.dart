import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'token_storage_service.dart';

class ApiService {
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  ApiService._();

  // NestJS backend écoute sur le port 3001.
  // Pour tester sur appareil réel (USB) : adb reverse tcp:3001 tcp:3001
  // Pour IP personnalisée : flutter run --dart-define=API_BASE_URL=http://TON_IP:3001
  static String get _baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    // 127.0.0.1 plutôt que 'localhost' : sur certains appareils Android réels,
    // la résolution DNS du nom 'localhost' échoue de façon intermittente
    // (SocketException: Failed host lookup). L'IP littérale ne nécessite
    // aucune résolution et fonctionne de manière fiable avec adb reverse.
    return 'http://127.0.0.1:3001';
  }

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  )..interceptors.add(_AuthInterceptor());

  Dio get client => _dio;
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      debugPrint('[API] ${options.method} ${options.path} — token: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
    } else {
      debugPrint('[API] ${options.method} ${options.path} — PAS DE TOKEN');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[API] Erreur type=${err.type.name} '
      'status=${err.response?.statusCode} '
      'path=${err.requestOptions.path} '
      'msg=${err.message} '
      'error=${err.error}',
    );
    handler.next(err);
  }
}
