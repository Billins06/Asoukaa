import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const passwordResetTemplate = (prenom: string, code: string): string => {
  const body = `
    <div style="margin:20px 0 0;padding:28px;background:#EEECFC;border:1.5px dashed #4338CA;border-radius:16px;text-align:center;">
      <span style="font-size:38px;font-weight:800;letter-spacing:12px;color:#4338CA;">${code}</span>
      <p style="margin:12px 0 0;font-size:13px;color:#6B6B72;">Ce code expire dans <strong style="color:#3A3A40;">03 minutes</strong></p>
    </div>
    <p style="margin:20px 0 24px;font-size:13px;color:#8B8B93;line-height:1.55;">Si vous n'avez pas fait cette demande, ignorez cet email : votre mot de passe reste inchangé.</p>`;

  return renderEmailLayout({
    category: 'compte',
    title: 'Réinitialisation du mot de passe',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, vous avez demandé à réinitialiser votre mot de passe. Voici votre code :`,
    body,
  });
};
