export const agentRejectedTemplate = (prenom: string, motif: string): string => `
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
              <h2 style="color:#1a1a1a;margin:0 0 16px;">Demande livreur non approuvée</h2>
              <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 24px;">
                Bonjour <strong>${prenom}</strong>,<br/>
                Votre demande pour devenir livreur Asoukaa n'a pas pu être approuvée.
              </p>
              <div style="background:#FEF2F2;border-left:4px solid #EF4444;padding:16px;border-radius:4px;margin-bottom:24px;">
                <p style="color:#993C1D;font-size:14px;margin:0 0 8px;font-weight:600;">Motif du refus :</p>
                <p style="color:#993C1D;font-size:14px;margin:0;">${motif}</p>
              </div>
              <p style="color:#555;font-size:14px;">
                Corrigez les points mentionnés et soumettez à nouveau votre demande depuis l'application.
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