import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './supabase_service.dart';

class GpsTrackingService {
  static GpsTrackingService? _instance;
  static GpsTrackingService get instance =>
      _instance ??= GpsTrackingService._();
  GpsTrackingService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  StreamSubscription<Position>? _positionSubscription;
  String? _activeMissionId;
  String? _activeDelivererId;

  // ── Permission & availability ──────────────────────────────────────────

  Future<bool> checkPermission() async {
    if (kIsWeb) {
      // Web uses browser geolocation
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        return requested != LocationPermission.denied &&
            requested != LocationPermission.deniedForever;
      }
      return permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ── Get current position once ──────────────────────────────────────────

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Start live GPS tracking for a deliverer mission ────────────────────

  Future<void> startTracking({
    required String delivererId,
    required String missionId,
  }) async {
    await stopTracking();

    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    _activeMissionId = missionId;
    _activeDelivererId = delivererId;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // update every 10 metres
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) => _uploadPosition(position), onError: (_) {});
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeMissionId = null;
    _activeDelivererId = null;
  }

  bool get isTracking => _positionSubscription != null;

  // ── Upload position to Supabase ────────────────────────────────────────

  Future<void> _uploadPosition(Position position) async {
    if (_activeDelivererId == null) return;
    try {
      await _client.from('deliverer_positions').insert({
        'deliverer_id': _activeDelivererId,
        'mission_id': _activeMissionId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ── Subscribe to a deliverer's latest position (for buyer/tracking) ────

  RealtimeChannel subscribeToDelivererPosition({
    required String delivererId,
    required void Function(Map<String, dynamic> position) onPosition,
  }) {
    final channel = _client
        .channel('deliverer_position_$delivererId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'deliverer_positions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'deliverer_id',
            value: delivererId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) onPosition(record);
          },
        )
        .subscribe();
    return channel;
  }

  // ── Subscribe to order status changes ─────────────────────────────────

  RealtimeChannel subscribeToOrderStatus({
    required String orderId,
    required void Function(String status) onStatusChange,
  }) {
    final channel = _client
        .channel('order_status_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null) onStatusChange(newStatus);
          },
        )
        .subscribe();
    return channel;
  }

  // ── Submit delivery rating ─────────────────────────────────────────────

  Future<bool> submitDeliveryRating({
    required String orderId,
    required String buyerId,
    String? delivererId,
    required int rating,
    String comment = '',
    String photoUrl = '',
  }) async {
    try {
      await _client.from('delivery_ratings').upsert({
        'order_id': orderId,
        'buyer_id': buyerId,
        if (delivererId != null) 'deliverer_id': delivererId,
        'rating': rating,
        'comment': comment,
        'photo_url': photoUrl,
      }, onConflict: 'order_id,buyer_id');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Check if rating already submitted ─────────────────────────────────

  Future<Map<String, dynamic>?> getDeliveryRating({
    required String orderId,
    required String buyerId,
  }) async {
    try {
      final result = await _client
          .from('delivery_ratings')
          .select()
          .eq('order_id', orderId)
          .eq('buyer_id', buyerId)
          .maybeSingle();
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── Insert notification for order status change ────────────────────────

  Future<void> insertStatusNotification({
    required String userId,
    required String orderNumber,
    required String status,
  }) async {
    final labels = {
      'confirme': (
        'Commande confirmée',
        'Votre commande #$orderNumber a été confirmée.',
      ),
      'en_preparation': (
        'En préparation',
        'Votre commande #$orderNumber est en cours de préparation.',
      ),
      'expedie': (
        'Commande expédiée',
        'Votre commande #$orderNumber a été expédiée.',
      ),
      'en_livraison': (
        'En cours de livraison',
        'Votre commande #$orderNumber est en route vers vous.',
      ),
      'livre': (
        'Commande livrée !',
        'Votre commande #$orderNumber a été livrée avec succès.',
      ),
    };
    final label = labels[status];
    if (label == null) return;
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': label.$1,
        'body': label.$2,
        'notification_type': 'livraison',
        'data': {'order_number': orderNumber, 'status': status},
      });
    } catch (_) {}
  }
}
