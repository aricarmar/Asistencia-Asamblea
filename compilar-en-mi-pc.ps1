# Compila la app de Windows y el APK en este PC y los deja en el Escritorio, carpeta "Asamblea Trebolis".
$ErrorActionPreference = 'Continue'
$api = 'https://asistencia-asamblea-api.onrender.com'
$web = 'https://aricarmar.github.io/Asistencia-Asamblea/'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$escritorio = [Environment]::GetFolderPath('Desktop')
$destino = Join-Path $escritorio 'Asamblea Trebolis'

function Paso($texto) { Write-Host ''; Write-Host "=== $texto ===" -ForegroundColor Green }
function Fallo($texto) {
  Write-Host ''
  Write-Host "*** $texto ***" -ForegroundColor Red
  Write-Host 'Toma una foto de esta ventana y enviala.' -ForegroundColor Red
  Read-Host 'Presiona Enter para cerrar'
  exit 1
}

Set-Location (Join-Path $raiz 'app')
New-Item -ItemType Directory -Force -Path $destino | Out-Null

Paso 'Paso 1 de 4: preparando el proyecto (Windows, Android y web)'
flutter create --platforms=windows,android,web --org co.asamblea --project-name asistencia_asamblea .
if ($LASTEXITCODE -ne 0) { Fallo 'No se pudo preparar el proyecto' }
# Titulo de la ventana de Windows
$main = 'windows\runner\main.cpp'
if (Test-Path $main) {
  $codigo = Get-Content $main -Raw
  $codigo = $codigo -replace 'L"asistencia_asamblea"', 'L"Asamblea Trebolis"'
  Set-Content -Path $main -Value $codigo -NoNewline
}
flutter pub get
if ($LASTEXITCODE -ne 0) { Fallo 'No se pudieron descargar los paquetes (revisa el internet)' }

Paso 'Paso 2 de 4: compilando el APK de Android (puede tardar varios minutos la primera vez)'
flutter build apk --release --dart-define=API_URL=$api --dart-define=WEB_URL=$web
if ($LASTEXITCODE -ne 0) { Fallo 'No se pudo compilar el APK' }
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' (Join-Path $destino 'asamblea-trebolis.apk') -Force

Paso 'Paso 3 de 4: compilando la app de Windows'
flutter build windows --release --dart-define=API_URL=$api --dart-define=WEB_URL=$web
if ($LASTEXITCODE -ne 0) { Fallo 'No se pudo compilar la app de Windows (el APK si quedo listo)' }
$carpetaWindows = Join-Path $destino 'App de Windows'
if (Test-Path $carpetaWindows) { Remove-Item $carpetaWindows -Recurse -Force }
Copy-Item 'build\windows\x64\runner\Release' $carpetaWindows -Recurse -Force

Paso 'Paso 4 de 4: creando el acceso directo en el Escritorio'
$exe = Join-Path $carpetaWindows 'asistencia_asamblea.exe'
$shell = New-Object -ComObject WScript.Shell
$acceso = $shell.CreateShortcut((Join-Path $escritorio 'Asamblea Trebolis.lnk'))
$acceso.TargetPath = $exe
$acceso.WorkingDirectory = $carpetaWindows
$acceso.IconLocation = "$exe,0"
$acceso.Save()

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' LISTO. En tu Escritorio quedaron:' -ForegroundColor Green
Write-Host '   - El acceso directo "Asamblea Trebolis" (app de Windows)' -ForegroundColor Green
Write-Host '   - La carpeta "Asamblea Trebolis" con asamblea-trebolis.apk' -ForegroundColor Green
Write-Host '     (ese es el que envias por WhatsApp como Documento)' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Start-Process explorer.exe $destino
Read-Host 'Presiona Enter para cerrar'
