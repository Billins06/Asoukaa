# =====================================================================
#  Asoukaa - Lance la version web, pour tester depuis un iPhone
# =====================================================================
#  Un iPhone ne peut pas installer un APK (format Android uniquement),
#  et fabriquer une vraie appli iPhone demande un Mac + un compte Apple
#  payant. En attendant, cette version web s'ouvre dans Safari et
#  permet de tester les memes ecrans.
#
#  A lancer :  .\lancer-web-iphone.ps1
#  Puis laisser cette fenetre OUVERTE pendant les tests.
# =====================================================================

$ErrorActionPreference = "Stop"
$portApi = 3001
$portWeb = 8080

Write-Host ""
Write-Host "=== Asoukaa : version web pour iPhone et navigateurs ===" -ForegroundColor Cyan
Write-Host ""

$config = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } |
    Select-Object -First 1

if ($null -eq $config) {
    Write-Host "ERREUR : aucune connexion reseau active trouvee." -ForegroundColor Red
    exit 1
}

$ip = $config.IPv4Address.IPAddress
$api = "http://" + $ip + ":" + $portApi

Write-Host "Adresse de ce PC : $ip" -ForegroundColor Green
Write-Host ""
Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
Write-Host " A DONNER A TES COLLEGUES (iPhone comme Android) :" -ForegroundColor Yellow
Write-Host ""
Write-Host "    http://${ip}:${portWeb}" -ForegroundColor White
Write-Host ""
Write-Host " Ils ouvrent cette adresse dans Safari ou Chrome." -ForegroundColor Yellow
Write-Host " Laisse cette fenetre ouverte pendant les tests." -ForegroundColor Yellow
Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-Host "Demarrage (la 1re fois peut prendre 1 a 2 minutes)..." -ForegroundColor Cyan
Write-Host ""

flutter run -d web-server --web-hostname=0.0.0.0 --web-port=$portWeb --dart-define=API_BASE_URL=$api
