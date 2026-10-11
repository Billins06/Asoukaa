import { escapeHtml } from '../../mail/templates/base-layout.template';

// Petites pages HTML autonomes (aucun script, aucune ressource externe) pour
// le lien « Ce n'est pas moi » reçu par e-mail. Toute valeur variable passe
// par escapeHtml, même celles qui devraient être sûres (jeton hexadécimal,
// adresse masquée).

const ACCENT = '#FF6210';

const layout = (title: string, inner: string): string => `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex, nofollow"/>
<meta name="referrer" content="no-referrer"/>
<title>${escapeHtml(title)} · Asoukaa</title>
<style>
  *{box-sizing:border-box}
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px;background:#F3F1EE;color:#17171A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;line-height:1.55}
  .card{width:100%;max-width:480px;background:#fff;border:1px solid #ECEAE6;border-radius:18px;padding:28px 24px}
  .brand{font-size:18px;font-weight:800;color:${ACCENT};margin:0 0 18px}
  h1{font-size:21px;margin:0 0 12px}
  p{margin:0 0 14px;font-size:15px;color:#3A3A40}
  .note{font-size:13px;color:#6B6B72}
  .box{background:#FFF1E6;border:1px solid #F5D3B8;border-radius:12px;padding:12px 14px;margin:0 0 16px}
  button{width:100%;padding:15px 16px;border:0;border-radius:12px;background:${ACCENT};color:#fff;font-size:15px;font-weight:700;cursor:pointer}
  button:hover{filter:brightness(.95)}
</style>
</head>
<body>
<main class="card">
  <p class="brand">Asoukaa</p>
  ${inner}
</main>
</body>
</html>`;

/** Page de confirmation affichée par le GET : n'exécute rien tant qu'on ne clique pas. */
export const revertConfirmPage = (maskedNewEmail: string): string =>
  layout(
    'Sécuriser mon compte',
    `<h1>Ce changement d'adresse n'est pas de vous&nbsp;?</h1>
  <div class="box"><p style="margin:0">L'adresse de connexion de votre compte a été remplacée par <strong>${escapeHtml(maskedNewEmail)}</strong>.</p></div>
  <p>Si vous confirmez que vous n'êtes pas à l'origine de ce changement, nous allons&nbsp;:</p>
  <p>&#8226; rétablir votre adresse d'origine&nbsp;;<br/>&#8226; déconnecter tous les appareils&nbsp;;<br/>&#8226; annuler votre mot de passe actuel&nbsp;;<br/>&#8226; prévenir l'équipe Asoukaa.</p>
  <form method="post">
    <button type="submit">Oui, ce n'est pas moi — sécuriser mon compte</button>
  </form>
  <p class="note" style="margin-top:16px">Si c'est bien vous qui avez changé d'adresse, fermez simplement cette page : rien ne sera modifié.</p>`,
  );

/** Compte sécurisé et adresse d'origine rétablie. */
export const revertDonePage = (): string =>
  layout(
    'Compte sécurisé',
    `<h1>Votre compte est sécurisé</h1>
  <p>Votre adresse d'origine a été rétablie, tous les appareils ont été déconnectés et votre ancien mot de passe a été annulé.</p>
  <div class="box"><p style="margin:0"><strong>Étape suivante&nbsp;:</strong> dans l'application Asoukaa, appuyez sur «&nbsp;Mot de passe oublié&nbsp;», saisissez votre adresse email et choisissez un nouveau mot de passe avec le code reçu.</p></div>
  <p class="note">L'équipe Asoukaa a été prévenue. Un email récapitulatif vous a été envoyé.</p>`,
  );

/** Sécurisation faite, mais l'adresse d'origine n'a pas pu être rétablie. */
export const revertPartialPage = (): string =>
  layout(
    'Compte sécurisé',
    `<h1>Votre compte a été sécurisé</h1>
  <p>Tous les appareils ont été déconnectés et le mot de passe a été annulé. En revanche, votre adresse d'origine n'a pas pu être rétablie automatiquement car elle est désormais utilisée par un autre compte.</p>
  <div class="box"><p style="margin:0">Par précaution, le compte a été bloqué. <strong>Contactez le support Asoukaa</strong> afin que l'équipe vous aide à en reprendre le contrôle.</p></div>
  <p class="note">L'équipe Asoukaa a été prévenue.</p>`,
  );

/** Jeton inconnu, expiré ou déjà utilisé — volontairement sans détail. */
export const revertInvalidPage = (): string =>
  layout(
    'Lien non valide',
    `<h1>Ce lien n'est plus valide</h1>
  <p>Ce lien a expiré, a déjà été utilisé ou n'est pas correct.</p>
  <p class="note">Si vous pensez que votre compte est en danger, utilisez «&nbsp;Mot de passe oublié&nbsp;» dans l'application Asoukaa ou contactez le support.</p>`,
  );
