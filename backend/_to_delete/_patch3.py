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

# ── Payment entity: add groupRef ────────────────────────────────────────
patch(
    "src/modules/payments/entities/payment.entity.ts",
    """  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montant: number;""",
    """  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montant: number;

  // Panier réparti sur plusieurs boutiques -> une commande par boutique,
  // mais UN SEUL paiement pour le client. On crée quand même une ligne
  // Payment par commande (orderId reste unique en base), mais toutes les
  // lignes issues du même paiement client partagent ce groupRef pour
  // pouvoir toutes les confirmer/échouer ensemble.
  @Index()
  @Column({ nullable: true, length: 64 })
  groupRef: string | null;""",
)

print("PART3 DONE")
