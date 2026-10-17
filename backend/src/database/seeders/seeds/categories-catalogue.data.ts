// FICHIER GÉNÉRÉ par generer_categories.py à partir de categories_arbre.txt.
// Ne le modifiez pas à la main : modifiez categories_arbre.txt puis relancez
// `python3 generer_categories.py` (le SQL et le seeder restent ainsi identiques).
//
// Arbre complet des catégories d'Asoukaa (3 niveaux maximum). Les catégories déjà
// présentes en base sont simplement ignorées par le seeder (contrôle par slug).

export interface CategorieNode {
  name: string;
  children?: CategorieNode[];
}

export const CATEGORIES_CATALOGUE: CategorieNode[] = [
  {
    "name": "Alimentation",
    "children": [
      { "name": "MAIS" },
      { "name": "Riz" },
      {
        "name": "Farines, gari et semoules",
        "children": [
          { "name": "Gari" },
          { "name": "Tapioca" },
          { "name": "Semoule et couscous" },
          { "name": "Farine de blé" },
        ]
      },
      { "name": "Igname et tubercules" },
      { "name": "Haricots et légumineuses" },
      { "name": "Huiles alimentaires" },
      { "name": "Épices et condiments" },
      { "name": "Fruits et légumes" },
      {
        "name": "Viandes et poissons",
        "children": [
          { "name": "Poisson frais" },
          { "name": "Poisson fumé et séché" },
          { "name": "Viande de bovins et ovins" },
          { "name": "Volaille et oeufs" },
        ]
      },
      { "name": "Boissons" },
      {
        "name": "Produits du terroir",
        "children": [
          { "name": "Afitin et soumbala" },
          { "name": "Miel" },
          { "name": "Noix de cajou" },
          { "name": "Arachides" },
          { "name": "Gombo et feuilles séchées" },
        ]
      },
      { "name": "Snacks et biscuits" },
    ]
  },
  {
    "name": "Beauté",
    "children": [
      { "name": "Soins du visage" },
      { "name": "Soins du corps" },
      {
        "name": "Soins des cheveux",
        "children": [
          { "name": "Shampoings et après-shampoings" },
          { "name": "Huiles et beurres capillaires" },
          { "name": "Perruques et tissages" },
          { "name": "Mèches et rajouts" },
        ]
      },
      { "name": "Maquillage" },
      { "name": "Parfums et déodorants" },
      {
        "name": "Karité et produits naturels",
        "children": [
          { "name": "Beurre de karité" },
          { "name": "Savon noir africain" },
          { "name": "Huiles végétales naturelles" },
        ]
      },
      { "name": "Hygiène et bain" },
      { "name": "Soins des ongles" },
      { "name": "Soins pour hommes" },
      { "name": "Matériel de coiffure et de beauté" },
    ]
  },
  {
    "name": "Électronique",
    "children": [
      { "name": "Téléviseurs et vidéo" },
      {
        "name": "Audio et son",
        "children": [
          { "name": "Enceintes et haut-parleurs" },
          { "name": "Casques et écouteurs" },
          { "name": "Radios" },
        ]
      },
      { "name": "Appareils photo et caméras" },
      { "name": "Jeux vidéo et consoles" },
      { "name": "Chargeurs et câbles" },
      { "name": "Sécurité et surveillance" },
      { "name": "Objets connectés" },
      { "name": "Décodeurs et antennes" },
    ]
  },
  {
    "name": "Jouets",
    "children": [
      { "name": "Jouets d'éveil" },
      { "name": "Poupées et peluches" },
      { "name": "Voitures et véhicules miniatures" },
      { "name": "Jeux de construction" },
      { "name": "Jeux de société et puzzles" },
      { "name": "Jeux d'extérieur" },
      { "name": "Jouets éducatifs" },
      { "name": "Déguisements" },
      { "name": "Jouets électroniques et télécommandés" },
    ]
  },
  {
    "name": "Livres",
    "children": [
      { "name": "Romans et littérature" },
      { "name": "Livres scolaires" },
      { "name": "Livres universitaires" },
      { "name": "Bandes dessinées et mangas" },
      { "name": "Livres pour enfants" },
      { "name": "Religion et spiritualité" },
      { "name": "Développement personnel" },
      { "name": "Dictionnaires et langues" },
      { "name": "Économie et gestion" },
    ]
  },
  {
    "name": "Maison",
    "children": [
      { "name": "Meubles" },
      { "name": "Décoration" },
      { "name": "Literie et linge de maison" },
      { "name": "Moustiquaires" },
      { "name": "Rideaux et tapis" },
      { "name": "Éclairage et luminaires" },
      { "name": "Salle de bain" },
      { "name": "Jardin et extérieur" },
      { "name": "Produits d'entretien" },
      { "name": "Rangement et organisation" },
    ]
  },
  {
    "name": "Mode",
    "children": [
      { "name": "Mode femme" },
      { "name": "Mode homme" },
      { "name": "Mode enfant" },
      {
        "name": "Tenues traditionnelles",
        "children": [
          { "name": "Boubous et grands boubous" },
          { "name": "Complets bazin" },
          { "name": "Kaba et robes en pagne" },
          { "name": "Tenues en wax" },
        ]
      },
      { "name": "Lingerie et sous-vêtements" },
      { "name": "Accessoires de mode" },
      { "name": "Uniformes et vêtements de travail" },
      { "name": "Friperie" },
    ]
  },
  {
    "name": "Sports",
    "children": [
      { "name": "Gym" },
      { "name": "Padel" },
      { "name": "Football" },
      { "name": "Basketball" },
      { "name": "Course et athlétisme" },
      { "name": "Musculation et haltères" },
      { "name": "Arts martiaux" },
      { "name": "Cyclisme" },
      { "name": "Natation" },
      { "name": "Vêtements de sport" },
      { "name": "Camping et randonnée" },
    ]
  },
  {
    "name": "Téléphones et tablettes",
    "children": [
      { "name": "Smartphones" },
      { "name": "Téléphones basiques" },
      { "name": "Téléphones reconditionnés" },
      { "name": "Tablettes" },
      { "name": "Accessoires téléphones" },
    ]
  },
  {
    "name": "Informatique",
    "children": [
      { "name": "Ordinateurs portables" },
      { "name": "Ordinateurs de bureau" },
      { "name": "Écrans et moniteurs" },
      { "name": "Imprimantes et scanners" },
      { "name": "Stockage" },
      { "name": "Claviers et souris" },
      { "name": "Routeurs et modems" },
      { "name": "Composants informatiques" },
      { "name": "Sacoches d'ordinateur" },
    ]
  },
  {
    "name": "Électroménager",
    "children": [
      { "name": "Réfrigérateurs et congélateurs" },
      { "name": "Climatiseurs et ventilateurs" },
      { "name": "Machines à laver" },
      { "name": "Cuisinières et gazinières" },
      { "name": "Petit électroménager" },
      { "name": "Fontaines à eau" },
      { "name": "Aspirateurs" },
      { "name": "Réchauds et accessoires gaz" },
    ]
  },
  {
    "name": "Bébé et maternité",
    "children": [
      { "name": "Vêtements de bébé" },
      { "name": "Couches et lingettes" },
      { "name": "Alimentation de bébé" },
      { "name": "Poussettes et porte-bébés" },
      { "name": "Berceaux et lits bébé" },
      { "name": "Bain et soins de bébé" },
      { "name": "Articles de maternité" },
      { "name": "Babyphones et sécurité enfant" },
    ]
  },
  {
    "name": "Santé et bien-être",
    "children": [
      { "name": "Vitamines et compléments" },
      { "name": "Premiers soins" },
      { "name": "Appareils de mesure santé" },
      { "name": "Hygiène féminine" },
      { "name": "Soins dentaires" },
      { "name": "Tisanes et plantes" },
      { "name": "Protection anti-moustiques" },
    ]
  },
  {
    "name": "Bricolage et outillage",
    "children": [
      { "name": "Outils à main" },
      { "name": "Outillage électrique" },
      { "name": "Quincaillerie" },
      { "name": "Plomberie" },
      { "name": "Électricité" },
      { "name": "Peinture et revêtements" },
      {
        "name": "Matériaux de construction",
        "children": [
          { "name": "Carrelage" },
          { "name": "Tôles et toitures" },
          { "name": "Portes et fenêtres" },
          { "name": "Ciment et sable" },
        ]
      },
      { "name": "Sécurité de chantier" },
      { "name": "Échelles et escabeaux" },
      { "name": "Soudure et accessoires" },
    ]
  },
  {
    "name": "Automobile et moto",
    "children": [
      { "name": "Pièces détachées auto" },
      { "name": "Pneus et jantes" },
      { "name": "Huiles et lubrifiants" },
      { "name": "Accessoires auto" },
      { "name": "Batteries de véhicules" },
      { "name": "Motos et scooters" },
      { "name": "Pièces moto" },
      { "name": "Casques et équipements de motard" },
      { "name": "Autoradios et GPS" },
      { "name": "Entretien et lavage auto" },
    ]
  },
  {
    "name": "Agriculture et élevage",
    "children": [
      { "name": "Semences et plants" },
      { "name": "Engrais et fertilisants" },
      { "name": "Matériel agricole" },
      { "name": "Irrigation et arrosage" },
      { "name": "Alimentation animale" },
      { "name": "Matériel d'élevage" },
      { "name": "Apiculture" },
      { "name": "Pisciculture" },
      { "name": "Machines de transformation" },
    ]
  },
  {
    "name": "Animaux de compagnie",
    "children": [
      { "name": "Nourriture pour animaux" },
      { "name": "Accessoires pour chiens" },
      { "name": "Accessoires pour chats" },
      { "name": "Oiseaux et cages" },
      { "name": "Aquariums et accessoires" },
      { "name": "Hygiène et soins animaux" },
      { "name": "Couchages pour animaux" },
    ]
  },
  {
    "name": "Papeterie et fournitures",
    "children": [
      { "name": "Cahiers et carnets" },
      { "name": "Stylos et écriture" },
      { "name": "Fournitures scolaires" },
      { "name": "Fournitures de bureau" },
      { "name": "Papier et rames" },
      { "name": "Classement et archivage" },
      { "name": "Dessin et peinture" },
      { "name": "Matériel de classe" },
    ]
  },
  {
    "name": "Instruments de musique",
    "children": [
      { "name": "Guitares et basses" },
      { "name": "Claviers et pianos" },
      { "name": "Batteries et percussions" },
      {
        "name": "Percussions africaines",
        "children": [
          { "name": "Djembés" },
          { "name": "Tam-tams" },
          { "name": "Balafons" },
          { "name": "Calebasses et shékérés" },
        ]
      },
      { "name": "Instruments à vent" },
      { "name": "Violons et instruments à cordes" },
      { "name": "Sonorisation" },
      { "name": "Studio et enregistrement" },
      { "name": "Accessoires musicaux" },
    ]
  },
  {
    "name": "Art et artisanat",
    "children": [
      { "name": "Sculptures et statuettes" },
      { "name": "Masques décoratifs" },
      { "name": "Peintures et tableaux" },
      { "name": "Poterie et céramique" },
      { "name": "Vannerie et paniers" },
      { "name": "Objets en bois" },
      { "name": "Batik et teinture" },
      { "name": "Calebasses et objets décorés" },
      { "name": "Bronzes et objets en laiton" },
      { "name": "Appliqués et tentures d'Abomey" },
      { "name": "Loisirs créatifs" },
    ]
  },
  {
    "name": "Cuisine et ustensiles",
    "children": [
      { "name": "Casseroles et marmites" },
      { "name": "Poêles et plats" },
      { "name": "Vaisselle et couverts" },
      { "name": "Couteaux et ustensiles" },
      { "name": "Mortiers et ustensiles traditionnels" },
      { "name": "Boîtes de conservation" },
      { "name": "Thermos et glacières" },
      { "name": "Linge de table" },
      { "name": "Bassines, seaux et bidons" },
    ]
  },
  {
    "name": "Chaussures et maroquinerie",
    "children": [
      { "name": "Chaussures femme" },
      { "name": "Chaussures homme" },
      { "name": "Chaussures enfant" },
      { "name": "Sandales et tongs" },
      { "name": "Baskets" },
      { "name": "Sacs à main" },
      { "name": "Sacs à dos" },
      { "name": "Valises et bagages" },
      { "name": "Portefeuilles et petite maroquinerie" },
    ]
  },
  {
    "name": "Bijoux et montres",
    "children": [
      { "name": "Colliers et pendentifs" },
      { "name": "Bracelets" },
      { "name": "Bagues" },
      { "name": "Boucles d'oreilles" },
      { "name": "Chaînes et gourmettes" },
      { "name": "Montres homme" },
      { "name": "Montres femme" },
      { "name": "Perles et bijoux traditionnels" },
      { "name": "Bijoux en or et argent" },
      { "name": "Parures et coffrets" },
    ]
  },
  {
    "name": "Pagnes et tissus",
    "children": [
      { "name": "Wax" },
      { "name": "Bazin et brocart" },
      { "name": "Dentelle et tulle" },
      { "name": "Pagnes tissés et bogolan" },
      { "name": "Tissus de coton" },
      { "name": "Satin, soie et velours" },
      { "name": "Tissus d'ameublement" },
      { "name": "Fournitures de couture" },
      { "name": "Machines à coudre" },
    ]
  },
  {
    "name": "Mariage et événements",
    "children": [
      { "name": "Décoration de fête" },
      {
        "name": "Tenues de mariage",
        "children": [
          { "name": "Robes de mariée" },
          { "name": "Costumes et smokings" },
          { "name": "Tenues de cortège" },
        ]
      },
      { "name": "Cadeaux et coffrets" },
      { "name": "Faire-part et papeterie événementielle" },
      { "name": "Vaisselle jetable" },
      { "name": "Chapiteaux, bâches et chaises" },
    ]
  },
  {
    "name": "Énergie solaire",
    "children": [
      { "name": "Panneaux solaires" },
      { "name": "Batteries solaires" },
      { "name": "Onduleurs et régulateurs" },
      { "name": "Kits solaires complets" },
      { "name": "Lampes et lanternes solaires" },
      { "name": "Groupes électrogènes" },
      { "name": "Stabilisateurs de tension" },
      { "name": "Accessoires d'installation solaire" },
    ]
  },
];
