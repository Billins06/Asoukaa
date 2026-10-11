import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Envoyé à l'adresse d'origine RESTAURÉE après un « Ce n'est pas moi ».
export const emailChangeSecuredTemplate = (prenom: string): string => {
  const body = `
    <div style="margin:20px 0 0;padding:18px 20px;border:1px solid #ECEAE6;border-radius:14px;">
      <p style="margin:0 0 10px;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Ce que nous avons fait</strong></p>
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.7;">&#8226; Votre adresse de connexion d'origine a été rétablie.<br/>&#8226; Tous les appareils ont été déconnectés.<br/>&#8226; Votre ancien mot de passe a été annulé.</p>
    </div>
    <div style="margin:18px 0 0;padding:18px 20px;background:#EEECFC;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Ce que vous devez faire</strong> : dans l'application Asoukaa, appuyez sur « Mot de passe oublié », saisissez cette adresse email, puis choisissez un nouveau mot de passe avec le code reçu.</p>
    </div>
    <p style="margin:18px 0 24px;font-size:13px;color:#8B8B93;line-height:1.55;">L'équipe Asoukaa a été prévenue et examine la situation.</p>`;

  return renderEmailLayout({
    category: 'compte',
    badge: 'check',
    title: 'Compte sécurisé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, vous avez signalé que le changement d'adresse n'était pas de votre fait. Votre compte Asoukaa est sécurisé.`,
    body,
  });
};
