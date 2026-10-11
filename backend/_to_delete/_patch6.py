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

# 1) Branch to the group-payment path at the top of initiatePayment.
patch(
    path,
    """  async initiatePayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
    // 1. Récupérer la commande
    const order = await this.orderRepo.findOne({
      where:     { id: dto.orderId, userId },
      relations: ['items', 'items.variant'],
    });""",
    """  async initiatePayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
    // Panier réparti sur plusieurs boutiques : plusieurs commandes créées
    // ensemble (une par boutique, voir OrdersService.createFromCart), mais
    // le client ne doit payer qu'une seule fois.
    if (dto.orderIds && dto.orderIds.length > 0) {
      return this.initiateGroupPayment(userId, dto, ip);
    }

    // 1. Récupérer la commande
    const order = await this.orderRepo.findOne({
      where:     { id: dto.orderId, userId },
      relations: ['items', 'items.variant'],
    });""",
)

# 2) Insert the new private method right after initiatePayment's closing
#    brace — anchored on the start of the next documented method so we
#    don't have to reproduce initiatePayment's whole body as the anchor.
patch(
    path,
    """  // ─────────────────────────────────────────────────────
  // APPEL RÉEL À L'API FEEXPAY (requesttopay mobile money)""",
    """  // ─────────────────────────────────────────────────────
  // PANIER MULTI-BOUTIQUES — UN SEUL PAIEMENT POUR PLUSIEURS COMMANDES
  // Même schéma que initiatePayment() (commande unique) mais appliqué à
  // un groupe de commandes créées ensemble par OrdersService.createFromCart
  // (une commande par boutique). On crée une ligne Payment par commande
  // (orderId reste unique en base — impossible de n'en créer qu'une seule
  // pour plusieurs commandes), mais toutes partagent le même groupRef et
  // le même providerRef FeexPay : un seul montant est réellement demandé
  // au client. checkPaymentStatus() confirmera ensuite TOUTES les lignes
  // du groupe d'un coup dès que FeexPay confirme.
  // ─────────────────────────────────────────────────────
  private async initiateGroupPayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
    const orderIds = dto.orderIds!;

    const orders = await this.orderRepo.find({
      where:     { id: In(orderIds), userId },
      relations: ['items', 'items.variant'],
    });

    if (orders.length !== orderIds.length) {
      throw new NotFoundException(
        'Une ou plusieurs commandes de ce paiement sont introuvables'
      );
    }

    for (const order of orders) {
      if (order.status !== OrderStatus.PENDING) {
        throw new BadRequestException(
          `La commande ${order.orderNumber} ne peut plus être payée`
        );
      }
    }

    const existingPayments = await this.paymentRepo.find({
      where: { orderId: In(orderIds) },
    });

    for (const existing of existingPayments) {
      if (existing.status === PaymentStatus.SUCCESS) {
        throw new BadRequestException(
          'Une des commandes de ce paiement est déjà payée'
        );
      }
      if (existing.status === PaymentStatus.PENDING) {
        throw new BadRequestException(
          'Un paiement est déjà en cours pour une des commandes'
        );
      }
    }

    // Vérifier le stock une dernière fois avant le paiement
    for (const order of orders) {
      for (const item of order.items) {
        const variant = item.variant;
        if (variant.stockQuantity < item.quantity) {
          if (variant.stockQuantity === 0) {
            throw new BadRequestException(
              `"${variant.sku}" n'est plus disponible. `
              + `Veuillez retirer cet article de votre commande.`
            );
          }
          throw new BadRequestException(
            `Stock insuffisant pour la référence "${variant.sku}". `
            + `Il reste ${variant.stockQuantity} unité(s).`
          );
        }
      }
    }

    const totalAmount = orders.reduce((sum, o) => sum + Number(o.total), 0);
    const groupRef     = randomUUID();

    const existingByOrderId = new Map(
      existingPayments.map(p => [p.orderId, p]),
    );

    const payments = orders.map(order => {
      const payment    = existingByOrderId.get(order.id) ?? this.paymentRepo.create();
      payment.orderId  = order.id;
      payment.method   = dto.method;
      payment.operator = dto.operator ?? null;
      payment.status   = PaymentStatus.PENDING;
      payment.montant  = order.total;
      payment.groupRef = groupRef;
      return payment;
    });

    await this.paymentRepo.save(payments);

    void Promise.all(
      payments.map(payment =>
        this.logService.log({
          actorId:    userId,
          actorType:  ActorType.CLIENT,
          action:     LogAction.PAYMENT_FAILED, // mis à jour à la confirmation
          entityType: 'payment',
          entityId:   payment.id,
          newValue:   { method: dto.method, amount: payment.montant, groupRef },
          ipAddress:  ip,
        }),
      ),
    );

    const primaryPayment = payments[0];

    if (dto.method === PaymentMethod.MOBILE_MONEY) {
      const reseau =
        dto.operator === PaymentOperator.MTN  ? 'MTN'  :
        dto.operator === PaymentOperator.MOOV ? 'MOOV' : null;

      if (!reseau) {
        await this.paymentRepo.update({ groupRef }, { status: PaymentStatus.FAILED });
        throw new BadRequestException(
          `L'opérateur "${dto.operator}" n'est pas encore pris en charge `
          + `via FeexPay (seuls MTN et Moov le sont pour le moment).`
        );
      }

      const user = await this.userRepo.findOne({ where: { id: userId } });

      try {
        const providerRef = await this.callFeexPayRequestToPay({
          phoneNumber: dto.phoneNumber!,
          amount:      totalAmount,
          reseau,
          firstName:   user?.prenom ?? 'Client',
          email:       user?.email ?? '',
          customId:    groupRef,
          description: `${orders.length} commandes (`
            + `${orders.map(o => o.orderNumber).join(', ')})`,
        });

        await this.paymentRepo.update({ groupRef }, { providerRef });
      } catch (err) {
        await this.paymentRepo.update({ groupRef }, { status: PaymentStatus.FAILED });
        throw err;
      }

      return {
        message:         'Demande envoyée. Confirmez le paiement sur votre téléphone.',
        paymentId:       primaryPayment.id,
        groupPaymentIds: payments.map(p => p.id),
        amount:          totalAmount,
        method:          dto.method,
        operator:        dto.operator,
      };
    }

    return {
      message:         'Paiement initié avec succès',
      paymentId:       primaryPayment.id,
      groupPaymentIds: payments.map(p => p.id),
      amount:          totalAmount,
      method:          dto.method,
      operator:        dto.operator,
    };
  }

  // ─────────────────────────────────────────────────────
  // APPEL RÉEL À L'API FEEXPAY (requesttopay mobile money)""",
)

print("PART6 DONE")
