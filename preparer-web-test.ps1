# =====================================================================
#  Asoukaa - Fabrique la VERSION WEB pour le serveur de test en ligne
# =====================================================================
#  A lancer dans le dossier du projet Flutter :  .\preparer-web-test.ps1
#  Resultat : le dossier "deploiement-web" est pret a etre envoye sur
#  Railway (voir DEPLOIEMENT_TEST_RAILWAY.md, partie "Version web").
#  Adresse de l'API par defaut : https://api-test.asoukaa.com
# =====================================================================
param([string]$api = "https://api-test.asoukaa.com")
$ErrorActionPreference = "Stop"
Write-Host "Construction de la version web (1 a 3 minutes)..." -ForegroundColor Cyan
Write-Host "Adresse de l'API inscrite dans l'appli : $api"
flutter build web --release --dart-define=API_BASE_URL=$api
if ($LASTEXITCODE -ne 0) { Write-Host "La construction a echoue. Lis le message ci-dessus." -ForegroundColor Red; exit 1 }
if (Test-Path "deploiement-web\site") { Remove-Item -Recurse -Force "deploiement-web\site" }
Copy-Item -Recurse "build\web" "deploiement-web\site"
Write-Host ""
Write-Host "=== TERMINE : dossier 'deploiement-web' pret a envoyer sur Railway ===" -ForegroundColor Green
