require('dotenv').config();
const { Client } = require('pg');

// Regroupement proposé (a valider / corriger par Collins) :
//  - Cotonou + environs (Littoral, Atlantique, Ouémé)      -> 1000f
//  - Centre (Collines, Couffo, Mono, Plateau, Zou)          -> 1500f
//  - Nord (Alibori, Atacora, Borgou, Donga)                 -> 2000f
const ZONE_PRICES = [
  { departements: ['Littoral', 'Atlantique', 'Ouémé'], prix: 1000 },
  { departements: ['Collines', 'Couffo', 'Mono', 'Plateau', 'Zou'], prix: 1500 },
  { departements: ['Alibori', 'Atacora', 'Borgou', 'Donga'], prix: 2000 },
];

async function main() {
  const client = new Client({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT) || 5432,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    connectionString: process.env.DATABASE_URL || undefined,
  });
  await client.connect();

  let totalUpdated = 0;
  for (const { departements, prix } of ZONE_PRICES) {
    const res = await client.query(
      `UPDATE delivery_zones SET "fraisLivraison" = $1 WHERE departement = ANY($2::text[])`,
      [prix, departements],
    );
    console.log(`${departements.join(', ')} -> ${prix}f : ${res.rowCount} commune(s) mise(s) à jour`);
    totalUpdated += res.rowCount;
  }

  const allDeps = ZONE_PRICES.flatMap((z) => z.departements);
  const missing = await client.query(
    `SELECT commune, departement, "fraisLivraison" FROM delivery_zones WHERE departement != ALL($1::text[]) ORDER BY departement, commune`,
    [allDeps],
  );
  console.log(`\nTotal mis à jour: ${totalUpdated}`);
  console.log(`Communes non couvertes par un des 3 groupes (devrait être vide): ${missing.rowCount}`);
  for (const row of missing.rows) {
    console.log(' -', row.commune, '/', row.departement, '/', row.fraisLivraison);
  }

  const summary = await client.query(
    `SELECT departement, "fraisLivraison", COUNT(*) FROM delivery_zones GROUP BY departement, "fraisLivraison" ORDER BY departement`,
  );
  console.log('\nRécap par département:');
  for (const row of summary.rows) {
    console.log(' -', row.departement, ':', row.fraisLivraison, 'f (', row.count, 'communes)');
  }

  await client.end();
}

main().catch((e) => {
  console.error('ERROR', e);
  process.exit(1);
});
