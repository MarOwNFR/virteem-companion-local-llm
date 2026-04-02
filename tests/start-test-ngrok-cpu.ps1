# Test client: Ollama (CPU) + 3B model + Ngrok tunnel + Virteem token.
# On a small PC without a GPU, this should remain usable, but responses may take 30s to 2 min
# per generation, which is expected. Please allow ~4-6 GB of free RAM for llama3.2:3b.
#
# Usage (PowerShell, from this folder):
#   Please copy .env.example to .env and define NGROK_AUTHTOKEN, or:
#   $env:NGROK_AUTHTOKEN = "your_ngrok_token"
#   .\start-test-ngrok-cpu.ps1
#
# Optional: $env:MODEL = "qwen2.5:3b"   (default: llama3.2:3b)

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
    Write-Host "ERROR: Please define NGROK_AUTHTOKEN (free account at https://ngrok.com)." -ForegroundColor Red
    Write-Host '  $env:NGROK_AUTHTOKEN = "xxx"' -ForegroundColor Yellow
    exit 1
}

$Model = if ($env:MODEL) { $env:MODEL } else { "llama3.2:3b" }
if (-not $env:VIRTEEM_TOKEN) {
    $env:VIRTEEM_TOKEN = [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')
}

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "=== Ngrok + 3B CPU Test ===" -ForegroundColor Cyan
Write-Host "- Model: $Model (~2 GB disk, ~4 GB RAM under load)" -ForegroundColor Gray
Write-Host "- CPU only: the first responses may be VERY slow, which is expected." -ForegroundColor Yellow
Write-Host ""

# Ngrok config using the same logic as start.bat
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
            - "!( 'x-virteem-token' in req.headers ) || req.headers['x-virteem-token'][0] != '$token'"
          actions:
            - type: custom-response
              config:
                status_code: 403
                content: Unauthorized - Invalid Virteem token
"@ | Set-Content -Path "ngrok-config.yml" -Encoding utf8

Write-Host "Starting Ollama..." -ForegroundColor Cyan
docker compose up -d ollama

Write-Host "Waiting for the Ollama API (localhost:11434)..."
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

Write-Host "Pulling model $Model (the first run may take a while)..." -ForegroundColor Yellow
$env:MODEL = $Model
docker compose run --rm model-loader

Write-Host "Starting the Ngrok tunnel (tunnel profile)..." -ForegroundColor Cyan
docker compose --profile tunnel up -d ngrok

Write-Host "Retrieving the public URL..."
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
Write-Host "  PLEASE PASTE INTO VIRTEEM COMPANION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Server URL   :  $publicUrl"
Write-Host "  Token        :  $token"
Write-Host "  Model        :  $Model"
Write-Host ""
Write-Host "  (Inference > Local > Test, then select the model)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Ngrok dashboard : http://127.0.0.1:4040" -ForegroundColor Gray
Write-Host "  Stop            : docker compose --profile tunnel down" -ForegroundColor Gray
Write-Host ""

if (-not $publicUrl) {
    Write-Host "WARNING: The Ngrok URL could not be read from port 4040. Please verify the Ngrok token and try again." -ForegroundColor Red
}
