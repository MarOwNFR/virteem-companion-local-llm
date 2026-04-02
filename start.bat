@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

call :load_env ".env"

if not defined MODEL set "MODEL=llama3.2:3b"
if not defined USE_GPU set "USE_GPU=yes"
if not defined USE_NGROK set "USE_NGROK=yes"
set "VIRTEEM_TOKEN_VALUE="
call :get_env_value ".env" "VIRTEEM_TOKEN" VIRTEEM_TOKEN_VALUE

call :normalize_yes_no USE_GPU yes
call :normalize_yes_no USE_NGROK yes

where docker >nul 2>nul
if errorlevel 1 (
    echo ERROR: Docker is not installed or not available in PATH.
    exit /b 1
)

if /i "%USE_NGROK%"=="yes" (
    if not defined NGROK_AUTHTOKEN (
        echo ERROR: NGROK_AUTHTOKEN is required when USE_NGROK=yes.
        echo   Please define it in .env or in your environment.
        exit /b 1
    )
    if not defined VIRTEEM_TOKEN_VALUE (
        for /f %%i in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')"') do set "VIRTEEM_TOKEN_VALUE=%%i"
    )
    call :write_ngrok_config
)

set "COMPOSE_FILES=-f docker-compose.yml"
if /i "%USE_GPU%"=="yes" set "COMPOSE_FILES=%COMPOSE_FILES% -f docker-compose.gpu.yml"

echo.
echo Starting services...
echo   Model:  %MODEL%
echo   GPU:    %USE_GPU%
echo   Ngrok:  %USE_NGROK%
echo.

if /i "%USE_NGROK%"=="yes" (
    docker compose %COMPOSE_FILES% up -d ollama
) else (
    docker compose %COMPOSE_FILES% up -d
)
if errorlevel 1 exit /b 1

set "OLLAMA_CONTAINER="
for /l %%i in (1,1,30) do (
    if not defined OLLAMA_CONTAINER (
        for /f "delims=" %%c in ('docker compose %COMPOSE_FILES% ps -q ollama 2^>nul') do set "OLLAMA_CONTAINER=%%c"
        if not defined OLLAMA_CONTAINER timeout /t 2 /nobreak >nul
    )
)

if defined OLLAMA_CONTAINER goto :wait_ollama
echo ERROR: Unable to retrieve the Ollama container.
exit /b 1

:wait_ollama
echo Waiting for the Ollama service...
set "OLLAMA_READY="
for /l %%i in (1,1,90) do (
    if not defined OLLAMA_READY (
        docker exec !OLLAMA_CONTAINER! ollama list >nul 2>nul && set "OLLAMA_READY=1"
        if not defined OLLAMA_READY timeout /t 2 /nobreak >nul
    )
)

if defined OLLAMA_READY goto :ollama_ready
echo ERROR: Ollama did not become available in time.
exit /b 1

:ollama_ready
echo Pulling model: %MODEL%
docker exec !OLLAMA_CONTAINER! ollama pull "%MODEL%"
if errorlevel 1 exit /b 1

if /i "%USE_NGROK%"=="yes" (
    docker compose %COMPOSE_FILES% --profile tunnel up -d --force-recreate ngrok
    if errorlevel 1 exit /b 1
    goto :wait_ngrok
)
goto :local_ready

:wait_ngrok
echo Retrieving the Ngrok URL...
set "NGROK_URL="
for /l %%i in (1,1,30) do (
    if not defined NGROK_URL (
        for /f "usebackq delims=" %%u in (`curl -s http://127.0.0.1:4040/api/tunnels 2^>nul ^| powershell -NoProfile -Command "$raw = [Console]::In.ReadToEnd(); if ($raw) { try { $t = ConvertFrom-Json -InputObject $raw; if ($t.tunnels -and $t.tunnels.Count -gt 0) { $t.tunnels[0].public_url } } catch {} }"`) do set "NGROK_URL=%%u"
        if not defined NGROK_URL timeout /t 2 /nobreak >nul
    )
)

if defined NGROK_URL goto :ngrok_ready
echo ERROR: Ngrok is not reachable at http://127.0.0.1:4040
exit /b 1

