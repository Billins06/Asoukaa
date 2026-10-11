import sys

def patch(path, old, new, expect=1):
    with open(path, encoding='utf-8') as f:
        content = f.read()
    count = content.count(old)
    if count != expect:
        print(f"MISMATCH ({count} != {expect}): {path}")
        print(repr(old[:200]))
        sys.exit(1)
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {path} ({count})")

path = "src/modules/payments/payments.service.ts"

patch(
    path,
    """    if (['SUCCESSFUL', 'SUCCESS', 'APPROVED'].includes(feexStatus)) {
      return this.confirmPayment(paymentId, payment.providerRef, ip);
    }

    if (['FAILED', 'CANCELLED', 'CANCELED', 'ERROR'].includes(feexStatus)) {
      return this.failPayment(paymentId, ip);
    }

    return { status: payment.status }; // toujours en attente
  }""",
    """    if (['SUCCESSFUL', 'SUCCESS', 'APPROVED'].includes(feexStatus)) {
      return this.confirmPaymentOrGroup(payment, ip);
    }

    if (['FAILED', 'CANCELLED', 'CANCELED', 'ERROR'].includes(feexStatus)) {
      return this.failPaymentOrGroup(payment, ip);
    }

    return { status: payment.status }; // toujours en attente
  }

  // ─────────────────────────────────────────────────────
  // Confirme un paiement, ET tous ses "frères" de même groupRef s'il en a
  // (panier multi-boutiques réglé en un seul paiement — voir
  // initiateGroupPayment). Chaque commande garde sa propre logique de
  // confirmation (stock, commission, email) via confirmPayment(), on
  // l'applique juste à tout le groupe d'un coup.
  // ─────────────────────────────────────────────────────
  private async confirmPaymentOrGroup(payment: Payment, ip: string) {
    if (!payment.groupRef) {
      return this.confirmPayment(payment.id, payment.providerRef, ip);
    }

    const siblings = await this.paymentRepo.find({
      where: { groupRef: payment.groupRef, status: PaymentStatus.PENDING },
    });

    const results = [];
    for (const sibling of siblings) {
      results.push(
        await this.confirmPayment(sibling.id, payment.providerRef, ip),
      );
    }

    return {
      message: `${results.length} commande(s) confirmée(s)`,
      status:  PaymentStatus.SUCCESS,
      orders:  results.map(r => r.orderNumber),
    };
  }

  // ─────────────────────────────────────────────────────
  // Symétrique de confirmPaymentOrGroup() pour un échec.
  // ─────────────────────────────────────────────────────
  private async failPaymentOrGroup(payment: Payment, ip: string) {
    if (!payment.groupRef) {
      return this.failPayment(payment.id, ip);
    }

    const siblings = await this.paymentRepo.find({
      where: { groupRef: payment.groupRef, status: PaymentStatus.PENDING },
    });

    for (const sibling of siblings) {
      await this.failPayment(sibling.id, ip);
    }

    return { message: 'Paiement marqué comme échoué' };
  }""",
)

print("PART7 DONE")
