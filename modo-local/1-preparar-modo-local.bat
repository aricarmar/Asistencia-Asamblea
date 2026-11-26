@echo off
chcp 65001 >nul
title Preparar el modo sin internet - Asamblea Trebolis
cd /d "%~dp0.."
echo.
echo ============================================================
echo   PREPARAR EL MODO SIN INTERNET  (hazlo en casa, CON internet)
echo ============================================================
echo.
echo === Paso 1 de 3: instalando lo que necesita la API ===
cd api
call npm install --omit=dev
if errorlevel 1 goto error
cd ..
echo.
echo === Paso 2 de 3: compilando la app web para usarla sin internet ===
cd app
call flutter pub get
if errorlevel 1 goto error
call flutter build web --release --no-web-resources-cdn --dart-define=API_URL=
if errorlevel 1 goto error
cd ..
echo.
echo === Paso 3 de 3: copiando la app web a la API ===
if exist api\publico rmdir /s /q api\publico
xcopy /e /i /q app\build\web api\publico >nul
if errorlevel 1 goto error
echo.
echo ============================================================
echo   LISTO. El dia de la asamblea usa 2-iniciar-modo-local.bat
echo   (ese ya no necesita internet).
echo ============================================================
pause
exit /b 0

:error
echo.
echo *** Hubo un error. Toma una foto de esta ventana y enviala. ***
pause
exit /b 1
