-- =====================================================================
-- ASOUKAA : insertion du catalogue de catégories (293 lignes dans le catalogue)
-- FICHIER GÉNÉRÉ par generer_categories.py (source : categories_arbre.txt).
--
-- COMMENT L'UTILISER (pgAdmin : Query Tool, ou psql -f) :
--   1) LANCE D'ABORD L'APERÇU SEUL : sélectionne tout le texte depuis
--      « PARTIE 1 » jusqu'à la fin de « PARTIE 2 : APERÇU », puis exécute
--      (F5 dans pgAdmin). Rien n'est écrit dans la table categories ;
--      seule une table temporaire de travail est créée dans ta session.
--      Regarde le résultat : les lignes « NOUVELLE » seront ajoutées,
--      « EXISTE_DEJA » seront ignorées.
--   2) PUIS EXÉCUTE LE SCRIPT ENTIER (Ctrl+A puis F5). Il est ré-exécutable
--      à volonté : il n'ajoute que ce qui manque, ne crée jamais de doublon
--      et ne modifie ni ne supprime aucune catégorie existante
--      (aucun UPDATE, aucun DELETE sur categories).
--   Les nouvelles catégories n'ont pas d'image (imageUrl NULL) : ajoute-les
--   ensuite depuis le site admin.
--
-- Règles de sécurité appliquées à chaque ligne :
--   - ignorée si le slug existe déjà dans categories ;
--   - ignorée si une catégorie du MÊME parent porte déjà le même nom
--     (comparaison insensible à la casse) ;
--   - le parent est retrouvé par son slug ; s'il est introuvable (ou de
--     mauvais niveau), la ligne est IGNORÉE (jamais insérée à la racine) ;
--   - toute l'insertion est dans UNE transaction (BEGIN ... COMMIT) : en cas
--     d'erreur, rien n'est ajouté (psql : ajoute -v ON_ERROR_STOP=1).
-- =====================================================================

-- ---------------------------------------------------------------------
-- PARTIE 1 : préparation (table temporaire + extension). N'écrit pas
-- dans categories.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DROP TABLE IF EXISTS pg_temp.tmp_plan;
DROP TABLE IF EXISTS pg_temp.tmp_cat;

CREATE TEMP TABLE tmp_cat (
  parent_slug varchar(255),
  name        varchar(255) NOT NULL,
  slug        varchar(255) NOT NULL,
  level       int          NOT NULL,
  sort_order  int          NOT NULL
);

