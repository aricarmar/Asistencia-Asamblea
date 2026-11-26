@echo off
chcp 65001 >nul
title Asamblea Trebolis - SERVIDOR SIN INTERNET (no cerrar esta ventana)
cd /d "%~dp0..\api"
if not exist node_modules goto falta
if not exist publico\index.html goto falta

echo.
echo ============================================================
echo   ASAMBLEA TREBOLIS - MODO SIN INTERNET
echo ============================================================
echo.
set /p PGPASSWORD=Contraseña de PostgreSQL (la de pgAdmin) y Enter: 
set /p ADMIN_CLAVE=Contraseña para la administradora (solo se usa la primera vez) y Enter: 
set DATABASE_URL=postgres://postgres@localhost:5432/asistencia_asamblea
set PGSSL=false
set PORT=3000
set TOKEN_SECRETO=asamblea-trebolis-modo-local
echo.
echo Iniciando... NO cierres esta ventana mientras dure la asamblea.
echo Si Windows pregunta por el Firewall, marca "Redes privadas" y "Redes publicas" y dale Permitir.
echo.
node src\servidor.js
echo.
echo El servidor se detuvo. Si hubo un error, toma una foto de esta ventana.
pause
exit /b 0

:falta
echo.
echo Primero ejecuta 1-preparar-modo-local.bat (con internet).
pause
exit /b 1
