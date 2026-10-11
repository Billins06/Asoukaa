import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Confirmation courte envoyée à la NOUVELLE adresse une fois le changement validé.
export const emailChangeConfirmedTemplate = (prenom: string): string => {
  const body = `
    <p style="margin:20px 0 24px;font-size:13px;color:#8B8B93;line-height:1.55;">Utilisez dès maintenant cette adresse pour vous connecter à Asoukaa. Vous restez connecté sur votre appareil actuel.</p>`;

  return renderEmailLayout({
    category: 'compte',
    badge: 'check',
    title: 'Adresse email modifiée',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, cette adresse est maintenant l'identifiant de connexion de votre compte Asoukaa.`,
    body,
  });
};