INSERT INTO tmp_cat (parent_slug, name, slug, level, sort_order) VALUES
  (NULL, 'Alimentation', 'alimentation', 1, 0),
  ('alimentation', 'MAIS', 'mais', 2, 0),
  ('alimentation', 'Riz', 'riz', 2, 1),
  ('alimentation', 'Farines, gari et semoules', 'farines-gari-et-semoules', 2, 2),
  ('farines-gari-et-semoules', 'Gari', 'gari', 3, 0),
  ('farines-gari-et-semoules', 'Tapioca', 'tapioca', 3, 1),
  ('farines-gari-et-semoules', 'Semoule et couscous', 'semoule-et-couscous', 3, 2),
  ('farines-gari-et-semoules', 'Farine de blé', 'farine-de-ble', 3, 3),
  ('alimentation', 'Igname et tubercules', 'igname-et-tubercules', 2, 3),
  ('alimentation', 'Haricots et légumineuses', 'haricots-et-legumineuses', 2, 4),
  ('alimentation', 'Huiles alimentaires', 'huiles-alimentaires', 2, 5),
  ('alimentation', 'Épices et condiments', 'epices-et-condiments', 2, 6),
  ('alimentation', 'Fruits et légumes', 'fruits-et-legumes', 2, 7),
  ('alimentation', 'Viandes et poissons', 'viandes-et-poissons', 2, 8),
  ('viandes-et-poissons', 'Poisson frais', 'poisson-frais', 3, 0),
  ('viandes-et-poissons', 'Poisson fumé et séché', 'poisson-fume-et-seche', 3, 1),
  ('viandes-et-poissons', 'Viande de bovins et ovins', 'viande-de-bovins-et-ovins', 3, 2),
  ('viandes-et-poissons', 'Volaille et oeufs', 'volaille-et-oeufs', 3, 3),
  ('alimentation', 'Boissons', 'boissons', 2, 9),
  ('alimentation', 'Produits du terroir', 'produits-du-terroir', 2, 10),
  ('produits-du-terroir', 'Afitin et soumbala', 'afitin-et-soumbala', 3, 0),
  ('produits-du-terroir', 'Miel', 'miel', 3, 1),
  ('produits-du-terroir', 'Noix de cajou', 'noix-de-cajou', 3, 2),
  ('produits-du-terroir', 'Arachides', 'arachides', 3, 3),
  ('produits-du-terroir', 'Gombo et feuilles séchées', 'gombo-et-feuilles-sechees', 3, 4),
  ('alimentation', 'Snacks et biscuits', 'snacks-et-biscuits', 2, 11),
  (NULL, 'Beauté', 'beaute', 1, 1),
  ('beaute', 'Soins du visage', 'soins-du-visage', 2, 0),
  ('beaute', 'Soins du corps', 'soins-du-corps', 2, 1),
  ('beaute', 'Soins des cheveux', 'soins-des-cheveux', 2, 2),
  ('soins-des-cheveux', 'Shampoings et après-shampoings', 'shampoings-et-apres-shampoings', 3, 0),
  ('soins-des-cheveux', 'Huiles et beurres capillaires', 'huiles-et-beurres-capillaires', 3, 1),
  ('soins-des-cheveux', 'Perruques et tissages', 'perruques-et-tissages', 3, 2),
  ('soins-des-cheveux', 'Mèches et rajouts', 'meches-et-rajouts', 3, 3),
  ('beaute', 'Maquillage', 'maquillage', 2, 3),
  ('beaute', 'Parfums et déodorants', 'parfums-et-deodorants', 2, 4),
  ('beaute', 'Karité et produits naturels', 'karite-et-produits-naturels', 2, 5),
  ('karite-et-produits-naturels', 'Beurre de karité', 'beurre-de-karite', 3, 0),
  ('karite-et-produits-naturels', 'Savon noir africain', 'savon-noir-africain', 3, 1),
  ('karite-et-produits-naturels', 'Huiles végétales naturelles', 'huiles-vegetales-naturelles', 3, 2),
  ('beaute', 'Hygiène et bain', 'hygiene-et-bain', 2, 6),
  ('beaute', 'Soins des ongles', 'soins-des-ongles', 2, 7),
  ('beaute', 'Soins pour hommes', 'soins-pour-hommes', 2, 8),
  ('beaute', 'Matériel de coiffure et de beauté', 'materiel-de-coiffure-et-de-beaute', 2, 9),
  (NULL, 'Électronique', 'electronique', 1, 2),
  ('electronique', 'Téléviseurs et vidéo', 'televiseurs-et-video', 2, 0),
  ('electronique', 'Audio et son', 'audio-et-son', 2, 1),
  ('audio-et-son', 'Enceintes et haut-parleurs', 'enceintes-et-haut-parleurs', 3, 0),
  ('audio-et-son', 'Casques et écouteurs', 'casques-et-ecouteurs', 3, 1),
  ('audio-et-son', 'Radios', 'radios', 3, 2),
  ('electronique', 'Appareils photo et caméras', 'appareils-photo-et-cameras', 2, 2),
  ('electronique', 'Jeux vidéo et consoles', 'jeux-video-et-consoles', 2, 3),
  ('electronique', 'Chargeurs et câbles', 'chargeurs-et-cables', 2, 4),
  ('electronique', 'Sécurité et surveillance', 'securite-et-surveillance', 2, 5),
  ('electronique', 'Objets connectés', 'objets-connectes', 2, 6),
  ('electronique', 'Décodeurs et antennes', 'decodeurs-et-antennes', 2, 7),
  (NULL, 'Jouets', 'jouets', 1, 3),
  ('jouets', 'Jouets d''éveil', 'jouets-deveil', 2, 0),
  ('jouets', 'Poupées et peluches', 'poupees-et-peluches', 2, 1),
  ('jouets', 'Voitures et véhicules miniatures', 'voitures-et-vehicules-miniatures', 2, 2),
  ('jouets', 'Jeux de construction', 'jeux-de-construction', 2, 3),
  ('jouets', 'Jeux de société et puzzles', 'jeux-de-societe-et-puzzles', 2, 4),
  ('jouets', 'Jeux d''extérieur', 'jeux-dexterieur', 2, 5),
  ('jouets', 'Jouets éducatifs', 'jouets-educatifs', 2, 6),
  ('jouets', 'Déguisements', 'deguisements', 2, 7),
  ('jouets', 'Jouets électroniques et télécommandés', 'jouets-electroniques-et-telecommandes', 2, 8),
  (NULL, 'Livres', 'livres', 1, 4),
  ('livres', 'Romans et littérature', 'romans-et-litterature', 2, 0),
  ('livres', 'Livres scolaires', 'livres-scolaires', 2, 1),
  ('livres', 'Livres universitaires', 'livres-universitaires', 2, 2),
  ('livres', 'Bandes dessinées et mangas', 'bandes-dessinees-et-mangas', 2, 3),
  ('livres', 'Livres pour enfants', 'livres-pour-enfants', 2, 4),
  ('livres', 'Religion et spiritualité', 'religion-et-spiritualite', 2, 5),
  ('livres', 'Développement personnel', 'developpement-personnel', 2, 6),
  ('livres', 'Dictionnaires et langues', 'dictionnaires-et-langues', 2, 7),
  ('livres', 'Économie et gestion', 'economie-et-gestion', 2, 8),
  (NULL, 'Maison', 'maison', 1, 5),
  ('maison', 'Meubles', 'meubles', 2, 0),
  ('maison', 'Décoration', 'decoration', 2, 1),
  ('maison', 'Literie et linge de maison', 'literie-et-linge-de-maison', 2, 2),
  ('maison', 'Moustiquaires', 'moustiquaires', 2, 3),
  ('maison', 'Rideaux et tapis', 'rideaux-et-tapis', 2, 4),
  ('maison', 'Éclairage et luminaires', 'eclairage-et-luminaires', 2, 5),
  ('maison', 'Salle de bain', 'salle-de-bain', 2, 6),
  ('maison', 'Jardin et extérieur', 'jardin-et-exterieur', 2, 7),
  ('maison', 'Produits d''entretien', 'produits-dentretien', 2, 8),
  ('maison', 'Rangement et organisation', 'rangement-et-organisation', 2, 9),
  (NULL, 'Mode', 'mode', 1, 6),
  ('mode', 'Mode femme', 'mode-femme', 2, 0),
  ('mode', 'Mode homme', 'mode-homme', 2, 1),
  ('mode', 'Mode enfant', 'mode-enfant', 2, 2),
  ('mode', 'Tenues traditionnelles', 'tenues-traditionnelles', 2, 3),
  ('tenues-traditionnelles', 'Boubous et grands boubous', 'boubous-et-grands-boubous', 3, 0),
  ('tenues-traditionnelles', 'Complets bazin', 'complets-bazin', 3, 1),
  ('tenues-traditionnelles', 'Kaba et robes en pagne', 'kaba-et-robes-en-pagne', 3, 2),
  ('tenues-traditionnelles', 'Tenues en wax', 'tenues-en-wax', 3, 3),
  ('mode', 'Lingerie et sous-vêtements', 'lingerie-et-sous-vetements', 2, 4),
  ('mode', 'Accessoires de mode', 'accessoires-de-mode', 2, 5),
  ('mode', 'Uniformes et vêtements de travail', 'uniformes-et-vetements-de-travail', 2, 6),
  ('mode', 'Friperie', 'friperie', 2, 7),
  (NULL, 'Sports', 'sports', 1, 7),
  ('sports', 'Gym', 'gym', 2, 0),
  ('sports', 'Padel', 'padel', 2, 1),
  ('sports', 'Football', 'football', 2, 2),
  ('sports', 'Basketball', 'basketball', 2, 3),
  ('sports', 'Course et athlétisme', 'course-et-athletisme', 2, 4),
  ('sports', 'Musculation et haltères', 'musculation-et-halteres', 2, 5),
  ('sports', 'Arts martiaux', 'arts-martiaux', 2, 6),
  ('sports', 'Cyclisme', 'cyclisme', 2, 7),
  ('sports', 'Natation', 'natation', 2, 8),
  ('sports', 'Vêtements de sport', 'vetements-de-sport', 2, 9),
  ('sports', 'Camping et randonnée', 'camping-et-randonnee', 2, 10),
  (NULL, 'Téléphones et tablettes', 'telephones-et-tablettes', 1, 8),
  ('telephones-et-tablettes', 'Smartphones', 'smartphones', 2, 0),
  ('telephones-et-tablettes', 'Téléphones basiques', 'telephones-basiques', 2, 1),
  ('telephones-et-tablettes', 'Téléphones reconditionnés', 'telephones-reconditionnes', 2, 2),
  ('telephones-et-tablettes', 'Tablettes', 'tablettes', 2, 3),
  ('telephones-et-tablettes', 'Accessoires téléphones', 'accessoires-telephones', 2, 4),
  (NULL, 'Informatique', 'informatique', 1, 9),
  ('informatique', 'Ordinateurs portables', 'ordinateurs-portables', 2, 0),
  ('informatique', 'Ordinateurs de bureau', 'ordinateurs-de-bureau', 2, 1),
  ('informatique', 'Écrans et moniteurs', 'ecrans-et-moniteurs', 2, 2),
  ('informatique', 'Imprimantes et scanners', 'imprimantes-et-scanners', 2, 3),
  ('informatique', 'Stockage', 'stockage', 2, 4),
  ('informatique', 'Claviers et souris', 'claviers-et-souris', 2, 5),
  ('informatique', 'Routeurs et modems', 'routeurs-et-modems', 2, 6),
  ('informatique', 'Composants informatiques', 'composants-informatiques', 2, 7),
  ('informatique', 'Sacoches d''ordinateur', 'sacoches-dordinateur', 2, 8),
  (NULL, 'Électroménager', 'electromenager', 1, 10),
  ('electromenager', 'Réfrigérateurs et congélateurs', 'refrigerateurs-et-congelateurs', 2, 0),
  ('electromenager', 'Climatiseurs et ventilateurs', 'climatiseurs-et-ventilateurs', 2, 1),
  ('electromenager', 'Machines à laver', 'machines-a-laver', 2, 2),
  ('electromenager', 'Cuisinières et gazinières', 'cuisinieres-et-gazinieres', 2, 3),
  ('electromenager', 'Petit électroménager', 'petit-electromenager', 2, 4),
  ('electromenager', 'Fontaines à eau', 'fontaines-a-eau', 2, 5),
  ('electromenager', 'Aspirateurs', 'aspirateurs', 2, 6),
  ('electromenager', 'Réchauds et accessoires gaz', 'rechauds-et-accessoires-gaz', 2, 7),
  (NULL, 'Bébé et maternité', 'bebe-et-maternite', 1, 11),
  ('bebe-et-maternite', 'Vêtements de bébé', 'vetements-de-bebe', 2, 0),
  ('bebe-et-maternite', 'Couches et lingettes', 'couches-et-lingettes', 2, 1),
  ('bebe-et-maternite', 'Alimentation de bébé', 'alimentation-de-bebe', 2, 2),
  ('bebe-et-maternite', 'Poussettes et porte-bébés', 'poussettes-et-porte-bebes', 2, 3),
  ('bebe-et-maternite', 'Berceaux et lits bébé', 'berceaux-et-lits-bebe', 2, 4),
  ('bebe-et-maternite', 'Bain et soins de bébé', 'bain-et-soins-de-bebe', 2, 5),
  ('bebe-et-maternite', 'Articles de maternité', 'articles-de-maternite', 2, 6),
  ('bebe-et-maternite', 'Babyphones et sécurité enfant', 'babyphones-et-securite-enfant', 2, 7),
  (NULL, 'Santé et bien-être', 'sante-et-bien-etre', 1, 12),
  ('sante-et-bien-etre', 'Vitamines et compléments', 'vitamines-et-complements', 2, 0),
  ('sante-et-bien-etre', 'Premiers soins', 'premiers-soins', 2, 1),
  ('sante-et-bien-etre', 'Appareils de mesure santé', 'appareils-de-mesure-sante', 2, 2),
  ('sante-et-bien-etre', 'Hygiène féminine', 'hygiene-feminine', 2, 3),
  ('sante-et-bien-etre', 'Soins dentaires', 'soins-dentaires', 2, 4),
  ('sante-et-bien-etre', 'Tisanes et plantes', 'tisanes-et-plantes', 2, 5),
  ('sante-et-bien-etre', 'Protection anti-moustiques', 'protection-anti-moustiques', 2, 6),
  (NULL, 'Bricolage et outillage', 'bricolage-et-outillage', 1, 13),
  ('bricolage-et-outillage', 'Outils à main', 'outils-a-main', 2, 0),
  ('bricolage-et-outillage', 'Outillage électrique', 'outillage-electrique', 2, 1),
  ('bricolage-et-outillage', 'Quincaillerie', 'quincaillerie', 2, 2),
  ('bricolage-et-outillage', 'Plomberie', 'plomberie', 2, 3),
  ('bricolage-et-outillage', 'Électricité', 'electricite', 2, 4),
  ('bricolage-et-outillage', 'Peinture et revêtements', 'peinture-et-revetements', 2, 5),
  ('bricolage-et-outillage', 'Matériaux de construction', 'materiaux-de-construction', 2, 6),
  ('materiaux-de-construction', 'Carrelage', 'carrelage', 3, 0),
  ('materiaux-de-construction', 'Tôles et toitures', 'toles-et-toitures', 3, 1),
  ('materiaux-de-construction', 'Portes et fenêtres', 'portes-et-fenetres', 3, 2),
  ('materiaux-de-construction', 'Ciment et sable', 'ciment-et-sable', 3, 3),
  ('bricolage-et-outillage', 'Sécurité de chantier', 'securite-de-chantier', 2, 7),
  ('bricolage-et-outillage', 'Échelles et escabeaux', 'echelles-et-escabeaux', 2, 8),
  ('bricolage-et-outillage', 'Soudure et accessoires', 'soudure-et-accessoires', 2, 9),
  (NULL, 'Automobile et moto', 'automobile-et-moto', 1, 14),
  ('automobile-et-moto', 'Pièces détachées auto', 'pieces-detachees-auto', 2, 0),
  ('automobile-et-moto', 'Pneus et jantes', 'pneus-et-jantes', 2, 1),
  ('automobile-et-moto', 'Huiles et lubrifiants', 'huiles-et-lubrifiants', 2, 2),
  ('automobile-et-moto', 'Accessoires auto', 'accessoires-auto', 2, 3),
  ('automobile-et-moto', 'Batteries de véhicules', 'batteries-de-vehicules', 2, 4),
  ('automobile-et-moto', 'Motos et scooters', 'motos-et-scooters', 2, 5),
  ('automobile-et-moto', 'Pièces moto', 'pieces-moto', 2, 6),
  ('automobile-et-moto', 'Casques et équipements de motard', 'casques-et-equipements-de-motard', 2, 7),
  ('automobile-et-moto', 'Autoradios et GPS', 'autoradios-et-gps', 2, 8),
  ('automobile-et-moto', 'Entretien et lavage auto', 'entretien-et-lavage-auto', 2, 9),
  (NULL, 'Agriculture et élevage', 'agriculture-et-elevage', 1, 15),
  ('agriculture-et-elevage', 'Semences et plants', 'semences-et-plants', 2, 0),
  ('agriculture-et-elevage', 'Engrais et fertilisants', 'engrais-et-fertilisants', 2, 1),
  ('agriculture-et-elevage', 'Matériel agricole', 'materiel-agricole', 2, 2),
  ('agriculture-et-elevage', 'Irrigation et arrosage', 'irrigation-et-arrosage', 2, 3),
  ('agriculture-et-elevage', 'Alimentation animale', 'alimentation-animale', 2, 4),
  ('agriculture-et-elevage', 'Matériel d''élevage', 'materiel-delevage', 2, 5),
  ('agriculture-et-elevage', 'Apiculture', 'apiculture', 2, 6),
  ('agriculture-et-elevage', 'Pisciculture', 'pisciculture', 2, 7),
  ('agriculture-et-elevage', 'Machines de transformation', 'machines-de-transformation', 2, 8),
  (NULL, 'Animaux de compagnie', 'animaux-de-compagnie', 1, 16),
  ('animaux-de-compagnie', 'Nourriture pour animaux', 'nourriture-pour-animaux', 2, 0),
  ('animaux-de-compagnie', 'Accessoires pour chiens', 'accessoires-pour-chiens', 2, 1),
  ('animaux-de-compagnie', 'Accessoires pour chats', 'accessoires-pour-chats', 2, 2),
  ('animaux-de-compagnie', 'Oiseaux et cages', 'oiseaux-et-cages', 2, 3),
  ('animaux-de-compagnie', 'Aquariums et accessoires', 'aquariums-et-accessoires', 2, 4),
  ('animaux-de-compagnie', 'Hygiène et soins animaux', 'hygiene-et-soins-animaux', 2, 5),
  ('animaux-de-compagnie', 'Couchages pour animaux', 'couchages-pour-animaux', 2, 6),
  (NULL, 'Papeterie et fournitures', 'papeterie-et-fournitures', 1, 17),
  ('papeterie-et-fournitures', 'Cahiers et carnets', 'cahiers-et-carnets', 2, 0),
  ('papeterie-et-fournitures', 'Stylos et écriture', 'stylos-et-ecriture', 2, 1),
  ('papeterie-et-fournitures', 'Fournitures scolaires', 'fournitures-scolaires', 2, 2),
  ('papeterie-et-fournitures', 'Fournitures de bureau', 'fournitures-de-bureau', 2, 3),
  ('papeterie-et-fournitures', 'Papier et rames', 'papier-et-rames', 2, 4),
  ('papeterie-et-fournitures', 'Classement et archivage', 'classement-et-archivage', 2, 5),
  ('papeterie-et-fournitures', 'Dessin et peinture', 'dessin-et-peinture', 2, 6),
  ('papeterie-et-fournitures', 'Matériel de classe', 'materiel-de-classe', 2, 7),
  (NULL, 'Instruments de musique', 'instruments-de-musique', 1, 18),
  ('instruments-de-musique', 'Guitares et basses', 'guitares-et-basses', 2, 0),
  ('instruments-de-musique', 'Claviers et pianos', 'claviers-et-pianos', 2, 1),
  ('instruments-de-musique', 'Batteries et percussions', 'batteries-et-percussions', 2, 2),
  ('instruments-de-musique', 'Percussions africaines', 'percussions-africaines', 2, 3),
  ('percussions-africaines', 'Djembés', 'djembes', 3, 0),
  ('percussions-africaines', 'Tam-tams', 'tam-tams', 3, 1),
  ('percussions-africaines', 'Balafons', 'balafons', 3, 2),
  ('percussions-africaines', 'Calebasses et shékérés', 'calebasses-et-shekeres', 3, 3),
  ('instruments-de-musique', 'Instruments à vent', 'instruments-a-vent', 2, 4),
  ('instruments-de-musique', 'Violons et instruments à cordes', 'violons-et-instruments-a-cordes', 2, 5),
  ('instruments-de-musique', 'Sonorisation', 'sonorisation', 2, 6),
  ('instruments-de-musique', 'Studio et enregistrement', 'studio-et-enregistrement', 2, 7),
  ('instruments-de-musique', 'Accessoires musicaux', 'accessoires-musicaux', 2, 8),
  (NULL, 'Art et artisanat', 'art-et-artisanat', 1, 19),
  ('art-et-artisanat', 'Sculptures et statuettes', 'sculptures-et-statuettes', 2, 0),
  ('art-et-artisanat', 'Masques décoratifs', 'masques-decoratifs', 2, 1),
  ('art-et-artisanat', 'Peintures et tableaux', 'peintures-et-tableaux', 2, 2),
  ('art-et-artisanat', 'Poterie et céramique', 'poterie-et-ceramique', 2, 3),
  ('art-et-artisanat', 'Vannerie et paniers', 'vannerie-et-paniers', 2, 4),
  ('art-et-artisanat', 'Objets en bois', 'objets-en-bois', 2, 5),
  ('art-et-artisanat', 'Batik et teinture', 'batik-et-teinture', 2, 6),
  ('art-et-artisanat', 'Calebasses et objets décorés', 'calebasses-et-objets-decores', 2, 7),
  ('art-et-artisanat', 'Bronzes et objets en laiton', 'bronzes-et-objets-en-laiton', 2, 8),
  ('art-et-artisanat', 'Appliqués et tentures d''Abomey', 'appliques-et-tentures-dabomey', 2, 9),
  ('art-et-artisanat', 'Loisirs créatifs', 'loisirs-creatifs', 2, 10),
  (NULL, 'Cuisine et ustensiles', 'cuisine-et-ustensiles', 1, 20),
  ('cuisine-et-ustensiles', 'Casseroles et marmites', 'casseroles-et-marmites', 2, 0),
  ('cuisine-et-ustensiles', 'Poêles et plats', 'poeles-et-plats', 2, 1),
  ('cuisine-et-ustensiles', 'Vaisselle et couverts', 'vaisselle-et-couverts', 2, 2),
  ('cuisine-et-ustensiles', 'Couteaux et ustensiles', 'couteaux-et-ustensiles', 2, 3),
  ('cuisine-et-ustensiles', 'Mortiers et ustensiles traditionnels', 'mortiers-et-ustensiles-traditionnels', 2, 4),
  ('cuisine-et-ustensiles', 'Boîtes de conservation', 'boites-de-conservation', 2, 5),
  ('cuisine-et-ustensiles', 'Thermos et glacières', 'thermos-et-glacieres', 2, 6),
  ('cuisine-et-ustensiles', 'Linge de table', 'linge-de-table', 2, 7),
  ('cuisine-et-ustensiles', 'Bassines, seaux et bidons', 'bassines-seaux-et-bidons', 2, 8),
  (NULL, 'Chaussures et maroquinerie', 'chaussures-et-maroquinerie', 1, 21),
  ('chaussures-et-maroquinerie', 'Chaussures femme', 'chaussures-femme', 2, 0),
  ('chaussures-et-maroquinerie', 'Chaussures homme', 'chaussures-homme', 2, 1),
  ('chaussures-et-maroquinerie', 'Chaussures enfant', 'chaussures-enfant', 2, 2),
  ('chaussures-et-maroquinerie', 'Sandales et tongs', 'sandales-et-tongs', 2, 3),
  ('chaussures-et-maroquinerie', 'Baskets', 'baskets', 2, 4),
  ('chaussures-et-maroquinerie', 'Sacs à main', 'sacs-a-main', 2, 5),
  ('chaussures-et-maroquinerie', 'Sacs à dos', 'sacs-a-dos', 2, 6),
  ('chaussures-et-maroquinerie', 'Valises et bagages', 'valises-et-bagages', 2, 7),
  ('chaussures-et-maroquinerie', 'Portefeuilles et petite maroquinerie', 'portefeuilles-et-petite-maroquinerie', 2, 8),
  (NULL, 'Bijoux et montres', 'bijoux-et-montres', 1, 22),
  ('bijoux-et-montres', 'Colliers et pendentifs', 'colliers-et-pendentifs', 2, 0),
  ('bijoux-et-montres', 'Bracelets', 'bracelets', 2, 1),
  ('bijoux-et-montres', 'Bagues', 'bagues', 2, 2),
  ('bijoux-et-montres', 'Boucles d''oreilles', 'boucles-doreilles', 2, 3),
  ('bijoux-et-montres', 'Chaînes et gourmettes', 'chaines-et-gourmettes', 2, 4),
  ('bijoux-et-montres', 'Montres homme', 'montres-homme', 2, 5),
  ('bijoux-et-montres', 'Montres femme', 'montres-femme', 2, 6),
  ('bijoux-et-montres', 'Perles et bijoux traditionnels', 'perles-et-bijoux-traditionnels', 2, 7),
  ('bijoux-et-montres', 'Bijoux en or et argent', 'bijoux-en-or-et-argent', 2, 8),
  ('bijoux-et-montres', 'Parures et coffrets', 'parures-et-coffrets', 2, 9),
  (NULL, 'Pagnes et tissus', 'pagnes-et-tissus', 1, 23),
  ('pagnes-et-tissus', 'Wax', 'wax', 2, 0),
  ('pagnes-et-tissus', 'Bazin et brocart', 'bazin-et-brocart', 2, 1),
  ('pagnes-et-tissus', 'Dentelle et tulle', 'dentelle-et-tulle', 2, 2),
  ('pagnes-et-tissus', 'Pagnes tissés et bogolan', 'pagnes-tisses-et-bogolan', 2, 3),
  ('pagnes-et-tissus', 'Tissus de coton', 'tissus-de-coton', 2, 4),
  ('pagnes-et-tissus', 'Satin, soie et velours', 'satin-soie-et-velours', 2, 5),
  ('pagnes-et-tissus', 'Tissus d''ameublement', 'tissus-dameublement', 2, 6),
  ('pagnes-et-tissus', 'Fournitures de couture', 'fournitures-de-couture', 2, 7),
  ('pagnes-et-tissus', 'Machines à coudre', 'machines-a-coudre', 2, 8),
  (NULL, 'Mariage et événements', 'mariage-et-evenements', 1, 24),
  ('mariage-et-evenements', 'Décoration de fête', 'decoration-de-fete', 2, 0),
  ('mariage-et-evenements', 'Tenues de mariage', 'tenues-de-mariage', 2, 1),
  ('tenues-de-mariage', 'Robes de mariée', 'robes-de-mariee', 3, 0),
  ('tenues-de-mariage', 'Costumes et smokings', 'costumes-et-smokings', 3, 1),
  ('tenues-de-mariage', 'Tenues de cortège', 'tenues-de-cortege', 3, 2),
  ('mariage-et-evenements', 'Cadeaux et coffrets', 'cadeaux-et-coffrets', 2, 2),
  ('mariage-et-evenements', 'Faire-part et papeterie événementielle', 'faire-part-et-papeterie-evenementielle', 2, 3),
  ('mariage-et-evenements', 'Vaisselle jetable', 'vaisselle-jetable', 2, 4),
  ('mariage-et-evenements', 'Chapiteaux, bâches et chaises', 'chapiteaux-baches-et-chaises', 2, 5),
  (NULL, 'Énergie solaire', 'energie-solaire', 1, 25),
  ('energie-solaire', 'Panneaux solaires', 'panneaux-solaires', 2, 0),
  ('energie-solaire', 'Batteries solaires', 'batteries-solaires', 2, 1),
  ('energie-solaire', 'Onduleurs et régulateurs', 'onduleurs-et-regulateurs', 2, 2),
  ('energie-solaire', 'Kits solaires complets', 'kits-solaires-complets', 2, 3),
  ('energie-solaire', 'Lampes et lanternes solaires', 'lampes-et-lanternes-solaires', 2, 4),
  ('energie-solaire', 'Groupes électrogènes', 'groupes-electrogenes', 2, 5),
  ('energie-solaire', 'Stabilisateurs de tension', 'stabilisateurs-de-tension', 2, 6),
  ('energie-solaire', 'Accessoires d''installation solaire', 'accessoires-dinstallation-solaire', 2, 7);

