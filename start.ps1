$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

function Import-DotEnv {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Normalize-YesNo {
    param(
        [string]$Value,
        [string]$Default = "yes"
    )

    $normalized = if ($null -eq $Value) { "" } else { $Value.ToLowerInvariant() }

    switch ($normalized) {
        { $_ -in @("y", "yes", "true", "1") } { return "yes" }
        { $_ -in @("n", "no", "false", "0") } { return "no" }
        default { return $Default }
    }
}

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            continue
        }

        $currentName = $line.Substring(0, $separatorIndex).Trim()
        if ($currentName -ne $Name) {
            continue
        }

        $value = $line.Substring($separatorIndex + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        return $value
    }

    return $null
}
$DotEnvPath = Join-Path $PSScriptRoot ".env"
Import-DotEnv -Path $DotEnvPath

$Model = if ($env:MODEL) { $env:MODEL } else { "llama3.2:3b" }
$UseGpu = Normalize-YesNo -Value $env:USE_GPU -Default "yes"
$UseNgrok = Normalize-YesNo -Value $env:USE_NGROK -Default "yes"
$FixedVirteemToken = Get-DotEnvValue -Path $DotEnvPath -Name "VIRTEEM_TOKEN"
$VirteemToken = $FixedVirteemToken

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is not installed or not available in PATH."
}

if ($UseNgrok -eq "yes") {
    if (-not $env:NGROK_AUTHTOKEN) {
        throw "NGROK_AUTHTOKEN is required when USE_NGROK=yes."
    }

    if (-not $VirteemToken) {
        $VirteemToken = [Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N")
    }

    @"
version: 2
authtoken: $($env:NGROK_AUTHTOKEN)
tunnels:
  ollama:
    addr: ollama:11434
    proto: http
    traffic_policy:
      on_http_request:
        - expressions:
            - "!( 'x-virteem-token' in req.headers ) || req.headers['x-virteem-token'][0] != '$VirteemToken'"
          actions:
            - type: custom-response
              config:
                status_code: 403
                content: Unauthorized - Invalid Virteem token
"@ | Set-Content -Path (Join-Path $PSScriptRoot "ngrok-config.yml") -Encoding utf8
}

$composeArgs = @("-f", "docker-compose.yml")
if ($UseGpu -eq "yes") {
    $composeArgs += @("-f", "docker-compose.gpu.yml")
}

Write-Host ""
Write-Host "Starting services..." -ForegroundColor Cyan
Write-Host "  Model:  $Model"
Write-Host "  GPU:    $UseGpu"
Write-Host "  Ngrok:  $UseNgrok"
Write-Host ""

if ($UseNgrok -eq "yes") {
    & docker compose @composeArgs up -d ollama
} else {
    & docker compose @composeArgs up -d
}
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$ollamaContainer = $null
for ($i = 0; $i -lt 30; $i++) {
    $containerOutput = & docker compose @composeArgs ps -q ollama
    if ($null -eq $containerOutput) {
        $ollamaContainer = ""
    } else {
        $ollamaContainer = ([string]($containerOutput -join [Environment]::NewLine)).Trim()
    }
    if ($ollamaContainer) {
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $ollamaContainer) {
    throw "Unable to retrieve the Ollama container."
}

Write-Host "Waiting for the Ollama service..."
$ollamaReady = $false
for ($i = 0; $i -lt 90; $i++) {
    & docker exec $ollamaContainer ollama list *> $null
    if ($LASTEXITCODE -eq 0) {
        $ollamaReady = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $ollamaReady) {
    throw "Ollama did not become available in time."
}

Write-Host "Pulling model: $Model" -ForegroundColor Yellow
& docker exec $ollamaContainer ollama pull $Model
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($UseNgrok -eq "yes") {
    & docker compose @composeArgs --profile tunnel up -d --force-recreate ngrok
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    Write-Host "Retrieving the Ngrok URL..."
    $publicUrl = $null
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $tunnels = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 3
            if ($tunnels.tunnels -and $tunnels.tunnels.Count -gt 0) {
                $publicUrl = $tunnels.tunnels[0].public_url
                break
            }
        } catch {
        }
        Start-Sleep -Seconds 2
    }

    if (-not $publicUrl) {
        throw "Ngrok is not reachable at http://127.0.0.1:4040."
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  VIRTEEM LOCAL LLM - READY" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Server URL:         $publicUrl"
    Write-Host "  Virteem Token:      $VirteemToken"
    Write-Host "  Model:              $Model"
    Write-Host ""
    Write-Host "  Please paste these values into:"
    Write-Host "  Virteem Companion > Inference > Models > Local / Open Source"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Dashboard Ngrok:    http://127.0.0.1:4040"
    Write-Host "  Stop:               docker compose $($composeArgs -join ' ') --profile tunnel down"
    Write-Host "  Logs:               docker compose $($composeArgs -join ' ') logs -f"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  VIRTEEM LOCAL LLM - READY" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Local URL:          http://127.0.0.1:11434"
    Write-Host "  Model:              $Model"
    Write-Host ""
    Write-Host "  Please use this URL in Virteem Companion for local-only usage."
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Stop:               docker compose $($composeArgs -join ' ') down"
    Write-Host "  Logs:               docker compose $($composeArgs -join ' ') logs -f"
    Write-Host ""
}
