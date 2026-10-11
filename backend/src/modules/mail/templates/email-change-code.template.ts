import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Code envoyé à la NOUVELLE adresse : c'est la preuve que l'utilisateur en
// a bien le contrôle avant qu'elle ne remplace son identifiant de connexion.
export const emailChangeCodeTemplate = (prenom: string, code: string): string => {
  const body = `
    <div style="margin:20px 0 0;padding:28px;background:#EEECFC;border:1.5px dashed #4338CA;border-radius:16px;text-align:center;">
      <span style="font-size:38px;font-weight:800;letter-spacing:12px;color:#4338CA;">${escapeHtml(code)}</span>
      <p style="margin:12px 0 0;font-size:13px;color:#6B6B72;">Ce code expire dans <strong style="color:#3A3A40;">10 minutes</strong></p>
    </div>
    <div style="margin:18px 0 24px;padding:16px 18px;border:1px solid #ECEAE6;border-radius:14px;">
      <p style="margin:0;font-size:13px;color:#8B8B93;line-height:1.55;">Si vous n'êtes pas à l'origine de cette demande, ignorez simplement cet email : rien ne sera modifié. Ne partagez jamais ce code, l'équipe Asoukaa ne vous le demandera jamais.</p>
    </div>`;

  return renderEmailLayout({
    category: 'compte',
    title: 'Confirmez votre nouvelle adresse email',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, saisissez ce code dans l'application Asoukaa pour utiliser cette adresse comme identifiant de connexion.`,
    body,
  });
};
