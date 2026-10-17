# =====================================================================
#  Asoukaa - Tunnel pour tester a distance (Android et iPhone)
# =====================================================================
#  A lancer depuis le dossier du projet Flutter :  .\lancer-tunnel.ps1
#
#  Ce script :
#    1. verifie que ton serveur (backend) tourne sur ce PC ;
#    2. ouvre un "tunnel" Cloudflare : une adresse https publique qui
#       pointe vers ton PC ;
#    3. t'affiche l'adresse du jour et la copie dans le presse-papiers,
#       avec un message pret a coller dans WhatsApp.
#
#  Si Windows refuse de lancer le script :
#     powershell -ExecutionPolicy Bypass -File .\lancer-tunnel.ps1
#
#  IMPORTANT :
#    - garde cette fenetre OUVERTE : si tu la fermes, le tunnel s'arrete ;
#    - ton PC doit rester allume, avec le serveur lance (npm run start:dev) ;
#    - l'adresse CHANGE a chaque lancement : renvoie la nouvelle a tes collegues.
# =====================================================================

$ErrorActionPreference = "Stop"
$port = 3001
$journal = Join-Path $env:TEMP "asoukaa-tunnel.log"

Write-Host ""
Write-Host "=== Asoukaa : tunnel pour les tests a distance ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Le serveur tourne-t-il ? ---------------------------------------
$serveurOk = $false
try {
    $client = New-Object System.Net.Sockets.TcpClient
    $attente = $client.BeginConnect("127.0.0.1", $port, $null, $null)
    $serveurOk = $attente.AsyncWaitHandle.WaitOne(1500) -and $client.Connected
    $client.Close()
} catch { $serveurOk = $false }

if (-not $serveurOk) {
    Write-Host "ATTENTION : rien n'ecoute sur le port $port." -ForegroundColor Yellow
    Write-Host "Lance d'abord le serveur dans le dossier backend :  npm run start:dev"
    $rep = Read-Host "Continuer quand meme ? (o/N)"
    if ($rep -notmatch '^[oOyY]') { exit 1 }
} else {
    Write-Host "Serveur detecte sur le port $port." -ForegroundColor Green
}

# --- 2. Trouver (ou installer) cloudflared ------------------------------
$cloudflared = $null
$cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cmd) { $cloudflared = $cmd.Source }
if (-not $cloudflared) {
    $local = Join-Path $PSScriptRoot "cloudflared.exe"
    if (Test-Path $local) { $cloudflared = $local }
}
if (-not $cloudflared) {
    Write-Host ""
    Write-Host "cloudflared (l'outil qui fabrique le tunnel) n'est pas installe." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $rep = Read-Host "Je l'installe maintenant avec winget ? (O/n)"
        if ($rep -notmatch '^[nN]') {
            winget install --id Cloudflare.cloudflared -e --accept-package-agreements --accept-source-agreements
            # Recharger le PATH de la session pour trouver le programme tout juste installe
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
            $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($cmd) { $cloudflared = $cmd.Source }
        }
    }
}
if (-not $cloudflared) {
    Write-Host ""
    Write-Host "Installation manuelle : telecharge cloudflared-windows-amd64.exe sur" -ForegroundColor Red
    Write-Host "  https://github.com/cloudflare/cloudflared/releases/latest"
    Write-Host "renomme-le en cloudflared.exe, mets-le dans ce dossier, puis relance ce script."
    exit 1
}
Write-Host "cloudflared trouve : $cloudflared" -ForegroundColor Green

# --- 3. Ouvrir le tunnel -------------------------------------------------
$journalSortie = Join-Path $env:TEMP "asoukaa-tunnel-out.log"
foreach ($f in @($journal, $journalSortie)) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
Write-Host ""
Write-Host "Ouverture du tunnel, patiente quelques secondes..." -ForegroundColor Cyan

$arguments = @("tunnel", "--no-autoupdate", "--protocol", "http2", "--url", "http://127.0.0.1:$port")
$processus = Start-Process -FilePath $cloudflared -ArgumentList $arguments `
    -RedirectStandardError $journal -RedirectStandardOutput $journalSortie `
    -NoNewWindow -PassThru

try {
    # --- 4. Lire l'adresse du jour dans le journal -----------------------
    $adresse = $null
    for ($i = 0; $i -lt 60 -and -not $adresse; $i++) {
        Start-Sleep -Milliseconds 500
        if ($processus.HasExited) { break }
        if (Test-Path $journal) {
            $texte = Get-Content $journal -Raw -ErrorAction SilentlyContinue
            if ($texte -match 'https://(?!api\.)[a-z0-9-]+\.trycloudflare\.com') { $adresse = $Matches[0] }
        }
    }

    if (-not $adresse) {
        Write-Host ""
        Write-Host "ERREUR : le tunnel ne s'est pas ouvert." -ForegroundColor Red
        Write-Host "Journal : $journal"
        if (Test-Path $journal) { Get-Content $journal -Tail 15 }
        exit 1
    }

    # --- 5. Verifier que l'adresse repond (peut prendre ~10 s) -----------
    Write-Host "Verification de l'adresse..." -ForegroundColor Cyan
    $repond = $false
    for ($i = 0; $i -lt 15 -and -not $repond; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "$adresse/api/v1/products?limit=1" -UseBasicParsing -TimeoutSec 8
            $repond = $true
        } catch {
            # Une reponse HTTP < 500 (meme 401/404) prouve que le tunnel marche ;
            # 502/530 = tunnel pas encore pret ou serveur arrete : on reessaie.
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -gt 0 -and $code -lt 500) { $repond = $true } else { Start-Sleep -Seconds 2 }
        }
    }

    # --- 6. Afficher et copier -------------------------------------------
    $message = "Salut ! Pour tester Asoukaa a distance : ouvre l'appli, fais un appui long (2 secondes) sur le logo Asoukaa de la page de connexion, colle cette adresse puis appuie sur Enregistrer :`n$adresse"
    try { Set-Clipboard -Value $message } catch {}

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host "  ADRESSE DU JOUR :" -ForegroundColor Green
    Write-Host "  $adresse" -ForegroundColor White
    Write-Host "=====================================================" -ForegroundColor Green
    if (-not $repond) {
        Write-Host "(L'adresse ne repond pas encore : attends 10-20 s avant de l'envoyer.)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Le message pour WhatsApp est deja COPIE : ouvre WhatsApp et fais Ctrl+V." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Message copie :"
    Write-Host $message
    Write-Host ""
    Write-Host "Garde cette fenetre ouverte. Ctrl+C ou fermeture = tunnel coupe." -ForegroundColor Yellow

    # --- 7. Rester allume tant que le tunnel tourne ----------------------
    $processus.WaitForExit()
    Write-Host ""
    Write-Host "Le tunnel s'est arrete." -ForegroundColor Red
}
finally {
    if ($processus -and -not $processus.HasExited) {
        Stop-Process -Id $processus.Id -Force -ErrorAction SilentlyContinue
    }
}
