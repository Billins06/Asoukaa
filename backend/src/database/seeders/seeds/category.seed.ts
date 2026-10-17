import { DataSource } from 'typeorm';
import { Category } from 'src/modules/categories/entities/category.entity';
import {
  CATEGORIES_CATALOGUE,
  CategorieNode,
} from './categories-catalogue.data';

// Même logique que CategoriesService.generateSlug (le service fait foi).
// Ex : "Vêtements Hommes" → "vetements-hommes"
function generateSlug(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD') // décompose les accents
    .replace(/[̀-ͯ]/g, '') // supprime les accents
    .replace(/[^a-z0-9\s-]/g, '') // supprime les caractères spéciaux
    .trim()
    .replace(/\s+/g, '-') // espaces → tirets
    .replace(/-+/g, '-'); // tirets multiples → un seul
}

interface LigneCatalogue {
  name: string;
  slug: string;
  parentSlug: string | null;
  level: number;
  sortOrder: number;
}

// Aplatit l'arbre en lignes (parcours en profondeur, niveau 3 maximum).
function aplatir(
  noeuds: CategorieNode[],
  parentSlug: string | null,
  level: number,
  out: LigneCatalogue[] = [],
): LigneCatalogue[] {
  noeuds.forEach((n, index) => {
    const slug = generateSlug(n.name);
    out.push({ name: n.name, slug, parentSlug, level, sortOrder: index });
    if (n.children?.length) {
      aplatir(n.children, slug, level + 1, out);
    }
  });
  return out;
}

export interface CategorySeedResult {
  total: number;
  inserted: number;
  ignored: number;
}

/**
 * Insère l'arbre de catégories (categories-catalogue.data.ts).
 *
 * - Ré-exécutable à volonté : une catégorie dont le slug existe déjà est IGNORÉE
 *   (jamais modifiée, jamais déplacée, jamais dupliquée).
 * - Création niveau par niveau ; le parent est retrouvé par son slug. S'il est
 *   introuvable, la ligne est ignorée (jamais insérée à la racine).
 * - Une catégorie du même parent ayant déjà le même nom (casse ignorée) est ignorée.
 * - Aucune image : imageUrl reste NULL (à ajouter depuis le site admin).
 */
export async function seedCategories(
  dataSource: DataSource,
): Promise<CategorySeedResult> {
  const lignes = aplatir(CATEGORIES_CATALOGUE, null, 1);

  // Garde-fous sur le catalogue lui-même
  const slugsVus = new Set<string>();
  for (const l of lignes) {
    if (l.level > 3) {
      throw new Error(`Catalogue invalide (niveau > 3) : ${l.name}`);
    }
    if (slugsVus.has(l.slug)) {
      throw new Error(`Catalogue invalide (slug en double) : ${l.slug}`);
    }
    slugsVus.add(l.slug);
  }

  const resultat = await dataSource.transaction(async (manager) => {
    const repo = manager.getRepository(Category);

    // État actuel de la base : slug → catégorie
    const existantes = await repo.find({
      select: ['id', 'name', 'slug', 'parentId', 'level'],
    });
    const parSlug = new Map<string, Category>();
    for (const c of existantes) parSlug.set(c.slug, c);

    // Noms déjà pris par parent (clé "parentId|nom en minuscules")
    const nomsParParent = new Set<string>();
    const cle = (parentId: string | null, nom: string) =>
      `${parentId ?? ''}|${nom.toLowerCase()}`;
    for (const c of existantes) {
      nomsParParent.add(cle(c.parentId ?? null, c.name));
    }

    let inserted = 0;
    let dejaExistantes = 0;
    let parentIntrouvable = 0;
    let nomEnDouble = 0;

    for (const niveau of [1, 2, 3]) {
      let insereNiveau = 0;
      for (const l of lignes.filter((x) => x.level === niveau)) {
        // 1) Le slug existe déjà : on ne touche à rien
        if (parSlug.has(l.slug)) {
          dejaExistantes++;
          continue;
        }

        // 2) Résolution du parent par son slug
        let parentId: string | null = null;
        if (niveau > 1) {
          const parent = l.parentSlug ? parSlug.get(l.parentSlug) : undefined;
          if (!parent || parent.level !== niveau - 1) {
            parentIntrouvable++;
            console.warn(
              `   ⚠️  Parent introuvable pour "${l.name}" (parent attendu : ${l.parentSlug}) → ignorée`,
            );
            continue;
          }
          parentId = parent.id;
        }

        // 3) Même nom (casse ignorée) chez le même parent : on ignore
        if (nomsParParent.has(cle(parentId, l.name))) {
          nomEnDouble++;
          continue;
        }

        const res = await repo.insert({
          name: l.name,
          slug: l.slug,
          parentId,
          imageUrl: null,
          level: niveau,
          sortOrder: l.sortOrder,
          isActive: true,
        });
        const id = res.identifiers[0].id as string;
        parSlug.set(l.slug, {
          id,
          name: l.name,
          slug: l.slug,
          parentId,
          level: niveau,
        } as Category);
        nomsParParent.add(cle(parentId, l.name));
        inserted++;
        insereNiveau++;
      }
      console.log(`   Niveau ${niveau} : ${insereNiveau} catégorie(s) insérée(s)`);
    }

    return { inserted, dejaExistantes, parentIntrouvable, nomEnDouble };
  });

  const ignored = lignes.length - resultat.inserted;
  console.log(
    `✅ Catégories : ${resultat.inserted} insérée(s), ${ignored} ignorée(s) ` +
      `(${resultat.dejaExistantes} déjà existante(s), ${resultat.nomEnDouble} nom déjà pris chez le même parent, ` +
      `${resultat.parentIntrouvable} parent introuvable) sur ${lignes.length} au catalogue`,
  );

  return { total: lignes.length, inserted: resultat.inserted, ignored };
}
