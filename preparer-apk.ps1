# =====================================================================
#  Asoukaa - Fabrique l'APK de test pour les telephones Android
# =====================================================================
#  A lancer depuis le dossier du projet Flutter, clic droit > "Executer
#  avec PowerShell", ou dans un terminal :  .\preparer-apk.ps1
#
#  Ce script fait trois choses tout seul :
#    1. il trouve l'adresse de ce PC sur le Wi-Fi ;
#    2. il autorise cette adresse dans la configuration de securite
#       Android (sans quoi l'APK bloquerait tous les appels en silence) ;
#    3. il fabrique l'APK en y inscrivant cette adresse.
#
#  Resultat : plus besoin de retaper une adresse a la main, meme si la
#  box en attribue une nouvelle apres un redemarrage.
# =====================================================================

$ErrorActionPreference = "Stop"
$port = 3001

Write-Host ""
Write-Host "=== Asoukaa : preparation de l'APK de test ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Trouver l'adresse de ce PC sur le reseau ----------------------
# On prend la carte reseau qui a une passerelle par defaut : c'est celle
# qui est reellement connectee (Wi-Fi ou cable), pas une carte virtuelle.
$config = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } |
    Select-Object -First 1

if ($null -eq $config) {
    Write-Host "ERREUR : aucune connexion reseau active trouvee." -ForegroundColor Red
    Write-Host "Connecte ce PC au Wi-Fi, puis relance ce script."
    exit 1
}

$ip = $config.IPv4Address.IPAddress
Write-Host "Adresse de ce PC sur le reseau : $ip" -ForegroundColor Green
Write-Host "Carte utilisee : $($config.InterfaceAlias)"
Write-Host ""

# --- 2. Autoriser cette adresse cote Android -------------------------
$xml = "android\app\src\main\res\xml\network_security_config.xml"

if (-not (Test-Path $xml)) {
    Write-Host "ERREUR : fichier de securite reseau introuvable." -ForegroundColor Red
    Write-Host "Attendu ici : $xml"
    exit 1
}

$contenu = Get-Content $xml -Raw -Encoding UTF8

if ($contenu -notmatch "ADRESSES-LAN-DEBUT") {
    Write-Host "ERREUR : reperes ADRESSES-LAN-DEBUT / FIN absents du fichier." -ForegroundColor Red
    Write-Host "Ajoute l'adresse $ip a la main dans : $xml"
    exit 1
}

if ($contenu -match [regex]::Escape($ip)) {
    Write-Host "Cette adresse est deja autorisee cote Android." -ForegroundColor Green
} else {
    $ligne = '        <domain includeSubdomains="false">' + $ip + '</domain>'
    $contenu = $contenu -replace "(?s)(ADRESSES-LAN-DEBUT[^>]*-->)", ("`$1`r`n" + $ligne)
    # Ecriture SANS BOM : un BOM en tete d'un XML de ressources peut faire
    # echouer la compilation Android. Set-Content -Encoding UTF8 en ajoute
    # un sous Windows PowerShell, d'ou cette ecriture explicite.
    $sansBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Resolve-Path $xml), $contenu, $sansBom)
    Write-Host "Adresse $ip ajoutee aux adresses autorisees." -ForegroundColor Yellow
}
Write-Host ""

# --- 3. Fabriquer l'APK ----------------------------------------------
$api = "http://" + $ip + ":" + $port
Write-Host "Construction de l'APK (compte 3 a 5 minutes)..." -ForegroundColor Cyan
Write-Host "Adresse du serveur inscrite dans l'appli : $api"
Write-Host ""

flutter build apk --release --dart-define=API_BASE_URL=$api

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "La construction a echoue. Lis le message ci-dessus." -ForegroundColor Red
    exit 1
}

$apk = "build\app\outputs\flutter-apk\app-release.apk"
Write-Host ""
Write-Host "=== TERMINE ===" -ForegroundColor Green
Write-Host "Fichier a envoyer a tes collegues :" -ForegroundColor Green
Write-Host (Resolve-Path $apk)
Write-Host ""
Write-Host "Rappels :" -ForegroundColor Yellow
Write-Host " - ton serveur doit tourner (port $port) pendant les tests"
Write-Host " - tout le monde doit etre sur le meme Wi-Fi que ce PC"
Write-Host " - a la 1re installation, autoriser les 'sources inconnues'"
Write-Host ""