CREATE TEMP TABLE tmp_plan (
  parent_slug varchar(255),
  name        varchar(255),
  slug        varchar(255),
  level       int,
  sort_order  int,
  statut      text
);

-- Calcul du plan, niveau par niveau (lecture seule sur categories)
INSERT INTO tmp_plan (parent_slug, name, slug, level, sort_order, statut)
SELECT t.parent_slug, t.name, t.slug, t.level, t.sort_order,
       CASE WHEN (EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)
       OR EXISTS (SELECT 1 FROM public.categories c
                  LEFT JOIN public.categories cp ON cp.id = c."parentId"
                  WHERE lower(c.name) = lower(t.name)
                    AND cp.slug IS NOT DISTINCT FROM t.parent_slug)) THEN 'EXISTE_DEJA'
            WHEN TRUE THEN 'NOUVELLE'
            ELSE 'PARENT_INTROUVABLE' END
FROM tmp_cat t
WHERE t.level = 1;

INSERT INTO tmp_plan (parent_slug, name, slug, level, sort_order, statut)
SELECT t.parent_slug, t.name, t.slug, t.level, t.sort_order,
       CASE WHEN (EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)
       OR EXISTS (SELECT 1 FROM public.categories c
                  LEFT JOIN public.categories cp ON cp.id = c."parentId"
                  WHERE lower(c.name) = lower(t.name)
                    AND cp.slug IS NOT DISTINCT FROM t.parent_slug)) THEN 'EXISTE_DEJA'
            WHEN (EXISTS (SELECT 1 FROM public.categories p WHERE p.slug = t.parent_slug AND p.level = 1)
           OR EXISTS (SELECT 1 FROM tmp_plan pp WHERE pp.slug = t.parent_slug AND pp.statut = 'NOUVELLE')) THEN 'NOUVELLE'
            ELSE 'PARENT_INTROUVABLE' END
