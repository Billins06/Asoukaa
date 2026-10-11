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

# ── delivery.service.ts: createForOrder accepts optional lat/lng ───────
patch(
    "src/modules/delivery/delivery.service.ts",
    """  async createForOrder(
    orderId:         string,
    pickupAddress:   string,
    adresseLivraison: string,
  ): Promise<Delivery> {
    // Vérifier qu'une livraison n'existe pas déjà
    const existing = await this.deliveryRepo.findOne({
      where: { orderId },
    });

    if (existing) return existing;

    const delivery                  = this.deliveryRepo.create();
    delivery.orderId                = orderId;
    delivery.agentId                = null;
    delivery.pickupAddress          = pickupAddress;
    delivery.adresseLivraison       = adresseLivraison;
    delivery.status                 = DeliveryStatus.PENDING;

    return this.deliveryRepo.save(delivery);
  }""",
    """  async createForOrder(
    orderId:          string,
    pickupAddress:    string,
    adresseLivraison: string,
    latitude?:        number | null,
    longitude?:       number | null,
  ): Promise<Delivery> {
    // Vérifier qu'une livraison n'existe pas déjà
    const existing = await this.deliveryRepo.findOne({
      where: { orderId },
    });

    if (existing) return existing;

    const delivery                  = this.deliveryRepo.create();
    delivery.orderId                = orderId;
    delivery.agentId                = null;
    delivery.pickupAddress          = pickupAddress;
    delivery.adresseLivraison       = adresseLivraison;
    delivery.latitude               = latitude ?? null;
    delivery.longitude              = longitude ?? null;
    delivery.status                 = DeliveryStatus.PENDING;

    return this.deliveryRepo.save(delivery);
  }""",
)

# ── orders.service.ts: pass address.latitude/longitude through ─────────
patch(
    "src/modules/orders/orders.service.ts",
    """      for (const order of createdOrders) {
        await this.deliveryService.createForOrder(
          order.id,
          pickupAddressByOrderId.get(order.id) ?? '',
          adresseLivraison,
        );
      }""",
    """      for (const order of createdOrders) {
        await this.deliveryService.createForOrder(
          order.id,
          pickupAddressByOrderId.get(order.id) ?? '',
          adresseLivraison,
          address.latitude,
          address.longitude,
        );
      }""",
)

print("PART2 DONE")
