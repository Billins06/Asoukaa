import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const adminInvitationTemplate = (prenom: string, role: string, link: string): string => {
  const body = `
    <p style="margin:0 0 20px;font-size:14px;color:#6B6B72;line-height:1.6;">Cliquez sur le bouton ci-dessous pour définir votre mot de passe et accéder au dashboard.</p>
    <p style="margin:0 0 8px;font-size:12px;color:#ACACB2;">Ce lien expire dans <strong style="color:#8B8B93;">48 heures</strong>.</p>`;

  return renderEmailLayout({
    category: 'compte',
    title: 'Invitation — Dashboard Asoukaa',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, vous avez été invité(e) en tant que <strong style="color:#3A3A40;">${escapeHtml(role)}</strong> sur Asoukaa.`,
    body,
    cta: { label: 'Définir mon mot de passe', href: escapeHtml(link) },
  });
};
