import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  StorageService._();

  SupabaseClient get _client => SupabaseService.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Bucket names
  static const String productImagesBucket = 'product-images';
  static const String shopLogosBucket = 'shop-logos';
  static const String deliveryProofsBucket = 'delivery-proofs';
  static const String chatImagesBucket = 'chat-images';

  // ── Pick image from gallery or camera ──────────────────────────────────────

  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      return null;
    }
  }

  // ── Upload product image ───────────────────────────────────────────────────

  Future<String?> uploadProductImage(XFile imageFile) async {
    try {
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      final ext = imageFile.name.split('.').last.toLowerCase();
      final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      final bytes = await imageFile.readAsBytes();
      await _client.storage
          .from(productImagesBucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
          );

      return _client.storage.from(productImagesBucket).getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  // ── Upload shop logo ───────────────────────────────────────────────────────

  Future<String?> uploadShopLogo(XFile imageFile) async {
    try {
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      final ext = imageFile.name.split('.').last.toLowerCase();
      final fileName =
          '$userId/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final bytes = await imageFile.readAsBytes();
      await _client.storage
          .from(shopLogosBucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
          );

      return _client.storage.from(shopLogosBucket).getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  // ── Upload delivery proof photo ────────────────────────────────────────────

  Future<String?> uploadDeliveryProof(XFile imageFile, String orderId) async {
    try {
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      final ext = imageFile.name.split('.').last.toLowerCase();
      final fileName =
          '$userId/${orderId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final bytes = await imageFile.readAsBytes();
      await _client.storage
          .from(deliveryProofsBucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
          );

      return _client.storage.from(deliveryProofsBucket).getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  // ── Upload bytes directly (for web chat images) ────────────────────────────

  Future<String?> uploadBytes(
    List<int> bytes,
    String fileName,
    String bucket,
  ) async {
    try {
      final userId = _client.auth.currentUser?.id ?? 'anonymous';
      final path = '$userId/$fileName';
      // Use Uint8List.fromList to safely convert List<int> — avoids runtime TypeError on web
      final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            uint8Bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  // ── Delete file ────────────────────────────────────────────────────────────

  Future<void> deleteFile(String bucket, String filePath) async {
    try {
      await _client.storage.from(bucket).remove([filePath]);
    } catch (_) {}
  }
}
