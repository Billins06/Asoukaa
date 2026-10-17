/**
 * Outils de TEST de la migration de base (BaselineSchema1700000000000).
 * Utilisé par scripts/test-baseline.sh - ne sert jamais en production.
 * (Volontairement en JavaScript et hors de src/ : un fichier .ts hors de src/
 * changerait l'emplacement des fichiers compilés et casserait « node dist/main ».)
 * Lancement : node -r ts-node/register/transpile-only -r tsconfig-paths/register scripts/baseline-tools.js <commande> <base>
 *
 * Lit la connexion dans les variables d'environnement DB_HOST, DB_PORT,
 * DB_USER, DB_PASSWORD (il ne lit AUCUN fichier .env). Chaque commande
 * reçoit en paramètre le nom de la base de TEST à utiliser.
 *
 * Commandes :
 *   createdb <base>             crée une base vide
 *   dropdb <base>               supprime une base (nom obligatoirement préfixé asoukaa_bltest_)
 *   sync <base>                 crée le schéma avec synchronize (à partir des entités)
 *   baseline-only <base>        n'exécute QUE la migration de base
 *   migrate-no-baseline <base>  exécute toutes les migrations SAUF la base
 *                               (reproduit une base « déjà installée »)
 *   seed-sample <base>          insère quelques lignes d'exemple
 *   signature <base>            affiche la signature structurelle du schéma
 *   rowcounts <base>            affiche le nombre de lignes par table
 *   drift <base>                affiche ce que synchronize modifierait (informatif)
 */
require('reflect-metadata');
const { DataSource } = require('typeorm');
const fs = require('fs');
const path = require('path');

const PREFIXE = 'asoukaa_bltest_';
const [commande, base] = process.argv.slice(2);

const connexion = (database) => ({
  type: 'postgres',
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT) || 5432,
  username: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  database,
});

const entites = [path.join(__dirname, '../src/**/*.entity{.ts,.js}')];
const dossierMigrations = path.join(__dirname, '../src/database/migrations');

// Signature structurelle : insensible aux NOMS d'index / de contraintes.
const SIGNATURE_SQL = `
SELECT 'EXT ' || extname AS l FROM pg_extension WHERE extname <> 'plpgsql'
UNION ALL
SELECT 'ENUM ' || t.typname || ' = ' || string_agg(e.enumlabel, ' | ' ORDER BY e.enumsortorder)
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid GROUP BY t.typname
UNION ALL
SELECT 'COL ' || c.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
       || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END
       || COALESCE(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '')
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped AND c.relname <> 'typeorm_migrations'
UNION ALL
SELECT 'CON ' || c.relname || ' ' || pg_get_constraintdef(k.oid)
  FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relname <> 'typeorm_migrations'
UNION ALL
SELECT 'IDX ' || tablename || ' ' || regexp_replace(indexdef, 'INDEX \\S+ ON', 'INDEX ON')
  FROM pg_indexes WHERE schemaname = 'public' AND tablename <> 'typeorm_migrations'
    AND indexname NOT IN (SELECT conname FROM pg_constraint)
UNION ALL
SELECT 'SEQ ' || sequencename || ' start=' || start_value
  FROM pg_sequences WHERE schemaname = 'public' AND sequencename <> 'typeorm_migrations_id_seq'
ORDER BY 1`;

const COMPTES_SQL = `
SELECT table_name AS t,
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text AS n
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> 'typeorm_migrations'
ORDER BY 1`;

const EXEMPLES_SQL = [
  `INSERT INTO "delivery_zones" ("commune","departement","fraisLivraison") VALUES ('Cotonou','Littoral',1000),('Porto-Novo','Ouémé',1500)`,
  `INSERT INTO "categories" ("name","slug") VALUES ('Mode','mode'),('Maison','maison')`,
  `INSERT INTO "partners" ("part_name") VALUES ('Partenaire test')`,
  `INSERT INTO "vitrine_bandeau" ("titre") VALUES ('Bandeau test')`,
];

async function main() {
  if (!process.env.DB_PASSWORD) throw new Error('DB_PASSWORD manquant');
  if (!commande) throw new Error('Commande manquante (voir l\'en-tête du fichier)');
  if (!base?.startsWith(PREFIXE)) {
    throw new Error(`Par sécurité, le nom de base doit commencer par "${PREFIXE}" (reçu : ${base})`);
  }

  if (commande === 'createdb' || commande === 'dropdb') {
    const admin = new DataSource(connexion('postgres'));
    await admin.initialize();
    await admin.query(`DROP DATABASE IF EXISTS "${base}"`);
    if (commande === 'createdb') await admin.query(`CREATE DATABASE "${base}"`);
    await admin.destroy();
    return;
  }

  if (commande === 'baseline-only' || commande === 'migrate-no-baseline') {
    const fichiers = fs
      .readdirSync(dossierMigrations)
      .filter((f) => /\.ts$/.test(f) || /\.js$/.test(f))
      .filter((f) => (f.startsWith('1700000000000-') ? commande === 'baseline-only' : commande === 'migrate-no-baseline'))
      .map((f) => path.join(dossierMigrations, f));
    const ds = new DataSource({ ...connexion(base), migrations: fichiers, migrationsTableName: 'typeorm_migrations' });
    await ds.initialize();
    await ds.runMigrations();
    await ds.destroy();
    return;
  }

  const ds = new DataSource({ ...connexion(base), entities: entites, synchronize: false });
  await ds.initialize();
  try {
    if (commande === 'sync') {
      await ds.synchronize();
    } else if (commande === 'signature') {
      for (const r of await ds.query(SIGNATURE_SQL)) console.log(r.l);
    } else if (commande === 'rowcounts') {
      for (const r of await ds.query(COMPTES_SQL)) console.log(`${r.t} ${r.n}`);
    } else if (commande === 'seed-sample') {
      for (const sql of EXEMPLES_SQL) await ds.query(sql);
    } else if (commande === 'drift') {
      const log = await ds.driver.createSchemaBuilder().log();
      for (const q of log.upQueries) console.log(q.query.trim() + ';');
    } else {
      throw new Error(`Commande inconnue : ${commande}`);
    }
  } finally {
    await ds.destroy();
  }
}

main().catch((e) => {
  console.error('ERREUR :', e?.message ?? e);
  process.exit(1);
});
