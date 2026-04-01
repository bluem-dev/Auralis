@echo off
setlocal enabledelayedexpansion

:: ============================================
:: ANTI-CIERRE: relanzar en cmd /k si doble clic
:: ============================================
if "%~1"=="" (
    cmd /k "%~f0" CALLED
    exit /b
)

cd /d "%~dp0"

echo ===========================
echo Auralis - Go/Wails Compiler
echo ===========================
echo.

:: ============================================
:: CONFIGURACION DE DESPLIEGUE
:: Cambiar DEPLOY_DIR segun el entorno local.
:: Si la ruta no existe, el bat la crea automaticamente.
:: Dejar vacio para omitir el copiado del ejecutable.
:: ============================================
set "DEPLOY_DIR=????"

set FINAL_CODE=0

:: ============================================
:: [1/5] VERIFICACION DE DEPENDENCIAS
:: ============================================
echo [1/5] Verificando dependencias...
echo.

:: Go
where go >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Go no encontrado.
    echo          Instalar desde: https://go.dev/dl/
    set FINAL_CODE=1
    goto :fin
)
for /f "tokens=3" %%v in ('go version') do set GO_VER=%%v
echo   [OK] Go           %GO_VER%

:: Wails CLI
where wails >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   [AVISO] Wails CLI no encontrado.
    echo.
    set /p WAILS_INST="   Desea instalarlo ahora con 'go install'? (s/n): "
    if /i "!WAILS_INST!"=="s" (
        echo.
        echo   Instalando Wails CLI...
        call go install github.com/wailsapp/wails/v2/cmd/wails@latest
        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo   [ERROR] La instalacion de Wails fallo.
            echo          Intentalo manualmente: go install github.com/wailsapp/wails/v2/cmd/wails@latest
            set FINAL_CODE=1
            goto :fin
        )
        echo   [OK] Wails instalado correctamente.
    ) else (
        echo.
        echo   [ERROR] Wails es requerido para compilar. Abortando.
        set FINAL_CODE=1
        goto :fin
    )
)
for /f "tokens=2" %%v in ('wails version 2^>^&1') do set WAILS_VER=%%v
echo   [OK] Wails        %WAILS_VER%

:: Node.js
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Node.js no encontrado.
    echo          Instalar desde: https://nodejs.org/
    set FINAL_CODE=1
    goto :fin
)
for /f %%v in ('node --version') do set NODE_VER=%%v
echo   [OK] Node.js      %NODE_VER%

:: Compilador C (CGO_ENABLED=1 es obligatorio — Wails v2 requiere CGO para WebView2)
where gcc >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   [ERROR] GCC no encontrado. CGO_ENABLED=1 es obligatorio para Wails v2.
    echo          Instalar MinGW-w64 x86: https://www.mingw-w64.org/
    echo          O via MSYS2: pacman -S mingw-w64-i686-gcc
    set FINAL_CODE=1
    goto :fin
)
for /f "tokens=3" %%v in ('gcc --version 2^>^&1 ^| findstr /r "[0-9]"') do (
    set GCC_VER=%%v
    goto :gcc_ver_done
)
:gcc_ver_done
echo   [OK] GCC          %GCC_VER%
echo.

:: ============================================
:: [2/5] DEPENDENCIAS FRONTEND (npm install)
:: ============================================
echo [2/5] Instalando dependencias frontend (npm install)...
echo.

call npm install --prefix frontend
set NPM_EXIT=%ERRORLEVEL%
if %NPM_EXIT% NEQ 0 (
    echo.
    echo   [ERROR] npm install fallo [exit code: %NPM_EXIT%]
    set FINAL_CODE=%NPM_EXIT%
    goto :fin
)
echo   [OK] Dependencias frontend listas.
echo.

:: ============================================
:: [3/5] DEPENDENCIAS GO (go mod tidy)
:: ============================================
echo [3/5] Sincronizando modulos Go (go mod tidy)...
echo.

call go mod tidy
set TIDY_EXIT=%ERRORLEVEL%
if %TIDY_EXIT% NEQ 0 (
    echo.
    echo   [ERROR] go mod tidy fallo [exit code: %TIDY_EXIT%]
    set FINAL_CODE=%TIDY_EXIT%
    goto :fin
)
echo   [OK] Modulos Go sincronizados.
echo.