:ngrok_ready
echo ============================================================
echo.
echo   VIRTEEM LOCAL LLM - READY
echo.
echo   Server URL:         %NGROK_URL%
echo   Virteem Token:      %VIRTEEM_TOKEN_VALUE%
echo   Model:              %MODEL%
echo.
echo   Please paste these values into:
echo   Virteem Companion ^> Inference ^> Models ^> Local / Open Source
echo.
echo ============================================================
echo.
echo   Dashboard Ngrok:    http://127.0.0.1:4040
echo   Stop:               docker compose %COMPOSE_FILES% --profile tunnel down
echo   Logs:               docker compose %COMPOSE_FILES% logs -f
echo.
exit /b 0

:local_ready
echo ============================================================
echo.
echo   VIRTEEM LOCAL LLM - READY
echo.
echo   Local URL:          http://127.0.0.1:11434
echo   Model:              %MODEL%
echo.
echo   Please use this URL in Virteem Companion for local-only usage.
echo.
echo ============================================================
echo.
echo   Stop:               docker compose %COMPOSE_FILES% down
echo   Logs:               docker compose %COMPOSE_FILES% logs -f
echo.
exit /b 0

:load_env
set "ENV_FILE=%~1"
if not exist "%ENV_FILE%" exit /b 0
for /f "usebackq tokens=* delims=" %%L in ("%ENV_FILE%") do call :parse_env_line "%%L"
exit /b 0

:parse_env_line
set "LINE=%~1"
if not defined LINE exit /b 0
if "%LINE:~0,1%"=="#" exit /b 0
for /f "tokens=1* delims==" %%A in ("%LINE%") do (
    set "KEY=%%~A"
    set "VALUE=%%~B"
)
if not defined KEY exit /b 0
for /f "tokens=* delims= " %%A in ("%KEY%") do set "KEY=%%~A"
if not defined %KEY% (
    if defined VALUE (
        set "FIRST=!VALUE:~0,1!"
        set "LAST=!VALUE:~-1!"
        if "!FIRST!!LAST!"=="\"\"" set "VALUE=!VALUE:~1,-1!"
        if "!FIRST!!LAST!"=="''" set "VALUE=!VALUE:~1,-1!"
    )
    set "%KEY%=%VALUE%"
)
set "KEY="
set "VALUE="
set "LINE="
exit /b 0

:normalize_yes_no
set "CURRENT=!%~1!"
if not defined CURRENT set "CURRENT=%~2"
if /i "!CURRENT!"=="y" set "CURRENT=yes"
if /i "!CURRENT!"=="yes" set "CURRENT=yes"
if /i "!CURRENT!"=="true" set "CURRENT=yes"
if /i "!CURRENT!"=="1" set "CURRENT=yes"
if /i "!CURRENT!"=="n" set "CURRENT=no"
if /i "!CURRENT!"=="no" set "CURRENT=no"
if /i "!CURRENT!"=="false" set "CURRENT=no"
if /i "!CURRENT!"=="0" set "CURRENT=no"
if /i not "!CURRENT!"=="yes" if /i not "!CURRENT!"=="no" set "CURRENT=%~2"
set "%~1=!CURRENT!"
exit /b 0

:get_env_value
setlocal EnableDelayedExpansion
set "ENV_FILE=%~1"
set "TARGET_KEY=%~2"
set "RESULT="
if exist "%ENV_FILE%" (
    for /f "usebackq tokens=* delims=" %%L in ("%ENV_FILE%") do (
        set "LINE=%%L"
        if defined LINE if not "!LINE:~0,1!"=="#" (
            for /f "tokens=1* delims==" %%A in ("!LINE!") do (
                set "KEY=%%~A"
                set "VALUE=%%~B"
            )
            if /i "!KEY!"=="!TARGET_KEY!" (
                set "FIRST=!VALUE:~0,1!"
                set "LAST=!VALUE:~-1!"
                if "!FIRST!!LAST!"=="\"\"" set "VALUE=!VALUE:~1,-1!"
                if "!FIRST!!LAST!"=="''" set "VALUE=!VALUE:~1,-1!"
                set "RESULT=!VALUE!"
            )
        )
    )
)
endlocal & set "%~3=%RESULT%"
exit /b 0

:write_ngrok_config
setlocal DisableDelayedExpansion
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
echo             - "!( 'x-virteem-token' in req.headers ) || req.headers['x-virteem-token'][0] != '%VIRTEEM_TOKEN_VALUE%'"
echo           actions:
echo             - type: custom-response
echo               config:
echo                 status_code: 403
echo                 content: Unauthorized - Invalid Virteem token
) > ngrok-config.yml
endlocal
exit /b 0