FROM tmp_cat t
WHERE t.level = 2;

INSERT INTO tmp_plan (parent_slug, name, slug, level, sort_order, statut)
SELECT t.parent_slug, t.name, t.slug, t.level, t.sort_order,
       CASE WHEN (EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)
       OR EXISTS (SELECT 1 FROM public.categories c
                  LEFT JOIN public.categories cp ON cp.id = c."parentId"
                  WHERE lower(c.name) = lower(t.name)
                    AND cp.slug IS NOT DISTINCT FROM t.parent_slug)) THEN 'EXISTE_DEJA'
            WHEN (EXISTS (SELECT 1 FROM public.categories p WHERE p.slug = t.parent_slug AND p.level = 2)
           OR EXISTS (SELECT 1 FROM tmp_plan pp WHERE pp.slug = t.parent_slug AND pp.statut = 'NOUVELLE')) THEN 'NOUVELLE'
            ELSE 'PARENT_INTROUVABLE' END
FROM tmp_cat t
WHERE t.level = 3;

-- ---------------------------------------------------------------------
-- PARTIE 2 : APERÇU (lecture seule)
-- NOUVELLE = sera ajoutée ; EXISTE_DEJA = ignorée ;
-- PARENT_INTROUVABLE = ignorée (parent absent de la base).
-- ---------------------------------------------------------------------
DO $apercu$
DECLARE
  v_total int; v_nouvelles int; v_existantes int; v_orphelines int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE statut = 'NOUVELLE'),
         count(*) FILTER (WHERE statut = 'EXISTE_DEJA'),
         count(*) FILTER (WHERE statut = 'PARENT_INTROUVABLE')
    INTO v_total, v_nouvelles, v_existantes, v_orphelines
    FROM tmp_plan;
  RAISE NOTICE 'APERCU : % lignes au catalogue -> % NOUVELLES a ajouter, % deja existantes (ignorees), % ignorees (parent introuvable)',
    v_total, v_nouvelles, v_existantes, v_orphelines;
