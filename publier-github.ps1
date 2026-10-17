# =====================================================================
#  Asoukaa - Envoie (commit + push) un projet sur GitHub, en securite
# =====================================================================
#  A lancer DANS le dossier du projet :   .\publier-github.ps1
#  Optionnel : .\publier-github.ps1 -message "Mon texte"
#
#  Le script : 1) montre la branche et l'adresse GitHub ;
#              2) prepare les fichiers (jamais .env, keystore, env.json, sauvegardes) ;
#              3) cherche des cles secretes dans ce qui part ;
#              4) te demande confirmation, puis commit + push.
#  Ton mot de passe / jeton GitHub reste dans Windows : je ne le vois jamais.
# =====================================================================
param([string]$message = "Corrections, remboursements, paiements, coupons, import de produits")
$brancheAttendue = "asoukaa_front"
$ErrorActionPreference = "Stop"

git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Ce dossier n'est pas un projet git." -ForegroundColor Red; exit 1 }

$racine = git rev-parse --show-toplevel
$branche = git branch --show-current
Write-Host ""
Write-Host "Projet  : $racine"
Write-Host "Branche : $branche"
Write-Host "GitHub  : $(git remote get-url origin)"
Write-Host ""
if ($branche -ne $brancheAttendue) {
    Write-Host "ATTENTION : tu es sur la branche '$branche' mais ce projet doit etre envoye sur '$brancheAttendue'." -ForegroundColor Red
    Write-Host "Change de branche avec :  git switch $brancheAttendue   (puis relance le script)" -ForegroundColor Yellow
    exit 1
}

# Un ancien verrou git oublie bloque tout (fichier vide, plus de 10 minutes)
$verrou = Join-Path $racine ".git\index.lock"
if (Test-Path $verrou) {
    $age = (Get-Date) - (Get-Item $verrou).LastWriteTime
    if ($age.TotalMinutes -gt 10 -and (Get-Item $verrou).Length -eq 0) {
        Remove-Item $verrou -Force
        Write-Host "Ancien verrou git supprime." -ForegroundColor Yellow
    } else { Write-Host "Un autre git semble tourner (verrou recent). Ferme-le puis relance." -ForegroundColor Red; exit 1 }
}

git add -A .

# 1) Fichiers interdits
$envoyes = @(git diff --cached --name-only)
$interdits = @($envoyes | Where-Object {
    ($_ -match '(^|/)\.env' -and $_ -notmatch '\.example$') -or
    $_ -match '\.(keystore|jks|pem)$' -or $_ -match 'key\.properties$' -or
    $_ -match '(^|/)env\.json$' -or $_ -match '\.bak' -or $_ -match '(^|/)_sauvegardes'
})
if ($interdits.Count -gt 0) {
    git reset -q
    Write-Host "STOP : ces fichiers ne doivent pas partir sur GitHub :" -ForegroundColor Red
    $interdits | ForEach-Object { Write-Host "  $_" }
    Write-Host "Ajoute-les au .gitignore puis relance."
    exit 1
}

# 2) Cles secretes dans le contenu
$motif = 'sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|fp_[A-Za-z0-9]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sbp_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}'
$suspect = git diff --cached -U0 | Select-String -Pattern $motif
if ($suspect) {
    git reset -q
    Write-Host "STOP : une cle secrete semble presente dans les fichiers (ligne masquee)." -ForegroundColor Red
    Write-Host "Cherche : $motif"
    exit 1
}

Write-Host "$($envoyes.Count) fichier(s) prets a partir :" -ForegroundColor Cyan
git diff --cached --stat | Select-Object -Last 15
Write-Host ""
$ok = Read-Host "Envoyer sur GitHub (branche $branche) ? tape  o  pour oui"
if ($ok -ne "o") { git reset -q; Write-Host "Annule, rien n'a ete envoye."; exit 0 }

git commit -m $message
if ($LASTEXITCODE -ne 0) { Write-Host "Rien a envoyer ou commit refuse." -ForegroundColor Yellow; exit 0 }
git push origin $branche
if ($LASTEXITCODE -ne 0) {
    Write-Host "Le push a echoue (connexion GitHub ?). Le commit est fait : relance seulement  git push origin $branche" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "=== TERMINE : projet envoye sur GitHub ===" -ForegroundColor Green
