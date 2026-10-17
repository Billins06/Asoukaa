// Affichage du prix sur les cartes produit : fourchette
// « meilleur palier dégressif – prix normal ».
//
// Objectif commercial : le client doit voir dès la carte (et pas seulement
// sur la fiche produit) que le prix baisse quand il achète en quantité,
// par exemple « 25 – 39 FCFA ».
//
// Règle métier (identique à resolveTierUnitPrice côté backend,
// src/common/utils/tier-pricing.util.ts) : un palier n'est JAMAIS plus cher
// que le prix de base. Un palier mal saisi est donc plafonné au prix normal.
//
// ⚠️ Les prix arrivent souvent en CHAÎNE de caractères depuis Postgres
// (colonnes `decimal` sérialisées en texte par TypeORM, ex. "4.50") : tout
// passe donc par double.tryParse, jamais par un cast direct `as num`.

/// Clés sous lesquelles les paliers dégressifs peuvent arriver selon
/// l'endpoint ou l'écran (nommages déjà observés dans le projet).
const List<String> kTierPriceKeys = <String>[
  'tierPrices',
  'price_tiers',
  'priceTiers',
];

/// Clés sous lesquelles le prix normal du produit peut arriver.
const List<String> kBasePriceKeys = <String>[
  'basePrice',
  'price',
  'base_price',
];

/// Parse tolérant : accepte un num, une chaîne ("4.50") ou null.
/// Retourne null si la valeur n'est pas un prix exploitable (<= 0).
double? parsePriceValue(dynamic value) {
  final parsed = double.tryParse('${value ?? ''}');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// Prix normal du produit, quelle que soit la clé utilisée par l'écran.
double? productBasePrice(Map<dynamic, dynamic> product) {
  for (final key in kBasePriceKeys) {
    final value = parsePriceValue(product[key]);
    if (value != null) return value;
  }
  return null;
}

/// Prix unitaire le plus bas atteignable grace aux paliers dégressifs,
/// plafonné au prix de base. Retourne null si le produit n'a aucun palier
/// exploitable.
double? lowestTierPrice(Map<dynamic, dynamic> product) {
  List<dynamic>? tiers;
  for (final key in kTierPriceKeys) {
    final raw = product[key];
    if (raw is List && raw.isNotEmpty) {
      tiers = raw;
      break;
    }
  }
  if (tiers == null) return null;

  double? lowest;
  for (final tier in tiers) {
    final price = tier is Map
        ? parsePriceValue(tier['price'])
        : parsePriceValue(tier);
    if (price == null) continue;
    if (lowest == null || price < lowest) lowest = price;
  }
  if (lowest == null) return null;

  // Un palier ne doit jamais faire payer plus cher que le prix normal.
  final base = productBasePrice(product);
  if (base != null && lowest > base) return base;
  return lowest;
}

/// Montant formaté comme partout dans l'appli : séparateur de milliers
/// = espace, pas de décimale (le FCFA n'a pas de centime).
String formatPriceAmount(num amount) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer(rounded < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// true si le produit a un palier strictement moins cher que le prix normal
/// (donc si une fourchette sera affichée).
bool hasPriceRange(Map<dynamic, dynamic> product) {
  final base = productBasePrice(product);
  final lowest = lowestTierPrice(product);
  if (base == null || lowest == null) return false;
  return lowest.round() < base.round();
}

/// Texte à afficher sur une carte produit.
///
/// - aucun palier, ou palier non moins cher que le prix normal
///   → prix normal seul : « 39 FCFA » ;
/// - sinon fourchette du plus bas au prix normal : « 25 – 39 FCFA ».
///
/// [currency] : suffixe pour un prix seul. [rangeCurrency] : suffixe pour une
/// fourchette (par défaut le même) — utile sur les cartes étroites où
/// « FCFA » deux fois ne tiendrait pas sur une ligne.
String priceRangeLabel(
  Map<dynamic, dynamic> product, {
  String currency = 'FCFA',
  String? rangeCurrency,
}) {
  final base = productBasePrice(product);
  final lowest = lowestTierPrice(product);

  if (base == null) {
    return '${formatPriceAmount(lowest ?? 0)} $currency';
  }
  if (lowest == null || lowest.round() >= base.round()) {
    return '${formatPriceAmount(base)} $currency';
  }
  final suffix = rangeCurrency ?? currency;
  return '${formatPriceAmount(lowest)} – ${formatPriceAmount(base)} $suffix';
}
