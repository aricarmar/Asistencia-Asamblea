@echo off
chcp 65001 >nul
title Abrir el puerto 3000 en el Firewall
echo Este archivo debe abrirse con clic derecho - "Ejecutar como administrador".
netsh advfirewall firewall add rule name="Asamblea Trebolis (puerto 3000)" dir=in action=allow protocol=TCP localport=3000
echo.
echo Si dice "Aceptar", los celulares ya pueden conectarse a este computador.
pause
