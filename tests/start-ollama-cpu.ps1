# Starts Ollama in Docker (CPU) and pulls a lightweight model for tool calling.
# Usage (from this folder):
#   .\start-ollama-cpu.ps1
#   $env:MODEL = "qwen2.5:3b"; .\start-ollama-cpu.ps1
#
# Default: llama3.2:3b (~2 GB) - balanced size and reliability for function calling (MCP, web search).
# Smaller but less reliable for tools: llama3.2:1b

$ErrorActionPreference = "Stop"
$Model = if ($env:MODEL) { $env:MODEL } else { "llama3.2:3b" }

Set-Location $PSScriptRoot

Write-Host "Starting Ollama (CPU) on port 11434..." -ForegroundColor Cyan
docker compose up -d ollama

Write-Host "Waiting for the Ollama service..."
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

Write-Host "Pulling model: $Model (the first run may take several minutes on a small PC)..." -ForegroundColor Yellow
$env:MODEL = $Model
docker compose run --rm model-loader

Write-Host ""
Write-Host "=== Ready ===" -ForegroundColor Green
Write-Host "OpenAI-compatible API: http://localhost:11434/v1"
Write-Host "In Virteem Companion > Inference > Local: URL = http://localhost:11434"
Write-Host "Model to select: $Model"
Write-Host ""
Write-Host "Stop: docker compose down"
Write-Host "Cloud tunnel (Ngrok): please see docs/LOCAL_LLM_SETUP.md or run docker compose --profile tunnel up -d"
Write-Host ""
