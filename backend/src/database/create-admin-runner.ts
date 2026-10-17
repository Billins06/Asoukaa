import * as readline from 'readline';
import * as bcrypt from 'bcrypt';
import { AppDataSource } from './data-source';
import {
  AdminAccount,
  AdminRole,
} from '../modules/auth/entities/admin-account.entity';

// Crée UN compte super-administrateur, avec l'e-mail et le mot de passe que TU
// tapes (le mot de passe ne s'affiche pas et n'est écrit nulle part).
//   En local :  npm run create:admin
//   Sur Railway (après « railway ssh ») :  node dist/database/create-admin-runner.js
// À utiliser À LA PLACE de « npm run seed » sur un serveur en ligne : le seed crée
// des comptes admin au mot de passe public « Admin1234! ».

function ask(question: string, hidden = false): Promise<string> {
  return new Promise((resolve) => {
    const rl: any = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: true,
    });
    if (hidden) {
      rl._writeToOutput = (s: string) => {
        rl.output.write(s.startsWith(question) ? question : '');
      };
    }
    rl.question(question, (answer: string) => {
      rl.close();
      if (hidden) process.stdout.write('\n');
      resolve(answer);
    });
  });
}

async function bootstrap() {
  try {
    const email = (await ask('E-mail de l\'administrateur : ')).trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new Error('E-mail invalide.');
    }
    const prenom = (await ask('Prénom : ')).trim();
    const name = (await ask('Nom : ')).trim();
    if (!prenom || !name) throw new Error('Prénom et nom obligatoires.');

    const password = await ask('Mot de passe (12 caractères minimum, invisible) : ', true);
    if (password.length < 12) {
      throw new Error('Mot de passe trop court (12 caractères minimum).');
    }
    const confirm = await ask('Retape le mot de passe : ', true);
    if (password !== confirm) throw new Error('Les deux mots de passe sont différents.');

    if (!AppDataSource.isInitialized) await AppDataSource.initialize();
    const repo = AppDataSource.getRepository(AdminAccount);

    if (await repo.findOne({ where: { email } })) {
      throw new Error('Un compte administrateur existe déjà avec cet e-mail.');
    }

    const admin = new AdminAccount();
    admin.email = email;
    admin.prenom = prenom;
    admin.name = name;
    admin.role = AdminRole.SUPERADMIN;
    admin.passwordHash = await bcrypt.hash(password, 12);
    admin.isPasswordSet = true;
    admin.isActive = true;
    await repo.save(admin);

    console.log(`✅ Super-administrateur créé : ${email}`);
    await AppDataSource.destroy();
  } catch (error) {
    console.error('❌ ' + (error as Error).message);
    if (AppDataSource.isInitialized) await AppDataSource.destroy();
    process.exit(1);
  }
}

bootstrap();
