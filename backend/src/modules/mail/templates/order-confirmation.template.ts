export interface OrderConfirmationData {
  prenom: string;
  orderNumber: string;
  items: { name: string; quantity: number; price: number }[];
  total: number;
  adresse: string;
}

export const orderConfirmationTemplate = (data: OrderConfirmationData): string => {
  const itemsRows = data.items.map(item => `
    <tr>
      <td style="padding:10px;border-bottom:1px solid #eee;color:#333;font-size:14px;">${item.name}</td>
      <td style="padding:10px;border-bottom:1px solid #eee;color:#333;font-size:14px;text-align:center;">${item.quantity}</td>
      <td style="padding:10px;border-bottom:1px solid #eee;color:#333;font-size:14px;text-align:right;">${item.price.toLocaleString('fr-FR')} FCFA</td>
    </tr>
  `).join('');

  return `
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
              <h2 style="color:#1a1a1a;margin:0 0 8px;">Commande confirmée ✅</h2>
              <p style="color:#555;font-size:15px;margin:0 0 24px;">
                Bonjour <strong>${data.prenom}</strong>, votre commande <strong>#${data.orderNumber}</strong> a bien été reçue.
              </p>

              <!-- TABLEAU ARTICLES -->
              <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #eee;border-radius:8px;overflow:hidden;margin-bottom:24px;">
                <tr style="background:#f8f8f8;">
                  <th style="padding:10px;text-align:left;font-size:13px;color:#888;">Article</th>
                  <th style="padding:10px;text-align:center;font-size:13px;color:#888;">Qté</th>
                  <th style="padding:10px;text-align:right;font-size:13px;color:#888;">Prix</th>
                </tr>
                ${itemsRows}
                <tr>
                  <td colspan="2" style="padding:12px 10px;font-weight:700;font-size:15px;color:#1a1a1a;">Total</td>
                  <td style="padding:12px 10px;font-weight:700;font-size:15px;color:#FF6B00;text-align:right;">${data.total.toLocaleString('fr-FR')} FCFA</td>
                </tr>
              </table>

              <p style="color:#555;font-size:14px;margin:0;">
                📍 Livraison à : <strong>${data.adresse}</strong>
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
};