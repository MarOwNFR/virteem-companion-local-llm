# Demarre Ollama en Docker (CPU) + telecharge le modele leger pour tool calling.
# Usage (depuis ce dossier) :
#   .\start-ollama-cpu.ps1
#   $env:MODEL = "qwen2.5:3b"; .\start-ollama-cpu.ps1
#
# Defaut : llama3.2:3b (~2 Go) — bon compromis taille / fiabilite pour function calling (MCP, web search).
# Plus petit mais moins fiable pour les outils : llama3.2:1b

$ErrorActionPreference = "Stop"
$Model = if ($env:MODEL) { $env:MODEL } else { "llama3.2:3b" }

Set-Location $PSScriptRoot

Write-Host "Demarrage Ollama (CPU) sur le port 11434..." -ForegroundColor Cyan
docker compose up -d ollama

Write-Host "Attente du service Ollama..."
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

Write-Host "Telechargement du modele : $Model (premiere fois : plusieurs minutes sur petit PC)..." -ForegroundColor Yellow
$env:MODEL = $Model
docker compose run --rm model-loader

Write-Host ""
Write-Host "=== Pret ===" -ForegroundColor Green
Write-Host "API OpenAI-compatible : http://localhost:11434/v1"
Write-Host "Dans Virteem Companion > Inference > Local : URL = http://localhost:11434"
Write-Host "Modele a selectionner : $Model"
Write-Host ""
Write-Host "Arret : docker compose down"
Write-Host "Tunnel cloud (ngrok) : voir docs/LOCAL_LLM_SETUP.md ou docker compose --profile tunnel up -d"
Write-Host ""
