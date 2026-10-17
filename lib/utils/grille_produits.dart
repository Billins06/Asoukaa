// Réglages UNIQUES des grilles de produits de l'appli (taille des cartes).
//
// Pourquoi : la taille des cartes était réglée écran par écran (0.62 à
// l'accueil, 0.72 dans la recherche, hauteur fixe dans les catégories...),
// d'où des cartes tantôt grandes, tantôt petites. Pour changer la taille
// partout, il suffit de modifier les valeurs ci-dessous.

/// Largeur / hauteur d'une carte produit (0.72 = un peu plus haute que large).
const double kProductGridRatio = 0.72;

/// Espace entre deux cartes (horizontal et vertical).
const double kProductGridSpacing = 10;

/// Marge à gauche et à droite d'une grille de produits.
const double kProductGridPadding = 12;

/// Largeur d'écran à partir de laquelle on passe en mode tablette.
const double kProductGridTabletWidth = 600;

/// Nombre de colonnes : 2 sur téléphone, 3 sur tablette.
int productGridColumns(double screenWidth) =>
    screenWidth >= kProductGridTabletWidth ? 3 : 2;
