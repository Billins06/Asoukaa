export const passwordResetTemplate = (prenom: string, code: string): string => `
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr>
      <td align="center" style="padding:40px 0;">
        <table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.1);">
          <tr>
            <td style="background:#FF6B00;padding:32px;text-align:center;">
              <h1 style="color:#fff;margin:0;font-size:28px;">Asoukaa</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:40px 32px;">
              <h2 style="color:#1a1a1a;margin:0 0 16px;">Réinitialisation du mot de passe</h2>
              <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 24px;">
                Bonjour <strong>${prenom}</strong>,<br/>
                Vous avez demandé à réinitialiser votre mot de passe. Voici votre code valable <strong>03 minutes</strong> :
              </p>
              <div style="background:#f8f8f8;border:2px dashed #FF6B00;border-radius:12px;padding:24px;text-align:center;margin:0 0 24px;">
                <span style="font-size:42px;font-weight:700;letter-spacing:12px;color:#FF6B00;">${code}</span>
              </div>
              <p style="color:#888;font-size:13px;">
                Si vous n'avez pas fait cette demande, ignorez cet email. Votre mot de passe reste inchangé.
              </p>
            </td>
          </tr>
          <tr>
            <td style="background:#f8f8f8;padding:20px 32px;text-align:center;border-top:1px solid #eee;">
              <p style="color:#aaa;font-size:12px;margin:0;">© ${new Date().getFullYear()} Asoukaa</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`;