# =====================================================================
#  Asoukaa - APK de test connecte au SERVEUR EN LIGNE (plus de Wi-Fi/tunnel)
# =====================================================================
#  .\preparer-apk-ligne.ps1                      (adresse par defaut ci-dessous)
#  .\preparer-apk-ligne.ps1 -api https://autre-adresse.com
#  Cet APK marche partout (4G, Wi-Fi), PC eteint. A refaire seulement quand
#  le CODE DE L'APPLI change (pas quand seul le serveur change).
# =====================================================================
param([string]$api = "https://api-test.asoukaa.com")
$ErrorActionPreference = "Stop"
Write-Host "Construction de l'APK (3 a 5 minutes)... serveur : $api" -ForegroundColor Cyan
flutter build apk --release --dart-define=API_BASE_URL=$api
if ($LASTEXITCODE -ne 0) { Write-Host "La construction a echoue." -ForegroundColor Red; exit 1 }
Write-Host ""
Write-Host "=== TERMINE ===" -ForegroundColor Green
Write-Host "Fichier a envoyer : build\app\outputs\flutter-apk\app-release.apk"
