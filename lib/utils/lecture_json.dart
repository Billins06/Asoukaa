// Lecture tolérante des nombres reçus du serveur.
//
// Pourquoi : le serveur renvoie les décimaux (prix, notes, frais, montants)
// en TEXTE (« 20.00 »), alors que les entiers arrivent en nombre. Un cast
// direct (`x as num`, `x as double`) plante sur un texte, et un test
// `x is num ? ... : 0` affiche un faux « 0 ». Ces fonctions acceptent un
// nombre, un texte (« 20.00 », « 1 500,50 ») ou null, et ne plantent jamais.

/// Lit un nombre décimal. Renvoie [defaut] si la valeur est absente ou illisible.
double lireDouble(dynamic valeur, [double defaut = 0]) =>
    lireDoubleOuNull(valeur) ?? defaut;

/// Comme [lireDouble], mais renvoie null si la valeur est absente ou illisible.
double? lireDoubleOuNull(dynamic valeur) {
  if (valeur == null) return null;
  if (valeur is num) return valeur.toDouble();
  if (valeur is String) {
    var t = valeur.trim();
    if (t.isEmpty) return null;
    // Espaces (y compris insécables) retirés ; virgule décimale acceptée.
    t = t.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '').replaceAll(',', '.');
    return double.tryParse(t);
  }
  return null;
}

/// Lit un entier (un décimal est arrondi vers zéro). [defaut] si illisible.
int lireInt(dynamic valeur, [int defaut = 0]) =>
    lireIntOuNull(valeur) ?? defaut;

/// Comme [lireInt], mais renvoie null si la valeur est absente ou illisible.
int? lireIntOuNull(dynamic valeur) {
  if (valeur == null) return null;
  if (valeur is int) return valeur;
  if (valeur is num) return valeur.isFinite ? valeur.toInt() : null;
  final d = lireDoubleOuNull(valeur);
  if (d == null || !d.isFinite) return null;
  return d.toInt();
}
