// Aides pour l'annulation / la vérification d'un paiement Mobile Money.
//
// Pourquoi : quand l'appli abandonne l'attente (délai de ~2 minutes dépassé
// ou bouton « Annuler l'attente »), elle appelle
// PATCH /api/v1/payments/{id}/cancel. Le serveur répond toujours HTTP 200 :
//  - { status: 'success', message }  -> le paiement était en fait confirmé ;
//  - { status: 'échoué', message }   -> échec confirmé, le client peut réessayer ;
//  - { status: 'en attente', verificationEnCours: true, message }
//      -> pas confirmé mais NON annulé : FeexPay n'a pas encore répondu,
//         le client ne doit PAS repayer tout de suite ;
//  - ancien serveur : juste { message } (sans `status`) -> comportement
//    historique (échec / annulé).
// Ce fichier lit cette réponse sans jamais planter (types inconnus, champs
// absents) et garde en mémoire les commandes « en cours de vérification ».

/// Texte affiché si le serveur n'envoie pas de message.
const String messagePaiementEnVerification =
    'Paiement en cours de vérification. Vous serez prévenu(e) dès sa '
    'confirmation. Ne payez pas une seconde fois.';

/// Issue d'une demande d'annulation de paiement.
enum IssueAnnulation { reussi, echoue, verificationEnCours }

/// Réponse du serveur à PATCH /payments/{id}/cancel, lue de façon défensive.
class ReponseAnnulationPaiement {
  final IssueAnnulation issue;

  /// Message du serveur (null s'il est absent ou vide).
  final String? message;

  /// Vrai si le serveur a envoyé un `status` (donc un échec explicite quand
  /// l'issue est [IssueAnnulation.echoue]). Faux pour un ancien serveur qui
  /// ne renvoie que { message }, ou une réponse illisible.
  final bool statutRecu;

  const ReponseAnnulationPaiement(
    this.issue, [
    this.message,
    this.statutRecu = false,
  ]);

  /// Vrai si le serveur a explicitement répondu « échoué » : le client peut
  /// réessayer et on peut lui montrer le message du serveur.
  bool get echecConfirme => issue == IssueAnnulation.echoue && statutRecu;

  /// Message à montrer au client après un échec confirmé : celui du serveur
  /// s'il existe, sinon un texte par défaut.
  String get messageEchec {
    final m = message;
    if (m != null && m.isNotEmpty) return m;
    return 'Paiement échoué, vous pouvez réessayer.';
  }

  /// Message à montrer au client quand le paiement est en vérification :
  /// celui du serveur s'il existe, sinon le texte par défaut.
  String get messageVerification {
    final m = message;
    if (m != null && m.isNotEmpty) return m;
    return messagePaiementEnVerification;
  }
}

/// Lit la réponse de PATCH /payments/{id}/cancel.
/// Toute réponse illisible ou sans `status` (ancien serveur) = [echoue],
/// c'est-à-dire le comportement historique.
ReponseAnnulationPaiement lireReponseAnnulation(dynamic data) {
  if (data is! Map) {
    return const ReponseAnnulationPaiement(IssueAnnulation.echoue);
  }

  final statutBrut = data['status'];
  final statut = statutBrut is String ? statutBrut.trim().toLowerCase() : '';

  String? message;
  final messageBrut = data['message'];
  if (messageBrut is String) {
    final t = messageBrut.trim();
    if (t.isNotEmpty) message = t;
  } else if (messageBrut is List && messageBrut.isNotEmpty) {
    final t = messageBrut.first.toString().trim();
    if (t.isNotEmpty) message = t;
  }

  final verifBrut = data['verificationEnCours'];
  final verification = verifBrut == true || verifBrut == 'true';

  if (statut == 'success' || statut == 'succes' || statut == 'succès') {
    return ReponseAnnulationPaiement(IssueAnnulation.reussi, message);
  }
  // Par prudence, tout ce qui ressemble à « en attente » est traité comme
  // « en cours de vérification » : on ne propose pas de repayer.
  if (verification || statut.contains('attente') || statut == 'pending') {
    return ReponseAnnulationPaiement(
      IssueAnnulation.verificationEnCours,
      message,
    );
  }
  return ReponseAnnulationPaiement(
    IssueAnnulation.echoue,
    message,
    statut.isNotEmpty,
  );
}

/// Vrai si ce message serveur dit qu'un paiement est déjà en cours de
/// vérification (réponse 400 de POST /payments/initiate).
bool estMessageVerificationEnCours(String texte) {
  final t = texte.toLowerCase();
  return t.contains('en cours de vérification') ||
      t.contains('en cours de verification');
}

/// Mémoire (le temps de la session de l'appli) des commandes dont le paiement
/// est « en cours de vérification » : empêche de relancer un second paiement
/// sur la même commande pendant quelques minutes. Le serveur reste la
/// référence (il refuse aussi avec un message 400) ; ceci est une 2e barrière.
class PaiementsEnVerification {
  PaiementsEnVerification._();

  static const Duration duree = Duration(minutes: 5);
  static final Map<String, DateTime> _depuis = <String, DateTime>{};

  /// Note ces commandes comme « en cours de vérification » à partir de maintenant.
  static void marquer(Iterable<String> orderIds) {
    final maintenant = DateTime.now();
    for (final id in orderIds) {
      if (id.isNotEmpty) _depuis[id] = maintenant;
    }
  }

  /// Oublie ces commandes (paiement confirmé ou échec confirmé).
  static void oublier(Iterable<String> orderIds) {
    for (final id in orderIds) {
      _depuis.remove(id);
    }
  }

  /// Vrai si au moins une de ces commandes est encore en vérification.
  static bool estEnVerification(Iterable<String> orderIds) {
    final maintenant = DateTime.now();
    var trouve = false;
    for (final id in orderIds) {
      final debut = _depuis[id];
      if (debut == null) continue;
      if (maintenant.difference(debut) < duree) {
        trouve = true;
      } else {
        _depuis.remove(id);
      }
    }
    return trouve;
  }
}
