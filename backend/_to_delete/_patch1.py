import re

def patch(path, old, new, expect=1):
    with open(path, encoding='utf-8') as f:
        content = f.read()
    count = content.count(old)
    if count != expect:
        print(f"MISMATCH ({count} != {expect}): {path}")
        print(repr(old[:200]))
        raise SystemExit(1)
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {path} ({count})")

# ── 1. Address entity: add latitude/longitude ──────────────────────────
patch(
    "src/modules/users/entities/address.entity.ts",
    """  @Column({ length: 100, default: 'Bénin' })
  country: string;""",
    """  @Column({ length: 100, default: 'Bénin' })
  country: string;

  // Position GPS partagée par le client (bouton "Partager ma
  // localisation" au paiement) — optionnelle, permet au livreur de
  // retrouver le client précisément plutôt que de se fier uniquement
  // au texte de l'adresse.
  @Column({ type: 'double precision', nullable: true })
  latitude: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude: number | null;""",
)

# ── 2. CreateAddressDto: accept optional latitude/longitude ────────────
patch(
    "src/modules/users/dto/create-address.dto.ts",
    """import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  MaxLength,
  Matches,
} from 'class-validator';""",
    """import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  IsNumber,
  MaxLength,
  Matches,
} from 'class-validator';""",
)
patch(
    "src/modules/users/dto/create-address.dto.ts",
    """  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}""",
    """  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;

  // Position GPS optionnelle (bouton "Partager ma localisation")
  @IsOptional()
  @IsNumber()
  latitude?: number;

  @IsOptional()
  @IsNumber()
  longitude?: number;
}""",
)

# ── 3. Delivery entity: add latitude/longitude (denormalisé, même
#      logique que adresseLivraison déjà copiée en texte) ──────────────
patch(
    "src/modules/delivery/entities/delivery.entity.ts",
    """  // Adresse du client (destination)
  @Column({ type: 'text' })
  adresseLivraison: string;""",
    """  // Adresse du client (destination)
  @Column({ type: 'text' })
  adresseLivraison: string;

  // Position GPS du client, copiée depuis l'adresse au moment de la
  // création de la commande — permet au livreur d'ouvrir directement
  // l'itinéraire dans Maps plutôt que de chercher le texte de l'adresse.
  @Column({ type: 'double precision', nullable: true })
  latitude: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude: number | null;""",
)

print("PART1 DONE")
