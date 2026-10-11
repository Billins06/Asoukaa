import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const otpTemplate = (prenom: string, code: string): string => {
  const body = `
    <div style="margin:20px 0 0;padding:28px;background:#EEECFC;border:1.5px dashed #4338CA;border-radius:16px;text-align:center;">
      <span style="font-size:38px;font-weight:800;letter-spacing:12px;color:#4338CA;">${code}</span>
      <p style="margin:12px 0 0;font-size:13px;color:#6B6B72;">Ce code expire dans <strong style="color:#3A3A40;">03 minutes</strong></p>
    </div>
    <div style="margin:18px 0 24px;padding:16px 18px;border:1px solid #ECEAE6;border-radius:14px;">
      <p style="margin:0;font-size:13px;color:#8B8B93;line-height:1.55;">Ne partagez jamais ce code. L'équipe Asoukaa ne vous le demandera jamais, ni par téléphone ni par email.</p>
    </div>`;

  return renderEmailLayout({
    category: 'compte',
    title: 'Vérifiez votre adresse email',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, voici votre code de vérification pour activer votre compte Asoukaa.`,
    body,
  });
};
