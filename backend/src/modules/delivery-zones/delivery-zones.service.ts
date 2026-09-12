import {
  Injectable,
  OnModuleInit,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { DeliveryZone }         from './entities/delivery-zone.entity';
import { UpdateDeliveryZoneDto } from './dto/update-delivery-zone.dto';

// Les 77 communes du Bénin, regroupées par département (source : découpage
// administratif officiel, 12 départements). Frais initialisés à 0 : à
// paramétrer ensuite depuis l'écran admin "Livraison par commune".
const BENIN_COMMUNES: Array<{ commune: string; departement: string }> = [
  // Alibori
  { commune: 'Banikoara',     departement: 'Alibori' },
  { commune: 'Gogounou',      departement: 'Alibori' },
  { commune: 'Kandi',         departement: 'Alibori' },
  { commune: 'Karimama',      departement: 'Alibori' },
  { commune: 'Malanville',    departement: 'Alibori' },
  { commune: 'Ségbana',       departement: 'Alibori' },
  // Atacora
  { commune: 'Boukoumbé',     departement: 'Atacora' },
  { commune: 'Cobly',         departement: 'Atacora' },
  { commune: 'Kérou',         departement: 'Atacora' },
  { commune: 'Kouandé',       departement: 'Atacora' },
  { commune: 'Matéri',        departement: 'Atacora' },
  { commune: 'Natitingou',    departement: 'Atacora' },
  { commune: 'Péhunco',       departement: 'Atacora' },
  { commune: 'Tanguiéta',     departement: 'Atacora' },
  { commune: 'Toucountouna',  departement: 'Atacora' },
  // Atlantique
  { commune: 'Abomey-Calavi', departement: 'Atlantique' },
  { commune: 'Allada',        departement: 'Atlantique' },
  { commune: 'Kpomassè',      departement: 'Atlantique' },
  { commune: 'Ouidah',        departement: 'Atlantique' },
  { commune: 'Sô-Ava',        departement: 'Atlantique' },
  { commune: 'Toffo',         departement: 'Atlantique' },
  { commune: 'Tori-Bossito',  departement: 'Atlantique' },
  { commune: 'Zè',            departement: 'Atlantique' },
  // Borgou
  { commune: 'Bembèrèkè',     departement: 'Borgou' },
  { commune: 'Kalalé',        departement: 'Borgou' },
  { commune: "N'Dali",        departement: 'Borgou' },
  { commune: 'Nikki',         departement: 'Borgou' },
  { commune: 'Parakou',       departement: 'Borgou' },
  { commune: 'Pèrèrè',        departement: 'Borgou' },
  { commune: 'Sinendé',       departement: 'Borgou' },
  { commune: 'Tchaourou',     departement: 'Borgou' },
  // Collines
  { commune: 'Bantè',         departement: 'Collines' },
  { commune: 'Dassa-Zoumè',   departement: 'Collines' },
  { commune: 'Glazoué',       departement: 'Collines' },
  { commune: 'Ouèssè',        departement: 'Collines' },
  { commune: 'Savalou',       departement: 'Collines' },
  { commune: 'Savè',          departement: 'Collines' },
  // Couffo
  { commune: 'Aplahoué',      departement: 'Couffo' },
  { commune: 'Djakotomey',    departement: 'Couffo' },
  { commune: 'Dogbo',         departement: 'Couffo' },
  { commune: 'Klouékanmè',    departement: 'Couffo' },
  { commune: 'Lalo',          departement: 'Couffo' },
  { commune: 'Toviklin',      departement: 'Couffo' },
  // Donga
  { commune: 'Bassila',       departement: 'Donga' },
  { commune: 'Copargo',       departement: 'Donga' },
  { commune: 'Djougou',       departement: 'Donga' },
  { commune: 'Ouaké',         departement: 'Donga' },
  // Littoral
  { commune: 'Cotonou',       departement: 'Littoral' },
  // Mono
  { commune: 'Athiémé',       departement: 'Mono' },
  { commune: 'Bopa',          departement: 'Mono' },
  { commune: 'Comè',          departement: 'Mono' },
  { commune: 'Grand-Popo',    departement: 'Mono' },
  { commune: 'Houéyogbé',     departement: 'Mono' },
  { commune: 'Lokossa',       departement: 'Mono' },
  // Ouémé
  { commune: 'Adjarra',           departement: 'Ouémé' },
  { commune: 'Adjohoun',          departement: 'Ouémé' },
  { commune: 'Aguégués',          departement: 'Ouémé' },
  { commune: 'Akpro-Missérété',   departement: 'Ouémé' },
  { commune: 'Avrankou',          departement: 'Ouémé' },
  { commune: 'Bonou',             departement: 'Ouémé' },
  { commune: 'Dangbo',            departement: 'Ouémé' },
  { commune: 'Porto-Novo',        departement: 'Ouémé' },
  { commune: 'Sèmè-Kpodji',       departement: 'Ouémé' },
  // Plateau
  { commune: 'Adja-Ouèrè',    departement: 'Plateau' },
  { commune: 'Ifangni',       departement: 'Plateau' },
  { commune: 'Kétou',         departement: 'Plateau' },
  { commune: 'Pobè',          departement: 'Plateau' },
  { commune: 'Sakété',        departement: 'Plateau' },
  // Zou
  { commune: 'Abomey',        departement: 'Zou' },
  { commune: 'Agbangnizoun',  departement: 'Zou' },
  { commune: 'Bohicon',       departement: 'Zou' },
  { commune: 'Covè',          departement: 'Zou' },
  { commune: 'Djidja',        departement: 'Zou' },
  { commune: 'Ouinhi',        departement: 'Zou' },
  { commune: 'Za-Kpota',      departement: 'Zou' },
  { commune: 'Zagnanado',     departement: 'Zou' },
  { commune: 'Zogbodomey',    departement: 'Zou' },
];

@Injectable()
export class DeliveryZonesService implements OnModuleInit {
  private readonly logger = new Logger(DeliveryZonesService.name);

  constructor(
    @InjectRepository(DeliveryZone)
    private readonly zoneRepo: Repository<DeliveryZone>,
  ) {}

  // Seed automatique au démarrage : n'insère que si la table est vide,
  // pour ne jamais écraser des frais déjà configurés par l'admin.
  async onModuleInit() {
    const count = await this.zoneRepo.count();
    if (count > 0) return;

    const zones = BENIN_COMMUNES.map((z) =>
      this.zoneRepo.create({
        commune:         z.commune,
        departement:     z.departement,
        fraisLivraison:  0,
        isActive:        true,
      }),
    );
    await this.zoneRepo.save(zones);
    this.logger.log(
      `${zones.length} communes initialisées dans delivery_zones (frais à 0, à configurer).`,
    );
  }

  async findAll() {
    return this.zoneRepo.find({
      order: { departement: 'ASC', commune: 'ASC' },
    });
  }

  async findOne(id: string) {
    const zone = await this.zoneRepo.findOne({ where: { id } });
    if (!zone) throw new NotFoundException('Zone de livraison introuvable');
    return zone;
  }

  async update(id: string, dto: UpdateDeliveryZoneDto) {
    const zone = await this.findOne(id);
    if (dto.fraisLivraison !== undefined) zone.fraisLivraison = dto.fraisLivraison;
    if (dto.isActive !== undefined) zone.isActive = dto.isActive;
    return this.zoneRepo.save(zone);
  }

  // Utilisé par OrdersService pour calculer les frais d'une commande.
  // Comparaison insensible à la casse/accents approximative (trim + lowercase) ;
  // si la commune ne correspond à aucune zone connue, retourne 0 plutôt que de
  // bloquer la création de la commande (à surveiller côté admin).
  async getFeeForCommune(commune: string): Promise<number> {
    if (!commune) return 0;
    const zones = await this.zoneRepo.find({ where: { isActive: true } });
    const target = commune.trim().toLowerCase();
    const match = zones.find((z) => z.commune.trim().toLowerCase() === target);
    if (!match) {
      this.logger.warn(
        `Aucune zone de livraison trouvée pour la commune "${commune}" — frais fixés à 0.`,
      );
      return 0;
    }
    return Number(match.fraisLivraison);
  }
}