:: ============================================
:: ENTORNO DE COMPILACION
::
:: GOARCH=386    — obligatorio. Las DLLs de DTS (dtsdecoderdll.dll, DtsJobQueue)
::                 son PE32 (x86). Un proceso x64 no puede cargarlas en su espacio
::                 de memoria. GOARCH=386 produce un PE32 compatible.
::
:: CGO_ENABLED=1 — obligatorio. Wails v2 en Windows usa CGO para inicializar
::                 WebView2. Sin esto el ejecutable no levanta la UI.
::
:: NO cambiar estos valores.
:: ============================================
set GOARCH=386
set GOOS=windows
set CGO_ENABLED=1

:: Leer version desde wails.json
set APP_VERSION=dev
for /f "delims=" %%v in ('node -e "try{const j=require('./wails.json');process.stdout.write(j.info&&j.info.productVersion||'dev')}catch(e){process.stdout.write('dev')}"') do set APP_VERSION=%%v
echo   Version detectada: %APP_VERSION%
echo.

:: ============================================
:: [4/5] SELECCION DE MODO
:: ============================================
echo [4/5] Modo de compilacion...
echo.
echo   [1] Produccion  --  wails build -clean -platform windows/386
echo       Genera el ejecutable final en build\bin\
echo.
echo   [2] Desarrollo  --  wails dev
echo       Levanta servidor con hot-reload en localhost:5173
echo.

:modo_input
set /p BUILD_MODE="   Ingrese opcion (1/2): "
if "%BUILD_MODE%"=="1" goto :build_prod
if "%BUILD_MODE%"=="2" goto :build_dev
echo   Opcion invalida. Ingrese 1 o 2.
goto :modo_input

:: ============================================
:: [5/5] BUILD - PRODUCCION
:: ============================================
:build_prod
echo.
echo [5/5] Compilando en modo produccion...
echo.

:: Preservar DLLs y EXEs externos antes de -clean
:: (wails build -clean elimina build\bin\ completo antes de compilar)
set BACKUP_DIR=build\_bin_backup
set BIN_DIR=build\bin

if exist "%BIN_DIR%\" (
    echo   Preservando dependencias de %BIN_DIR%\...
    if not exist "%BACKUP_DIR%\" mkdir "%BACKUP_DIR%"

    :: Carpetas (conf, display, lib, etc.)
    for /d %%d in ("%BIN_DIR%\*") do (
        xcopy /e /i /y /q "%%d" "%BACKUP_DIR%\%%~nd\" >nul 2>&1
    )
    :: Archivos sueltos — excluir el ejecutable principal (sera reemplazado)
    for %%f in ("%BIN_DIR%\*") do (
        if /i not "%%~nxf"=="auralis.exe" (
            copy /y "%%f" "%BACKUP_DIR%\" >nul
        )
    )
    echo   [OK] Dependencias preservadas.
    echo.
)

:: Marcar tiempo de inicio (segundos desde medianoche, robusto a locales)
for /f "tokens=1-4 delims=:.,/ " %%a in ("%TIME: =0%") do (
    set /a "T_START=(1%%a%%100)*3600+(1%%b%%100)*60+(1%%c%%100)"
)

:: Compilar
call wails build -clean -platform windows/386 -ldflags "-X auralis/internal/app.AppVersion=%APP_VERSION%"
set BUILD_EXIT=%ERRORLEVEL%

:: Restaurar dependencias
if exist "%BACKUP_DIR%\" (
    echo.
    echo   Restaurando dependencias...
    xcopy /e /i /y /q "%BACKUP_DIR%\" "%BIN_DIR%\" >nul
    rmdir /s /q "%BACKUP_DIR%"
    echo   [OK] Dependencias restauradas.
)