END
$apercu$;

SELECT statut,
       count(*) OVER (PARTITION BY statut) AS nb_lignes_de_ce_statut,
       level   AS niveau,
       parent_slug,
       name    AS nom,
       slug,
       sort_order
FROM tmp_plan
ORDER BY CASE statut WHEN 'NOUVELLE' THEN 1 WHEN 'PARENT_INTROUVABLE' THEN 2 ELSE 3 END,
         level, parent_slug NULLS FIRST, sort_order, name;
-- ----------------------- FIN DE L'APERÇU -----------------------------

-- ---------------------------------------------------------------------
-- PARTIE 3 : INSERTION (transaction unique)
-- ---------------------------------------------------------------------
BEGIN;

DO $insertion$
DECLARE
  v_niveau     int;
  v_n          int;
  v_total      int;
  v_insere     int := 0;
  v_existantes int;
BEGIN
  SELECT count(*) INTO v_total FROM tmp_cat;

  -- Lignes dont le slug ou le nom (même parent) existe déjà avant insertion
  SELECT count(*) INTO v_existantes
  FROM tmp_cat t
  WHERE EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)
     OR EXISTS (SELECT 1 FROM public.categories c
                LEFT JOIN public.categories cp ON cp.id = c."parentId"
                WHERE lower(c.name) = lower(t.name)
                  AND cp.slug IS NOT DISTINCT FROM t.parent_slug);

  FOR v_niveau IN 1..3 LOOP
    INSERT INTO public.categories
      (id, "parentId", name, slug, "imageUrl", level, "sortOrder", "isActive", "createdAt", "updatedAt")
    SELECT uuid_generate_v4(), p.id, t.name, t.slug, NULL, v_niveau, t.sort_order, true, now(), now()
    FROM tmp_cat t
    LEFT JOIN public.categories p ON p.slug = t.parent_slug
    WHERE t.level = v_niveau
      -- racine : pas de parent ; sinon le parent DOIT exister, au niveau juste au-dessus
      AND ( (v_niveau = 1 AND t.parent_slug IS NULL)
            OR (v_niveau > 1 AND p.id IS NOT NULL AND p.level = v_niveau - 1) )
      -- jamais de doublon de slug
      AND NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)
      -- ni de doublon de nom (casse ignorée) chez le même parent
      AND NOT EXISTS (SELECT 1 FROM public.categories c
                      WHERE c."parentId" IS NOT DISTINCT FROM p.id
                        AND lower(c.name) = lower(t.name))
    ON CONFLICT DO NOTHING;   -- filet de sécurité (violation d'unicité sur slug)
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_insere := v_insere + v_n;
    RAISE NOTICE 'Niveau % : % categorie(s) inserees', v_niveau, v_n;
  END LOOP;

  RAISE NOTICE 'TERMINE : % inseree(s), % ignoree(s) dont % deja existante(s) et % ignoree(s) (parent introuvable ou conflit), sur % lignes.',
    v_insere, v_total - v_insere, v_existantes, v_total - v_insere - v_existantes, v_total;
END
$insertion$;

COMMIT;
