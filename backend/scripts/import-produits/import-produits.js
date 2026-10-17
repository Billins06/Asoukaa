#!/usr/bin/env node
/* Import des produits Asoukaa pour UNE boutique (un compte vendeur).
 * Node >= 18, aucune dépendance.
 *
 *   node scripts/import-produits/import-produits.js --shop "Boutique Annette" --dry-run
 *   node scripts/import-produits/import-produits.js --shop "Boutique Annette"
 *
 * Options : --csv  --images  --api  --shop  --max-images  --parallel (3)  --rate (80/min)  --upload-limit  --dry-run
 * Le mot de passe est saisi au clavier (masqué), il n'est jamais écrit nulle part.
 */
const fs = require('fs');
const path = require('path');
const readline = require('readline');

// ───────── Arguments ─────────
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (!a.startsWith('--')) continue;
  const k = a.slice(2);
  const next = process.argv[i + 1];
  if (next === undefined || next.startsWith('--')) args[k] = true;
  else { args[k] = next; i++; }
}
const CSV = args.csv || path.join(__dirname, 'PRODUITS_A_IMPORTER.csv');
const IMAGES = args.images || 'C:\\Users\\ADMIN\\Downloads\\IMAGES';
const API = String(args.api || 'http://localhost:3001/api/v1').replace(/\/+$/, '');
const SHOP = args.shop && args.shop !== true ? String(args.shop) : null;
const MAX_IMAGES = parseInt(args['max-images'] || '5', 10);
// Photos par heure : le script ne se bride plus tout seul. Si le serveur refuse (quota 60/h par
// défaut), il attend le temps indiqué par le serveur puis continue. Option --upload-limit pour se brider.
const UPLOAD_LIMIT = parseInt(args['upload-limit'] || '100000', 10);
const RATE_PER_MIN = parseInt(args.rate || '80', 10);       // le serveur accepte 100 requêtes/min/IP
const PARALLEL = Math.max(1, parseInt(args.parallel || '3', 10)); // produits traités en même temps
const DRY = !!args['dry-run'];
const LOG_FILE = path.join(__dirname, `import-log-${(SHOP || 'toutes').replace(/[^a-z0-9]+/gi, '_')}.json`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const norm = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

// ───────── CSV (séparateur ;) ─────────
function parseCsv(text) {
  text = text.replace(/^\uFEFF/, '');
  const rows = []; let row = []; let cur = ''; let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ';') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  const head = rows.shift().map((h) => h.trim());
  return rows.filter((r) => r.some((x) => x.trim())).map((r) => Object.fromEntries(head.map((h, i) => [h, (r[i] || '').trim()])));
}

// ───────── HTTP ─────────
let TOKEN = null;
// Régulateur : jamais plus de RATE_PER_MIN requêtes par minute (limite du serveur : 100/min/IP)
const reqTimes = [];
async function rateGate() {
  while (true) {
    const now = Date.now();
    while (reqTimes.length && now - reqTimes[0] > 60000) reqTimes.shift();
    if (reqTimes.length < RATE_PER_MIN) { reqTimes.push(now); return; }
    await sleep(reqTimes[0] + 60000 - now + 50);
  }
}
async function api(method, url, body, { form, retry = 3 } = {}) {
  for (let attempt = 1; attempt <= retry; attempt++) {
    const headers = {};
    if (TOKEN) headers.Authorization = `Bearer ${TOKEN}`;
    let payload;
    if (form) payload = form;
    else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
    let res;
    await rateGate();
    try { res = await fetch(API + url, { method, headers, body: payload }); }
    catch (e) { throw new Error(`Serveur injoignable (${API}) : ${e.message}`); }
    const txt = await res.text();
    let data; try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
    if (res.status === 429) {
      const m = /(\d+)\s*minute/i.exec(txt);
      const quota = /envois|upload/i.test(txt);
      const waitMs = quota ? ((m ? parseInt(m[1], 10) : 5) + 1) * 60000 : 65000;
      if (attempt < retry + (quota ? 40 : 0)) {
        console.log(`   … trop de requêtes, pause de ${Math.ceil(waitMs / 60000)} min`); await sleep(waitMs); retry = Math.max(retry, attempt + 1); continue;
      }
    }
    if (!res.ok) {
      const msg = data && data.message ? (Array.isArray(data.message) ? data.message.join(' / ') : data.message) : txt.slice(0, 200);
      const err = new Error(`${method} ${url} → ${res.status} : ${msg}`); err.status = res.status; throw err;
    }
    return data;
  }
}
const unwrap = (d) => (d && d.data && !Array.isArray(d) && d.data.id ? d.data : d);

function ask(question, hidden) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      rl._writeToOutput = (s) => { rl.output.write(s.startsWith(question) ? question : ''); };
    }
    rl.question(question, (a) => { rl.close(); if (hidden) process.stdout.write('\n'); resolve(a); });
  });
}