:: Compilar auxiliares (despues del build para que -clean no los elimine)
if %BUILD_EXIT% EQU 0 (
    echo.
    echo   Compilando auralis-enc.exe...
    go build -o "%BIN_DIR%\auralis-enc.exe" .\cmd\auralis-enc
    if !ERRORLEVEL! NEQ 0 (
        echo   [AVISO] auralis-enc.exe fallo. La app funciona pero sin encoder nativo.
        set BUILD_EXIT=2
    ) else (
        echo   [OK] auralis-enc.exe compilado.
    )
)

:: auralis-notify.exe - proceso auxiliar amd64 para notificaciones WinRT.
if %BUILD_EXIT% EQU 0 (
    echo.
    echo   Compilando auralis-notify.exe (amd64)
    set GOARCH=amd64
    go build -o "%BIN_DIR%\auralis-notify.exe" .\cmd\auralis-notify
    set GOARCH=386
    if !ERRORLEVEL! NEQ 0 (
        echo   [AVISO] auralis-notify.exe fallo. Las notificaciones WinRT no estaran disponibles.
        echo          La app funciona normalmente con el toast interno como fallback.
    ) else (
        echo   [OK] auralis-notify.exe compilado ^(amd64^).
    )
)

:: Tiempo transcurrido
for /f "tokens=1-4 delims=:.,/ " %%a in ("%TIME: =0%") do (
    set /a "T_END=(1%%a%%100)*3600+(1%%b%%100)*60+(1%%c%%100)"
)
set /a T_ELAPSED=T_END-T_START
if %T_ELAPSED% LSS 0 set /a T_ELAPSED+=86400
set /a T_MIN=T_ELAPSED/60
set /a T_SEC=T_ELAPSED%%60

echo.
echo ============================================

if %BUILD_EXIT% EQU 0 (
    echo   BUILD EXITOSO
    echo   Duracion: %T_MIN%m %T_SEC%s
    echo ============================================
    echo.

    :: Copiar ejecutable al directorio de despliegue (si esta configurado)
    if not "!DEPLOY_DIR!"=="" (
        if not exist "!DEPLOY_DIR!\" mkdir "!DEPLOY_DIR!"
        echo   Copiando binarios a:
        echo   !DEPLOY_DIR!
        copy /y "%BIN_DIR%\auralis.exe" "!DEPLOY_DIR!\auralis.exe" >nul
        copy /y "%BIN_DIR%\auralis-enc.exe" "!DEPLOY_DIR!\auralis-enc.exe" >nul
        copy /y "%BIN_DIR%\auralis-notify.exe" "!DEPLOY_DIR!\auralis-notify.exe" >nul
        copy /y "%BIN_DIR%\orb.exe" "!DEPLOY_DIR!\orb.exe" >nul
        if !ERRORLEVEL! EQU 0 (
            echo   [OK] Ejecutable copiado correctamente.
        ) else (
            echo   [AVISO] No se pudo copiar el ejecutable al directorio de destino.
        )

        echo.
        echo   Abriendo carpeta de salida...
        explorer.exe "!DEPLOY_DIR!"
    )
) else (
    echo   BUILD FALLIDO  [exit code: %BUILD_EXIT%]
    echo   Duracion: %T_MIN%m %T_SEC%s
    echo ============================================
    echo.
    echo   Revisa los errores arriba antes de continuar.
    set FINAL_CODE=%BUILD_EXIT%
)

goto :fin

:: ============================================
:: [5/5] BUILD - DESARROLLO
:: ============================================
:build_dev
echo.
echo [5/5] Iniciando modo desarrollo...
echo.
echo   GOARCH=%GOARCH% activo — el dev server compila como x86.
echo   Servidor disponible en: http://localhost:5173
echo   Presiona Ctrl+C para detener.
echo.

:: -goflags fuerza GOARCH=386 dentro del proceso wails dev
call wails dev -goflags "-gcflags=all=-e"
set BUILD_EXIT=%ERRORLEVEL%

if %BUILD_EXIT% NEQ 0 (
    echo.
    echo   [ERROR] wails dev termino con error [exit code: %BUILD_EXIT%]
    set FINAL_CODE=%BUILD_EXIT%
)

:: ============================================
:: UNICO PUNTO DE SALIDA
:: ============================================
:fin
echo.
PAUSE
exit /b %FINAL_CODE%
