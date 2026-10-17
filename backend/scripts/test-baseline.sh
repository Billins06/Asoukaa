#!/usr/bin/env bash
# =============================================================================
# Test de la migration de base (src/database/migrations/1700000000000-BaselineSchema.ts)
#
# Rejoue la vérification complète sur des bases JETABLES (préfixe asoukaa_bltest_) :
#   1. base vide  -> npm run typeorm:run : 0 erreur, puis 2e passage = rien à faire ;
#      le schéma obtenu = celui de `synchronize` (aux différences expliquées près) ;
#      les migrations existantes ne modifient plus rien après la migration de base ;
#   2. base « déjà installée » (schéma complet + données, sans la migration de base
#      dans la table des migrations) : la migration de base ne change RIEN ;
#   3. annulation (down) : sans danger sur une base installée, refusée en production.
#
# Ce script ne touche JAMAIS à votre vraie base : il crée et supprime ses propres
# bases de test, sur le serveur PostgreSQL JETABLE que vous lui indiquez.
# Il n'a besoin que de Node + des dépendances du projet (npm install déjà fait).
#
# Utilisation (depuis le dossier backend) :
#   1. Un PostgreSQL jetable, par exemple avec Docker :
#        docker run --rm -d --name pg-bltest -e POSTGRES_PASSWORD=test -p 55432:5432 postgres:16
#   2. Lancer le test :
#        BL_DB_PORT=55432 BL_DB_PASSWORD=test bash scripts/test-baseline.sh
#      (ou une seule partie : ... test-baseline.sh vide | installee | annulation1 | annulation2)
#   3. Arrêter le serveur jetable : docker stop pg-bltest
#
# Variables : BL_DB_HOST (127.0.0.1), BL_DB_PORT (5432), BL_DB_USER (postgres),
#             BL_DB_PASSWORD (obligatoire). Un hôte autre que localhost est refusé
#             sauf si BL_ALLOW_REMOTE=oui (à éviter : ne visez jamais la production).
# =============================================================================
cd "$(dirname "$0")/.." || exit 2

SCENARIO="${1:-tout}"
export DB_HOST="${BL_DB_HOST:-127.0.0.1}"
export DB_PORT="${BL_DB_PORT:-5432}"
export DB_USER="${BL_DB_USER:-postgres}"
export DB_PASSWORD="${BL_DB_PASSWORD:-}"
export TS_NODE_TRANSPILE_ONLY=true
unset DB_SYNCHRONIZE DB_LOGGING BASELINE_DOWN_CONFIRM
export NODE_ENV=development

if [ -z "$DB_PASSWORD" ]; then echo "BL_DB_PASSWORD manquant (voir l'en-tête du script)."; exit 2; fi
case "$DB_HOST" in
  127.0.0.1|localhost) ;;
  *) if [ "${BL_ALLOW_REMOTE:-}" != "oui" ]; then
       echo "Hôte $DB_HOST refusé : ce test doit viser un PostgreSQL JETABLE local (BL_ALLOW_REMOTE=oui pour forcer)."; exit 2
     fi ;;
esac

TMP="$(mktemp -d)"
P="asoukaa_bltest_$$"
OK=0; KO=0
verifier() { # verifier "description" code_de_sortie
  if [ "$2" -eq 0 ]; then echo "  [OK] $1"; OK=$((OK+1)); else echo "  [ECHEC] $1"; KO=$((KO+1)); fi
}
outil() { node -r ts-node/register/transpile-only -r tsconfig-paths/register scripts/baseline-tools.js "$@"; }
migrer() { DB_NAME="$1" npm run typeorm:run > "$TMP/$2.log" 2>&1; }
annuler() { DB_NAME="$1" npm run typeorm:revert > "$TMP/$2.log" 2>&1; }
nettoyer() { for b in vide synchro base installee prod; do outil dropdb "${P}_$b" >/dev/null 2>&1; done; rm -rf "$TMP"; }
trap nettoyer EXIT