// ───────── Catégories ─────────
async function loadCategories() {
  const list = await api('GET', '/categories/flat');
  const arr = Array.isArray(list) ? list : (list.data || list.categories || []);
  const byId = new Map(arr.map((c) => [c.id, c]));
  const pathOf = (c) => { const parts = [c.name]; let p = c; while (p.parentId && byId.get(p.parentId)) { p = byId.get(p.parentId); parts.unshift(p.name); } return parts.join(' > '); };
  const map = new Map();
  for (const c of arr) map.set(norm(pathOf(c)), c.id);
  return map;
}

// ───────── Photos ─────────
function listPhotos(dossier) {
  const dir = path.join(IMAGES, dossier);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => /\.(jpe?g|png|webp)$/i.test(f)).sort().map((f) => path.join(dir, f));
}
const uploadTimes = [];
async function waitUploadSlot(n) {
  if (n > UPLOAD_LIMIT) throw new Error('--upload-limit est plus petit que le nombre de photos d\'un produit');
  const H = 3600 * 1000;
  while (true) {
    const now = Date.now();
    while (uploadTimes.length && now - uploadTimes[0] > H) uploadTimes.shift();
    if (uploadTimes.length + n <= UPLOAD_LIMIT) return;
    const wait = uploadTimes[0] + H - now + 5000;
    console.log(`   ⏳ quota de photos atteint (${UPLOAD_LIMIT}/h) : pause de ${Math.ceil(wait / 60000)} min…`);
    await sleep(Math.min(wait, 60000));
  }
}
// Envoie toutes les photos d'un produit en UNE requête (/upload/products/multiple, 10 max)
async function uploadPhotos(files) {
  if (!files.length) return [];
  await waitUploadSlot(files.length);
  const form = new FormData();
  for (const file of files) {
    const ext = path.extname(file).toLowerCase();
    const mime = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : 'image/jpeg';
    form.append('files', new Blob([fs.readFileSync(file)], { type: mime }), path.basename(file));
  }
  for (let i = 0; i < files.length; i++) uploadTimes.push(Date.now()); // le serveur compte aussi les refus
  const r = await api('POST', '/upload/products/multiple', undefined, { form });
  const list = Array.isArray(r) ? r : (r && Array.isArray(r.data) ? r.data : []);
  if (list.length !== files.length || list.some((d) => !d || !d.url)) throw new Error('Réponse d\'envoi incomplète');
  return list.map((d) => d.url);
}

