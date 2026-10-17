#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Générateur + validateur du catalogue de catégories Asoukaa.

Source UNIQUE : categories_arbre.txt (indentation = 2 espaces par niveau).
Produit, à partir de cette seule source (donc sans divergence possible) :
  - src/database/seeders/seeds/categories-catalogue.data.ts   (seeder TypeORM)
  - src/database/seeders/sql/categories_catalogue.sql         (pgAdmin / psql)
  - LISTE_CATEGORIES_PROPOSEES.md et .csv                     (relecture)
Puis RELIT les fichiers produits et vérifie qu'ils décrivent exactement le
même arbre que la source.

Usage :  python3 generer_categories.py            (depuis la racine du backend)
         python3 generer_categories.py --verifier (vérification seule, n'écrit rien)
Ne touche jamais à la base de données.
"""
import json
import os
import re
import sys
import unicodedata

RACINE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(RACINE, 'categories_arbre.txt')
F_TS = os.path.join(RACINE, 'src/database/seeders/seeds/categories-catalogue.data.ts')
F_SQL = os.path.join(RACINE, 'src/database/seeders/sql/categories_catalogue.sql')
F_MD = os.path.join(RACINE, 'LISTE_CATEGORIES_PROPOSEES.md')
F_CSV = os.path.join(RACINE, 'LISTE_CATEGORIES_PROPOSEES.csv')

# Catégories DÉJÀ en base chez le propriétaire : slug -> (slug du parent, nom, niveau)
EXISTANTES = {
    'alimentation': (None, 'Alimentation', 1),
    'mais': ('alimentation', 'MAIS', 2),
    'beaute': (None, 'Beauté', 1),
    'electronique': (None, 'Électronique', 1),
    'jouets': (None, 'Jouets', 1),
    'livres': (None, 'Livres', 1),
    'maison': (None, 'Maison', 1),
    'mode': (None, 'Mode', 1),
    'sports': (None, 'Sports', 1),
    'gym': ('sports', 'Gym', 2),
    'padel': ('sports', 'Padel', 2),
}


def generate_slug(name):
    """Copie EXACTE de CategoriesService.generateSlug (categories.service.ts)."""
    s = name.lower()
    s = unicodedata.normalize('NFD', s)
    s = re.sub(r'[̀-ͯ]', '', s)
    s = re.sub(r'[^a-z0-9\s-]', '', s)
    s = s.strip()
    s = re.sub(r'\s+', '-', s)
    s = re.sub(r'-+', '-', s)
    return s


def lire_source():
    arbre, pile = [], []  # pile : [(indent, noeud)]
    for no, ligne in enumerate(open(SOURCE, encoding='utf-8').read().split('\n'), 1):
        if not ligne.strip() or ligne.lstrip().startswith('#'):
            continue
        indent = len(ligne) - len(ligne.lstrip(' '))
        if indent % 2:
            raise SystemExit('Ligne %d : indentation impaire' % no)
        niv = indent // 2
        noeud = {'name': ligne.strip(), 'children': []}
        while pile and pile[-1][0] >= niv:
            pile.pop()
        if niv == 0:
            arbre.append(noeud)
        else:
            if not pile or pile[-1][0] != niv - 1:
                raise SystemExit('Ligne %d : saut de niveau' % no)
            pile[-1][1]['children'].append(noeud)
        pile.append((niv, noeud))
    return arbre


def aplatir(arbre):
    """Liste ordonnée (parcours en profondeur) de dicts name/slug/parent_slug/level/sort_order."""
    out = []

    def rec(noeuds, parent_slug, niveau):
        for i, n in enumerate(noeuds):
            slug = generate_slug(n['name'])
            out.append({'name': n['name'], 'slug': slug, 'parent_slug': parent_slug,
                        'level': niveau, 'sort_order': i})
            rec(n.get('children', []), slug, niveau + 1)

    rec(arbre, None, 1)
    return out


def valider(lignes):
    erreurs = []
    noms, slugs = {}, {}
    for l in lignes:
        if l['level'] > 3:
            erreurs.append('Niveau > 3 : %s' % l['name'])
        if len(l['name']) > 255 or len(l['slug']) > 255:
            erreurs.append('Longueur > 255 : %s' % l['name'])
        if not l['slug']:
            erreurs.append('Slug vide : %s' % l['name'])
        if re.search(r"[‘’“”–—…]", l['name']):
            erreurs.append('Caractère typographique douteux : %s' % l['name'])
        if l['name'] != l['name'].strip() or '  ' in l['name']:
            erreurs.append('Espaces superflus : %r' % l['name'])
        if l['name'][0] != l['name'][0].upper():
            erreurs.append('Majuscule initiale manquante : %s' % l['name'])
        k = l['name'].lower()
        if k in noms:
            erreurs.append('Nom en double : %s' % l['name'])
        noms[k] = 1
        if l['slug'] in slugs:
            erreurs.append('Slug en double : %s (%s / %s)' % (l['slug'], slugs[l['slug']], l['name']))
        slugs[l['slug']] = l['name']
    par_slug = {l['slug']: l for l in lignes}
    for slug, (p, nom, niv) in EXISTANTES.items():
        l = par_slug.get(slug)
        if not l:
            erreurs.append('Catégorie existante absente du catalogue : %s' % slug)
            continue
        if l['name'] != nom or l['parent_slug'] != p or l['level'] != niv:
            erreurs.append('Catégorie existante modifiée/déplacée : %s -> %s/%s/%s'
                           % (slug, l['name'], l['parent_slug'], l['level']))
        if l['sort_order'] is None:
            erreurs.append('sortOrder')
    # Les existantes sont sans enfant sauf Alimentation/MAIS et Sports/Gym/Padel : aucun enfant déplacé
    for l in lignes:
        if l['parent_slug'] and l['parent_slug'] not in par_slug:
            erreurs.append('Parent introuvable : %s' % l['name'])
        elif l['parent_slug'] and par_slug[l['parent_slug']]['level'] != l['level'] - 1:
            erreurs.append('Niveau incohérent : %s' % l['name'])
    return erreurs


def sq(s):
    return "'" + s.replace("'", "''") + "'"


# ---------------------------------------------------------------- TypeScript
def gen_ts(arbre):
    def rec(noeuds, ind):
        out = []
        for n in noeuds:
            pad = '  ' * ind
            if n['children']:
                out.append('%s{\n%s  "name": %s,\n%s  "children": [\n%s\n%s  ]\n%s}' % (
                    pad, pad, json.dumps(n['name'], ensure_ascii=False), pad,
                    rec(n['children'], ind + 2), pad, pad))
            else:
                out.append('%s{ "name": %s }' % (pad, json.dumps(n['name'], ensure_ascii=False)))
        return ',\n'.join(out) + ','
    corps = rec(arbre, 1)
    return (
        "// FICHIER GÉNÉRÉ par generer_categories.py à partir de categories_arbre.txt.\n"
        "// Ne le modifiez pas à la main : modifiez categories_arbre.txt puis relancez\n"
        "// `python3 generer_categories.py` (le SQL et le seeder restent ainsi identiques).\n"
        "//\n"
        "// Arbre complet des catégories d'Asoukaa (3 niveaux maximum). Les catégories déjà\n"
        "// présentes en base sont simplement ignorées par le seeder (contrôle par slug).\n"
        "\n"
        "export interface CategorieNode {\n"
        "  name: string;\n"
        "  children?: CategorieNode[];\n"
        "}\n"
        "\n"
        "export const CATEGORIES_CATALOGUE: CategorieNode[] = [\n%s\n];\n" % corps)


# ---------------------------------------------------------------- SQL
def gen_sql(lignes):
    vals = []
    for l in lignes:
        vals.append('  (%s, %s, %s, %d, %d)' % (
            'NULL' if l['parent_slug'] is None else sq(l['parent_slug']),
            sq(l['name']), sq(l['slug']), l['level'], l['sort_order']))
    values = ',\n'.join(vals)

    existe = ("(EXISTS (SELECT 1 FROM public.categories c WHERE c.slug = t.slug)\n"
              "       OR EXISTS (SELECT 1 FROM public.categories c\n"
              "                  LEFT JOIN public.categories cp ON cp.id = c.\"parentId\"\n"
              "                  WHERE lower(c.name) = lower(t.name)\n"
              "                    AND cp.slug IS NOT DISTINCT FROM t.parent_slug))")
    plan = []
    for n in (1, 2, 3):
        if n == 1:
            parent_ok = 'TRUE'
        else:
            parent_ok = ("(EXISTS (SELECT 1 FROM public.categories p WHERE p.slug = t.parent_slug AND p.level = %d)\n"
                         "           OR EXISTS (SELECT 1 FROM tmp_plan pp WHERE pp.slug = t.parent_slug AND pp.statut = 'NOUVELLE'))" % (n - 1))
        plan.append(
            "INSERT INTO tmp_plan (parent_slug, name, slug, level, sort_order, statut)\n"
            "SELECT t.parent_slug, t.name, t.slug, t.level, t.sort_order,\n"
            "       CASE WHEN %s THEN 'EXISTE_DEJA'\n"
            "            WHEN %s THEN 'NOUVELLE'\n"
            "            ELSE 'PARENT_INTROUVABLE' END\n"
            "FROM tmp_cat t\n"
            "WHERE t.level = %d;\n" % (existe, parent_ok, n))
    plan_sql = '\n'.join(plan)

    return """-- =====================================================================
-- ASOUKAA : insertion du catalogue de catégories (@@TOTAL@@ lignes dans le catalogue)
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
@@VALUES@@;

CREATE TEMP TABLE tmp_plan (
  parent_slug varchar(255),
  name        varchar(255),
  slug        varchar(255),
  level       int,
  sort_order  int,
  statut      text
);

-- Calcul du plan, niveau par niveau (lecture seule sur categories)
@@PLAN@@
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
""".replace('@@TOTAL@@', str(len(lignes))).replace('@@VALUES@@', values).replace('@@PLAN@@', plan_sql)


# ---------------------------------------------------------------- MD / CSV
def stat(l):
    return 'existe déjà' if l['slug'] in EXISTANTES else 'nouveau'


def gen_md(arbre, lignes):
    racines = [l for l in lignes if l['level'] == 1]
    ex = [l for l in lignes if l['slug'] in EXISTANTES]
    nouv = len(lignes) - len(ex)
    n2 = sum(1 for l in lignes if l['level'] == 2)
    n3 = sum(1 for l in lignes if l['level'] == 3)
    o = ['# Catégories proposées pour Asoukaa', '',
         '**Total : %d catégories** (%d racines, %d de niveau 2, %d de niveau 3) : '
         '**%d existent déjà** en base, **%d sont nouvelles**.' % (
             len(lignes), len(racines), n2, n3, len(ex), nouv), '',
         '_Relis cette liste ; pour retirer ou renommer une ligne, modifie `categories_arbre.txt` '
         'puis relance `python3 generer_categories.py`._', '']
    o.append('## Arbre')
    o.append('')

    def rec(noeuds, ind):
        for n in noeuds:
            s = generate_slug(n['name'])
            marque = 'existe déjà' if s in EXISTANTES else 'nouveau'
            gras = '**' if ind == 0 else ''
            o.append('%s- %s%s%s — _%s_' % ('  ' * ind, gras, n['name'], gras, marque))
            rec(n['children'], ind + 1)
    rec(arbre, 0)
    o += ['', '## Comment l\'utiliser', '',
          '1. Aperçu : ouvre `src/database/seeders/sql/categories_catalogue.sql` dans pgAdmin, sélectionne de « PARTIE 1 » à la fin de « APERÇU » et exécute : tu vois ce qui serait ajouté (rien n\'est écrit).',
          '2. Exécution SQL : exécute ensuite le script entier dans pgAdmin (Query Tool) sur la bonne base.',
          '3. Ou, avec le seeder : `npm run seed:categories` (même résultat que le SQL, avec les compteurs inséré/ignoré).',
          '4. Tu peux relancer sans risque : aucun doublon, aucune catégorie existante modifiée ni déplacée.',
          '5. Les nouvelles catégories n\'ont pas d\'image : ajoute-les ensuite depuis le site admin (une image est attendue pour les catégories principales).',
          '6. Les images actuelles pointent vers localhost : elles seront à renvoyer (ré-uploader) après la mise en ligne.',
          '']
    return '\n'.join(o)


def gen_csv(lignes):
    nom_par_slug = {l['slug']: l['name'] for l in lignes}

    def cel(s):
        return '"%s"' % s.replace('"', '""') if (';' in s or '"' in s) else s
    o = ['niveau;categorie_parente;nom;statut']
    for l in lignes:
        o.append('%d;%s;%s;%s' % (l['level'], cel(nom_par_slug.get(l['parent_slug'], '')), cel(l['name']), stat(l)))
    return '\r\n'.join(o) + '\r\n'


# ---------------------------------------------------------------- relecture
def relire_ts():
    txt = open(F_TS, encoding='utf-8').read()
    debut = txt.index('= [', txt.index('export const CATEGORIES_CATALOGUE')) + 2
    fin = txt.rindex(']')
    corps = txt[debut:fin + 1]
    corps = re.sub(r',(\s*[\]}])', r'\1', corps)  # virgules finales
    return json.loads(corps)


def relire_sql():
    txt = open(F_SQL, encoding='utf-8').read()
    bloc = txt.split('VALUES\n', 1)[1].split(';\n', 1)[0]
    rows = []
    for m in re.finditer(r"\((NULL|'(?:[^']|'')*'), ('(?:[^']|'')*'), ('(?:[^']|'')*'), (\d+), (\d+)\)", bloc):
        un = lambda s: s[1:-1].replace("''", "'")
        rows.append({'parent_slug': None if m.group(1) == 'NULL' else un(m.group(1)),
                     'name': un(m.group(2)), 'slug': un(m.group(3)),
                     'level': int(m.group(4)), 'sort_order': int(m.group(5))})
    # pas d'instruction d'écriture interdite
    for interdit in (r'\bUPDATE\s+public\.categories', r'\bDELETE\s+FROM', r'\bTRUNCATE\b', r'\bDROP\s+TABLE\s+(?!IF EXISTS pg_temp)'):
        sans_com = re.sub(r'--[^\n]*', '', txt)
        if re.search(interdit, sans_com, re.I):
            raise SystemExit('SQL : instruction interdite trouvée : ' + interdit)
    return rows


def main():
    verif_seule = '--verifier' in sys.argv
    arbre = lire_source()
    lignes = aplatir(arbre)
    err = valider(lignes)
    if err:
        print('ERREURS DE VALIDATION :')
        for e in err:
            print(' -', e)
        sys.exit(1)
    if not verif_seule:
        for f in (F_TS, F_SQL):
            os.makedirs(os.path.dirname(f), exist_ok=True)
        open(F_TS, 'w', encoding='utf-8', newline='\n').write(gen_ts(arbre))
        open(F_SQL, 'w', encoding='utf-8', newline='\n').write(gen_sql(lignes))
        open(F_MD, 'w', encoding='utf-8', newline='\n').write(gen_md(arbre, lignes))
        open(F_CSV, 'w', encoding='utf-8-sig', newline='').write(gen_csv(lignes))
    # Relecture croisée : TS == source == SQL
    ts_lignes = aplatir(relire_ts())
    sql_lignes = relire_sql()
    if ts_lignes != lignes:
        print('DIVERGENCE : le fichier .ts ne correspond pas à la source'); sys.exit(1)
    if sql_lignes != lignes:
        print('DIVERGENCE : le fichier .sql ne correspond pas à la source'); sys.exit(1)
    racines = sum(1 for l in lignes if l['level'] == 1)
    ex = sum(1 for l in lignes if l['slug'] in EXISTANTES)
    print('OK : %d catégories (%d racines, N2=%d, N3=%d), %d existantes, %d nouvelles'
          % (len(lignes), racines, sum(1 for l in lignes if l['level'] == 2),
             sum(1 for l in lignes if l['level'] == 3), ex, len(lignes) - ex))
    print('OK : noms uniques, slugs uniques, niveau <= 3, longueur <= 255, existantes inchangées')
    print('OK : SQL, TypeScript et source décrivent exactement le même arbre')


if __name__ == '__main__':
    main()
