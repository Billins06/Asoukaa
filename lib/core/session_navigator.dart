import 'package:flutter/material.dart';

/// Clé du Navigator racine.
///
/// L'intercepteur HTTP doit pouvoir renvoyer vers l'écran de connexion quand le
/// serveur répond 401, or il ne dispose d'aucun BuildContext. Cette clé lui
/// donne accès au Navigator sans passer par l'arbre de widgets.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
