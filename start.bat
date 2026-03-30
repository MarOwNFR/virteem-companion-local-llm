@echo off
setlocal enabledelayedexpansion

if "%MODEL%"=="" set MODEL=llama3.1

:: --- Check prerequisites ---
if "%NGROK_AUTHTOKEN%"=="" (
    echo ERREUR: NGROK_AUTHTOKEN non defini.
    echo   Creez un compte gratuit sur https://ngrok.com et recuperez votre token.
    echo.
    echo Usage:
    echo   set NGROK_AUTHTOKEN=xxx
    echo   set MODEL=llama3.1
    echo   start.bat
    exit /b 1
)

:: --- Generate security token ---
if "%VIRTEEM_TOKEN%"=="" (
    for /f %%i in ('powershell -Command "[System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')"') do set VIRTEEM_TOKEN=%%i
)

:: --- Generate ngrok config ---
(
echo version: 2
echo authtoken: %NGROK_AUTHTOKEN%
echo tunnels:
echo   ollama:
echo     addr: ollama:11434
echo     proto: http
echo     traffic_policy:
echo       on_http_request:
echo         - expressions:
echo             - "req.headers['x-virteem-token'][0] != '%VIRTEEM_TOKEN%'"
echo           actions:
echo             - type: custom-response
echo               config:
echo                 status_code: 403
echo                 content: Unauthorized - Invalid Virteem token
) > ngrok-config.yml

:: --- Launch Docker Compose ---
docker compose up -d

echo.
echo Demarrage en cours...
echo   Modele: %MODEL%
echo   Le telechargement du modele peut prendre plusieurs minutes.
echo.

:: --- Wait for ngrok ---
set NGROK_URL=
for /l %%i in (1,1,30) do (
    for /f "delims=" %%u in ('curl -s http://localhost:4040/api/tunnels 2^>nul ^| powershell -Command "$input | ConvertFrom-Json | ForEach-Object { $_.tunnels[0].public_url }" 2^>nul') do set NGROK_URL=%%u
    if not "!NGROK_URL!"=="" goto :ngrok_ready
    timeout /t 2 /nobreak >nul
)

echo En attente de Ngrok... Verifiez votre NGROK_AUTHTOKEN.
exit /b 1

:ngrok_ready
echo ============================================================
echo.
echo   VIRTEEM LOCAL LLM - PRET
echo.
echo   URL du serveur:     %NGROK_URL%
echo   Token de securite:  %VIRTEEM_TOKEN%
echo   Modele:             %MODEL%
echo.
echo   Collez ces informations dans:
echo   Virteem Companion ^> Inference ^> Modeles ^> Local / Open Source
echo.
echo ============================================================
echo.
echo   Dashboard Ngrok:    http://localhost:4040
echo   Arreter:            docker compose down
echo   Logs:               docker compose logs -f
echo.
