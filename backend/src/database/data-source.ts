import { DataSource } from "typeorm";
import * as dotenv from "dotenv";
import * as path from "path";

// Charge les variables d'environnement depuis .env à la racine du projet backend
const envPath = path.resolve(__dirname, "../../.env");
console.log(`📝 Loading .env from: ${envPath}`);
const result = dotenv.config({ path: envPath });

if (result.error) {
  console.warn(`⚠️  .env not found, using existing environment variables`);
} else {
  console.log(`✅ .env loaded successfully`);
}

// Affiche les variables chargées pour debug
console.log(`\n📋 Database Configuration:`);
console.log(`   Host: ${process.env.DB_HOST || "NOT SET"}`);
console.log(`   Port: ${process.env.DB_PORT || "NOT SET"}`);
console.log(`   User: ${process.env.DB_USER || "NOT SET"}`);
console.log(`   Database: ${process.env.DB_NAME || "NOT SET"}`);
console.log(`   Password: ${process.env.DB_PASSWORD ? "***SET***" : "NOT SET"}\n`);

if (!process.env.DB_PASSWORD) {
  console.error(`❌ ERROR: DB_PASSWORD is not set!`);
  console.error(`   Check your .env file at: ${envPath}`);
  process.exit(1);
}

export const AppDataSource = new DataSource({
  type: "postgres",
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT) || 5432,
  username: process.env.DB_USER || "postgres",
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "asoukaa",
  entities: [path.join(__dirname, "../**/*.entity{.ts,.js}")],
  migrations: [path.join(__dirname, "../database/migrations/*{.ts,.js}")],
  logging: process.env.DB_LOGGING === "true",
  synchronize: false,
  migrationsRun: false,
  migrationsTableName: "typeorm_migrations",
});