// ───────── Programme principal ─────────
(async () => {
  if (!fs.existsSync(CSV)) { console.error('CSV introuvable : ' + CSV); process.exit(1); }
  let rows = parseCsv(fs.readFileSync(CSV, 'utf8'));
  if (SHOP) rows = rows.filter((r) => norm(r.boutique) === norm(SHOP));
  if (!rows.length) { console.error('Aucun produit pour cette boutique. Boutiques du CSV : ' + [...new Set(parseCsv(fs.readFileSync(CSV, 'utf8')).map((r) => r.boutique))].join(', ')); process.exit(1); }
  console.log(`\n${DRY ? 'SIMULATION (rien n\'est créé)' : 'IMPORT RÉEL'} — ${rows.length} produit(s)${SHOP ? ' pour « ' + SHOP + ' »' : ''}\nServeur : ${API}\n`);

  let categories;
  try { categories = await loadCategories(); }
  catch (e) { console.error('Impossible de lire les catégories : ' + e.message + '\nLe serveur est-il démarré ? As-tu lancé « npm run seed:categories » ?'); process.exit(1); }

  // Vérifications sans connexion
  const problems = [];
  for (const r of rows) {
    if (!categories.has(norm(r.categorie))) problems.push(`Catégorie introuvable pour « ${r.nom} » : ${r.categorie}`);
    const n = listPhotos(r.dossier_photos).length;
    if (!n) problems.push(`Aucune photo pour « ${r.nom} » (dossier ${r.dossier_photos})`);
    const stock = Number(r.stock);
    if (!Number.isInteger(stock) || stock < 0) problems.push(`Stock invalide pour « ${r.nom} » : ${r.stock}`);
    for (const f of listPhotos(r.dossier_photos).slice(0, MAX_IMAGES)) {
      const st = fs.statSync(f);
      if (st.size > 5 * 1024 * 1024) problems.push(`Photo trop lourde (> 5 Mo) : ${f}`);
      const fd = fs.openSync(f, 'r'); const b = Buffer.alloc(12); fs.readSync(fd, b, 0, 12, 0); fs.closeSync(fd);
      const okMagic = (b[0] === 0xFF && b[1] === 0xD8) || (b[0] === 0x89 && b.toString('latin1', 1, 4) === 'PNG') || (b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP');
      if (!okMagic) problems.push(`Format de photo non reconnu (JPG/PNG/WEBP attendu) : ${f}`);
    }
    const p = [Number(r.prix), Number(r.palier3), Number(r.palier6), Number(r.palier12)];
    if (p.some((x) => !Number.isFinite(x) || x <= 0)) problems.push(`Prix invalide pour « ${r.nom} »`);
  }
  if (DRY) {
    for (const r of rows) {
      const photos = listPhotos(r.dossier_photos);
      console.log(`• ${r.nom}\n    catégorie : ${r.categorie}\n    prix ${r.prix} F — stock ${r.stock} — paliers : 3+ → ${r.palier3} F, 6+ → ${r.palier6} F, 12+ → ${r.palier12} F\n    photos : ${Math.min(photos.length, MAX_IMAGES)} sur ${photos.length}`);
    }
    const total = rows.reduce((s, r) => s + Math.min(listPhotos(r.dossier_photos).length, MAX_IMAGES), 0);
    console.log(`\nPhotos à envoyer au total : ${total} (une seule requête par produit ; si le serveur limite à 60/h, le script attend tout seul).`);
    console.log(problems.length ? '\n⚠ Problèmes :\n - ' + problems.join('\n - ') : '\n✔ Tout est prêt : catégories trouvées, photos présentes.');
    return;
  }
  if (problems.length) { console.error('⚠ Corrige d\'abord :\n - ' + problems.join('\n - ')); process.exit(1); }

  // Connexion vendeur (saisie au clavier)
  console.log(`Connecte-toi avec le compte vendeur de « ${SHOP || 'la boutique'} ».`);
  const identifier = (await ask('E-mail ou téléphone : ', false)).trim();
  const password = await ask('Mot de passe (invisible) : ', true);
  const login = await api('POST', '/auth/login', { identifier, password });
  TOKEN = login.accessToken || (login.data && login.data.accessToken) || (login.tokens && login.tokens.accessToken);
  if (!TOKEN) { console.error('Connexion refusée ou réponse inattendue (compte non vérifié / double authentification ?).'); process.exit(1); }
  console.log('✔ Connecté.\n');

  // Produits déjà présents (pour ne pas créer de doublons)
  const existing = new Map();
  for (let page = 1; page < 50; page++) {
    const r = await api('GET', `/products/vendor/me?page=${page}&limit=50`);
    for (const p of r.data || []) existing.set(norm(p.prod_name || p.name), p);
    if (page >= (r.pages || 1)) break;
  }

  const log = [];
  let ok = 0, skip = 0, fail = 0;

  async function traiter(r) {
    const label = r.nom;
    const prev = existing.get(norm(r.nom));
    const vide = prev && !(prev.variants && prev.variants.length) && !(prev.images && prev.images.length);
    if (prev && !(vide && (prev.status === 'brouillon' || prev.status === 'inactive'))) {
      console.log(`↷ ${label} : existe déjà`);
      log.push({ nom: label, resultat: 'existe-deja', id: prev.id }); skip++; return;
    }
    let productId = prev ? prev.id : null;
    try {
      const photos = listPhotos(r.dossier_photos).slice(0, MAX_IMAGES);
      console.log(`${prev ? '↻ reprise de' : '+'} ${label}`);
      if (!productId) {
        const p = unwrap(await api('POST', '/products', {
          prod_name: r.nom, description: r.description, basePrice: Number(r.prix),
          status: 'brouillon', categoryIds: [categories.get(norm(r.categorie))],
        }));
        productId = p.id;
      }
      const urls = await uploadPhotos(photos);
      const sku = ('ASK-' + norm(r.boutique).slice(0, 3) + '-' + norm(r.nom).replace(/[^a-z0-9]+/g, '').slice(0, 14) + '-' + String(productId).slice(0, 6)).toUpperCase();
      await api('POST', `/products/${productId}/variants`, { sku, price: Number(r.prix), stockQuantity: Number(r.stock) });
      for (let i = 0; i < urls.length; i++) await api('POST', `/products/${productId}/images`, { imageUrl: urls[i], isPrimary: i === 0, isVideo: false });
      await api('PUT', `/products/${productId}/tier-prices`, [
        { minQuantity: 3, maxQuantity: 5, price: Number(r.palier3) },
        { minQuantity: 6, maxQuantity: 11, price: Number(r.palier6) },
        { minQuantity: 12, price: Number(r.palier12) },
      ]);
      await api('PUT', `/products/${productId}`, { status: 'active' });
      console.log(`   ✔ ${label} publié (${urls.length} photo(s))`);
      log.push({ nom: label, resultat: 'ok', id: productId, photos: urls.length }); ok++;
    } catch (e) {
      console.log(`   ✘ ${label} : ${e.message}`);
      log.push({ nom: label, resultat: 'echec', id: productId, erreur: e.message }); fail++;
    }
    fs.writeFileSync(LOG_FILE, JSON.stringify(log, null, 2));
  }

  // File d'attente : PARALLEL produits en même temps
  const file = rows.slice();
  await Promise.all(Array.from({ length: Math.min(PARALLEL, file.length) }, async () => {
    while (file.length) { const r = file.shift(); await traiter(r); }
  }));
  fs.writeFileSync(LOG_FILE, JSON.stringify(log, null, 2));
  console.log(`\nTerminé : ${ok} publié(s), ${skip} ignoré(s), ${fail} en échec. Journal : ${LOG_FILE}`);
  if (fail) console.log('Relance le script : les produits restés vides sont complétés sans doublon. Un produit à moitié rempli doit d\'abord être supprimé depuis l\'appli vendeur.');
})().catch((e) => { console.error('Erreur : ' + e.message); process.exit(1); });
