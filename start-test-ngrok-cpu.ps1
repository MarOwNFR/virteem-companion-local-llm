# Test client : Ollama (CPU) + modele 3B + tunnel Ngrok + token Virteem.
# Sur petit PC sans GPU : ca ne "explose" pas le PC, mais les reponses peuvent prendre 30s–2 min
# par generation (normal). Prevoyez ~4–6 Go RAM libres pour llama3.2:3b.
#
# Usage (PowerShell, depuis ce dossier) :
#   Copiez .env.example vers .env et renseignez NGROK_AUTHTOKEN, ou :
#   $env:NGROK_AUTHTOKEN = "votre_token_ngrok"
#   .\start-test-ngrok-cpu.ps1
#
# Optionnel : $env:MODEL = "qwen2.5:3b"   (defaut : llama3.2:3b)

$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $i = $line.IndexOf("=")
        if ($i -lt 1) { return }
        $name = $line.Substring(0, $i).Trim()
        $val = $line.Substring($i + 1).Trim()
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        [Environment]::SetEnvironmentVariable($name, $val, "Process")
    }
}

if (-not $env:NGROK_AUTHTOKEN) {
    Write-Host "ERREUR: definissez NGROK_AUTHTOKEN (compte gratuit https://ngrok.com)" -ForegroundColor Red
    Write-Host '  $env:NGROK_AUTHTOKEN = "xxx"' -ForegroundColor Yellow
    exit 1
}

$Model = if ($env:MODEL) { $env:MODEL } else { "llama3.2:3b" }
if (-not $env:VIRTEEM_TOKEN) {
    $env:VIRTEEM_TOKEN = [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')
}

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "=== Test Ngrok + 3B en CPU ===" -ForegroundColor Cyan
Write-Host "- Modele : $Model (~2 Go disque, ~4 Go RAM en charge)" -ForegroundColor Gray
Write-Host "- CPU uniquement : les premieres reponses peuvent etre TRES lentes (c'est normal)." -ForegroundColor Yellow
Write-Host ""

# Config ngrok (meme logique que start.bat)
$token = $env:VIRTEEM_TOKEN
$ngrokAuth = $env:NGROK_AUTHTOKEN
@"
version: 2
authtoken: $ngrokAuth
tunnels:
  ollama:
    addr: ollama:11434
    proto: http
    traffic_policy:
      on_http_request:
        - expressions:
            - "req.headers['x-virteem-token'][0] != '$token'"
          actions:
            - type: custom-response
              config:
                status_code: 403
                content: Unauthorized - Invalid Virteem token
"@ | Set-Content -Path "ngrok-config.yml" -Encoding utf8

Write-Host "Demarrage Ollama..." -ForegroundColor Cyan
docker compose up -d ollama

Write-Host "Attente API Ollama (localhost:11434)..."
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

Write-Host "Telechargement du modele $Model (long la 1ere fois)..." -ForegroundColor Yellow
$env:MODEL = $Model
docker compose run --rm model-loader

Write-Host "Demarrage tunnel Ngrok (profile tunnel)..." -ForegroundColor Cyan
docker compose --profile tunnel up -d ngrok

Write-Host "Recuperation de l'URL publique..."
Start-Sleep -Seconds 4
$publicUrl = $null
for ($i = 0; $i -lt 20; $i++) {
    try {
        $t = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 5
        if ($t.tunnels -and $t.tunnels.Count -gt 0) {
            $publicUrl = $t.tunnels[0].public_url
            break
        }
    } catch { }
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  COLLEZ DANS VIRTEEM COMPANION (Local)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  URL serveur :  $publicUrl"
Write-Host "  Token        :  $token"
Write-Host "  Modele       :  $Model"
Write-Host ""
Write-Host "  (Inference > Local > Tester puis choisir le modele)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Dashboard ngrok : http://127.0.0.1:4040" -ForegroundColor Gray
Write-Host "  Arret           : docker compose --profile tunnel down" -ForegroundColor Gray
Write-Host ""

if (-not $publicUrl) {
    Write-Host "ATTENTION: URL ngrok non lue (4040). Verifiez le token ngrok et relancez." -ForegroundColor Red
}