NB_MIGRATIONS=$(ls src/database/migrations/*.ts | wc -l)
echo "Migrations dans le code : $NB_MIGRATIONS (dont la migration de base)"

# ----------------------------------------------------------------------------
if [ "$SCENARIO" = "tout" ] || [ "$SCENARIO" = "vide" ]; then
echo; echo "== 1. Serveur VIDE =="
outil createdb "${P}_vide" || exit 2
migrer "${P}_vide" run1; verifier "premier 'typeorm:run' sur base vide : 0 erreur" $?
NB=$(grep -c "has been executed successfully" "$TMP/run1.log")
[ "$NB" -eq "$NB_MIGRATIONS" ]; verifier "les $NB_MIGRATIONS migrations sont exécutées (trouvé : $NB)" $?
grep -q "BaselineSchema1700000000000 has been executed" "$TMP/run1.log"; verifier "la migration de base s'exécute (et en premier)" $?
FIRST=$(grep -m1 "has been executed successfully" "$TMP/run1.log")
case "$FIRST" in *Baseline*) R=0;; *) R=1;; esac; verifier "ordre : la migration de base passe AVANT les autres" $R
migrer "${P}_vide" run2; verifier "deuxième 'typeorm:run' : 0 erreur" $?
grep -q "No migrations are pending" "$TMP/run2.log"; verifier "deuxième passage : rien à faire" $?

outil createdb "${P}_synchro" && outil sync "${P}_synchro"; verifier "schéma de référence créé par synchronize (entités)" $?
outil signature "${P}_vide" > "$TMP/sig_vide.txt"; outil signature "${P}_synchro" > "$TMP/sig_synchro.txt"
diff --unchanged-line-format= --old-line-format='< %L' --new-line-format='> %L' "$TMP/sig_synchro.txt" "$TMP/sig_vide.txt" > "$TMP/diff_vide.txt"
diff -q "$TMP/diff_vide.txt" scripts/baseline-diff-attendu.txt >/dev/null; S=$?
verifier "schéma obtenu = schéma de synchronize, aux différences expliquées près (scripts/baseline-diff-attendu.txt)" $S
if [ $S -ne 0 ]; then echo "    Différences trouvées :"; sed 's/^/      /' "$TMP/diff_vide.txt" | head -40; fi

outil createdb "${P}_base" && outil baseline-only "${P}_base" && outil signature "${P}_base" > "$TMP/sig_base.txt"
diff -q "$TMP/sig_base.txt" "$TMP/sig_vide.txt" >/dev/null
verifier "après la migration de base, les migrations existantes ne modifient plus rien (aucun doublon d'index, etc.)" $?
fi

# ----------------------------------------------------------------------------
if [ "$SCENARIO" = "tout" ] || [ "$SCENARIO" = "installee" ]; then
echo; echo "== 2. Base DÉJÀ INSTALLÉE (schéma + données, migration de base inconnue) =="
outil createdb "${P}_installee" && outil sync "${P}_installee" && outil migrate-no-baseline "${P}_installee" && outil seed-sample "${P}_installee"
verifier "base « existante » préparée (synchronize + migrations existantes + données d'exemple)" $?
outil signature "${P}_installee" > "$TMP/sig_avant.txt"; outil rowcounts "${P}_installee" > "$TMP/n_avant.txt"
migrer "${P}_installee" run3; verifier "'typeorm:run' sur la base existante : 0 erreur" $?
grep -q "BaselineSchema1700000000000 has been executed" "$TMP/run3.log"; verifier "la migration de base est enregistrée comme exécutée" $?
grep -q "CREATE TABLE" "$TMP/run3.log"; [ $? -ne 0 ]; verifier "aucun CREATE TABLE n'a été lancé" $?
outil signature "${P}_installee" > "$TMP/sig_apres.txt"; outil rowcounts "${P}_installee" > "$TMP/n_apres.txt"
diff -q "$TMP/sig_avant.txt" "$TMP/sig_apres.txt" >/dev/null; verifier "schéma strictement identique avant / après" $?
diff -q "$TMP/n_avant.txt" "$TMP/n_apres.txt" >/dev/null; verifier "nombre de lignes de chaque table identique avant / après" $?
grep -q "^delivery_zones 2$" "$TMP/n_apres.txt"; verifier "les données d'exemple sont toujours là" $?
migrer "${P}_installee" run4; grep -q "No migrations are pending" "$TMP/run4.log"; verifier "nouveau passage : rien à faire" $?
fi

# ----------------------------------------------------------------------------
if [ "$SCENARIO" = "tout" ] || [ "$SCENARIO" = "annulation" ] || [ "$SCENARIO" = "annulation1" ]; then
echo; echo "== 3a. Annulation (down) sur une base déjà installée =="
outil createdb "${P}_installee" && outil sync "${P}_installee" && outil migrate-no-baseline "${P}_installee" && outil seed-sample "${P}_installee"
migrer "${P}_installee" run5
outil rowcounts "${P}_installee" > "$TMP/n_a.txt"
annuler "${P}_installee" rev1; verifier "base installée : 'typeorm:revert' tombe sur la migration de base sans rien casser" $?
grep -q "Migration BaselineSchema1700000000000 has been reverted" "$TMP/rev1.log"; verifier "c'est bien la migration de base qui a été « annulée » (et non une vraie migration)" $?
grep -q "rien à supprimer ici" "$TMP/rev1.log"; verifier "son down() a signalé qu'il n'y avait rien à supprimer" $?
outil rowcounts "${P}_installee" > "$TMP/n_b.txt"
diff -q "$TMP/n_a.txt" "$TMP/n_b.txt" >/dev/null; verifier "base installée : aucune table ni donnée perdue" $?

fi

if [ "$SCENARIO" = "tout" ] || [ "$SCENARIO" = "annulation" ] || [ "$SCENARIO" = "annulation2" ]; then
echo; echo "== 3b. Annulation (down) quand la migration de base est la seule enregistrée =="
outil createdb "${P}_prod" && outil baseline-only "${P}_prod"
outil signature "${P}_prod" > "$TMP/s0.txt"
NODE_ENV=production annuler "${P}_prod" rev2; [ $? -ne 0 ]; verifier "NODE_ENV=production : l'annulation est REFUSÉE" $?
grep -q "down() refusé : NODE_ENV=production" "$TMP/rev2.log"; verifier "NODE_ENV=production : le message de refus est bien celui de la migration de base" $?
outil signature "${P}_prod" > "$TMP/s1.txt"; diff -q "$TMP/s0.txt" "$TMP/s1.txt" >/dev/null; verifier "NODE_ENV=production : rien n'a été supprimé" $?
annuler "${P}_prod" rev3; [ $? -ne 0 ]; verifier "hors production sans confirmation : annulation REFUSÉE" $?
grep -q "BASELINE_DOWN_CONFIRM=OUI" "$TMP/rev3.log"; verifier "sans confirmation : le message explique comment confirmer" $?
outil signature "${P}_prod" > "$TMP/s2.txt"; diff -q "$TMP/s0.txt" "$TMP/s2.txt" >/dev/null; verifier "sans confirmation : rien n'a été supprimé" $?
BASELINE_DOWN_CONFIRM=OUI annuler "${P}_prod" rev4; verifier "base de test + BASELINE_DOWN_CONFIRM=OUI : annulation acceptée" $?
outil rowcounts "${P}_prod" > "$TMP/n_c.txt"; [ ! -s "$TMP/n_c.txt" ]; verifier "après confirmation : toutes les tables ont disparu (base de test)" $?
fi

echo; echo "== RÉSULTAT : $OK vérifications réussies, $KO échec(s) =="
[ "$KO" -eq 0 ]
