export const agentApprovedTemplate = (prenom: string): string => `
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
            <td style="padding:40px 32px;text-align:center;">
              <div style="font-size:56px;margin-bottom:16px;">🚀</div>
              <h2 style="color:#1a1a1a;margin:0 0 16px;">Vous êtes approuvé comme livreur !</h2>
              <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 24px;">
                Félicitations <strong>${prenom}</strong> !<br/>
                Votre profil livreur a été validé. Vous pouvez maintenant activer votre disponibilité
                et commencer à accepter des livraisons sur Asoukaa.
              </p>
              <div style="background:#F0FFF4;border-left:4px solid #22C55E;padding:16px;text-align:left;border-radius:4px;">
                <p style="color:#0F6E56;font-size:14px;margin:0;">
                  ✅ Activez votre disponibilité dans l'app<br/>
                  ✅ Acceptez vos premières livraisons<br/>
                  ✅ Construisez votre réputation
                </p>
              </div>
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