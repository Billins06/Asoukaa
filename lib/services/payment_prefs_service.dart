import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'token_storage_service.dart';

/// Un numéro Mobile Money enregistré par le client dans son profil.
class SavedPaymentMethod {
  /// « MTN » ou « Moov » : mêmes valeurs que celles acceptées par le serveur
  /// pour un paiement (Wave et Orange Money ne sont pas encore pris en charge).
  final String operator;
  final String number;
  final bool isDefault;

  const SavedPaymentMethod({
    required this.operator,
    required this.number,
    this.isDefault = false,
  });

  SavedPaymentMethod copyWith({bool? isDefault}) => SavedPaymentMethod(
        operator: operator,
        number: number,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, dynamic> toJson() => {
        'operator': operator,
        'number': number,
        'isDefault': isDefault,
      };

  static SavedPaymentMethod? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final op = raw['operator']?.toString() ?? '';
    final number = raw['number']?.toString() ?? '';
    if ((op != 'MTN' && op != 'Moov') || number.isEmpty) return null;
    return SavedPaymentMethod(
      operator: op,
      number: number,
      isDefault: raw['isDefault'] == true,
    );
  }
}

/// Numéros de paiement enregistrés (profil) : stockés sur l'appareil, séparément
/// pour chaque compte. Le client en choisit un « par défaut » : il est
/// pré-rempli à l'écran de paiement (et reste modifiable à ce moment-là).
class PaymentPrefsService {
  static PaymentPrefsService? _instance;
  static PaymentPrefsService get instance =>
      _instance ??= PaymentPrefsService._();
  PaymentPrefsService._();

  /// Nombre maximum de numéros enregistrés.
  static const int maxMethods = 4;

  Future<String> _key() async {
    String userId = '';
    try {
      userId = (await TokenStorageService.instance.getUserId()) ?? '';
    } catch (_) {}
    return 'payment_methods_v1_$userId';
  }

  Future<List<SavedPaymentMethod>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key());
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(SavedPaymentMethod.fromJson)
          .whereType<SavedPaymentMethod>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Enregistre la liste en garantissant UN seul numéro par défaut (le premier
  /// si aucun n'est marqué).
  Future<void> save(List<SavedPaymentMethod> methods) async {
    var list = List<SavedPaymentMethod>.from(methods);
    if (list.isNotEmpty && !list.any((m) => m.isDefault)) {
      list[0] = list[0].copyWith(isDefault: true);
    }
    var seen = false;
    list = list.map((m) {
      if (m.isDefault && !seen) {
        seen = true;
        return m;
      }
      return m.isDefault ? m.copyWith(isDefault: false) : m;
    }).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        await _key(),
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<SavedPaymentMethod?> getDefault() async {
    final list = await load();
    for (final m in list) {
      if (m.isDefault) return m;
    }
    return list.isNotEmpty ? list.first : null;
  }
}
