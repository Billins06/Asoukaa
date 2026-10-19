import 'package:dio/dio.dart';

import 'api_service.dart';

/// Appels API des « courses express » (livraisons indépendantes).
class ExpressDeliveryService {
  static ExpressDeliveryService? _instance;
  static ExpressDeliveryService get instance =>
      _instance ??= ExpressDeliveryService._();
  ExpressDeliveryService._();

  static const String _base = '/api/v1/delivery/independent';

  Dio get _dio => ApiService.instance.client;

  /// Message lisible tiré d'une erreur serveur, sinon [fallback].
  static String errorMessage(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    }
    return fallback;
  }

  static List<Map<String, dynamic>> _asList(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) as List : []);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── Client ──────────────────────────────────────────────

  Future<void> create({
    required String pickupAddress,
    required String adresseLivraison,
    required String packageDescription,
    required String delai,
    required int proposedPrice,
    String? notes,
  }) async {
    await _dio.post(_base, data: {
      'pickupAddress': pickupAddress,
      'adresseLivraison': adresseLivraison,
      'packageDescription': packageDescription,
      'delai': delai,
      'proposedPrice': proposedPrice,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> myRequests() async {
    final r = await _dio.get('$_base/requests');
    return _asList(r.data);
  }

  Future<void> respondToCounter(String id, bool accept) async {
    await _dio.patch('$_base/$id/respond', data: {'accept': accept});
  }

  Future<void> cancel(String id) async {
    await _dio.patch('$_base/$id/cancel');
  }

  Future<void> pay(String id,
      {required String operator, required String phoneNumber}) async {
    await _dio.post('$_base/$id/pay',
        data: {'operator': operator, 'phoneNumber': phoneNumber});
  }

  /// `paymentStatus` : null, « en attente », « success » ou « échoué ».
  Future<Map<String, dynamic>> paymentStatus(String id) async {
    final r = await _dio.get('$_base/$id/payment-status');
    return r.data is Map ? Map<String, dynamic>.from(r.data) : {};
  }

  // ── Livreur ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> available() async {
    final r = await _dio.get('$_base/available');
    return _asList(r.data);
  }

  Future<List<Map<String, dynamic>>> mine() async {
    final r = await _dio.get('$_base/mine');
    return _asList(r.data);
  }

  Future<void> accept(String id) async {
    await _dio.patch('$_base/$id/accept');
  }

  Future<void> counter(String id, int price) async {
    await _dio.patch('$_base/$id/counter', data: {'price': price});
  }

  Future<void> updateStatus(String id, String status) async {
    await _dio.patch('$_base/$id/status', data: {'status': status});
  }
}

/// Libellés partagés (client + livreur).
const Map<String, String> kDelaiLabels = {
  'normal': 'Normal · dans la journée',
  'urgent': 'Urgent · 2 à 3 h',
  'express': 'Express · moins d\'1 h',
};

String formatFcfa(num? n) {
  if (n == null) return '—';
  final s = n.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '$buf F';
}

num? toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}
