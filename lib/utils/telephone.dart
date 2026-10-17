// Numéros de téléphone : normalisation avant envoi au serveur.
//
// Le serveur n'accepte qu'un numéro de la forme `+?[0-9]{8,15}` (chiffres,
// éventuellement précédés d'un « + »). L'application affiche pourtant
// l'exemple « +229 97 000 000 » : on retire donc espaces, tirets, points et
// parenthèses AVANT l'envoi. Ce que l'utilisateur voit dans le champ ne change
// pas : seule la valeur envoyée est nettoyée.

final RegExp _separateursTelephone = RegExp(r'[\s\-.()\u00A0\u202F]');

/// « +229 97-00.00 (00) » -> « +22997000000 ». Ne touche pas aux autres
/// caractères : un numéro réellement invalide reste refusé par le serveur.
String normaliserTelephone(String brut) =>
    brut.trim().replaceAll(_separateursTelephone, '');
