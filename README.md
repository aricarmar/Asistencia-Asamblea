# Asamblea · Trebolis Capellanía Centro Comercial

App para registrar la asistencia a la asamblea de **Trebolis Capellanía Centro Comercial** (locales **1 al 51**)
por **número de local**, con el **quórum por coeficiente** en tiempo real.
Funciona como **página web** y como **app de Android (APK)**, con **modo claro y oscuro** (botón de sol / luna).

Usa la misma tecnología del proyecto de parqueaderos:

| Parte | Tecnología | Dónde corre |
|---|---|---|
| App | Flutter (web y Android) | GitHub Pages (web) y el celular (APK) |
| API | Node.js + WebSocket | Render |
| Base de datos | PostgreSQL | Neon |

## Cómo funciona

**Propietario o apoderado**
1. Abre la app y escribe solo el **número de su local**.
2. Ve su local, su coeficiente y el propietario (con la cédula parcialmente oculta).
3. Elige **«Soy el propietario»** o **«Soy el apoderado»**. El apoderado escribe sus **nombres**, **apellidos** y **cédula**.
4. Si la asamblea está abierta, **su asistencia queda registrada al ingresar** y el quórum sube en todas las pantallas.
5. Tiene dos pestañas: **Mi asistencia** (estado y quórum) y **Locales** (escribe un número y ve coeficiente, propietario y apoderado).

**Administradora** (usuario y contraseña)
- **Quórum:** porcentaje de coeficiente presente, locales presentes, propietarios, apoderados y últimos en llegar.
- **Consultar:** escribe un número de local y ve propietario y apoderado con cédula completa; puede registrar la asistencia o editar el local.
- **Asistencia:** lista de asistentes, registro manual, quitar registros, **descargar Excel** y **acta para imprimir o guardar como PDF**.
- **Locales:** crear, editar, quitar y **pegar la lista completa desde Excel** (usa `plantillas/plantilla-locales.xlsx`, que ya trae los locales 1 al 51).
- **Asambleas:** crear, abrir y cerrar. Solo puede haber una abierta a la vez.

Hay quórum cuando el coeficiente presente supera el 50 %.

## Base de datos (tablas en español)

| Tabla | Para qué |
|---|---|
| `locales` | número, coeficiente, propietario y cédula, apoderado y cédula |
| `asambleas` | nombre, fecha y estado (creada, abierta, cerrada) |
| `asistencias` | quién asistió por cada local, como propietario o apoderado, y a qué hora |
| `administradores` | usuario y contraseña cifrada de la administradora |

Las tablas se crean solas cuando arranca la API (`api/src/esquema.sql`).

---

## Publicarla (una sola vez)

### 1. Subir el código a GitHub
1. Crea un repositorio **público** llamado `Asistencia-Asamblea` (GitHub Pages gratis solo funciona en repositorios públicos).
2. Sube todo el contenido de esta carpeta a la rama `main`.

### 2. Base de datos en Neon
1. Entra a https://neon.tech → **New project** → nombre `asistencia-asamblea`, región **US East (Ohio)**.
2. Copia la **Connection string** (empieza por `postgresql://`).

### 3. API en Render
1. Entra a https://render.com → **New** → **Blueprint** → elige el repositorio.
2. Render lee `render.yaml` y pide dos valores:
   - `DATABASE_URL`: la cadena de conexión de Neon.
   - `ADMIN_CLAVE`: la contraseña inicial de la administradora (el usuario es `admin`).
3. Al terminar, copia la dirección del servicio, por ejemplo `https://asistencia-asamblea-api.onrender.com`.
4. Pruébala abriendo `https://TU-DIRECCION.onrender.com/api/salud`. Debe decir `"ok": true`.

### 4. Web y APK con GitHub Actions
1. En GitHub: **Settings → Secrets and variables → Actions → Variables → New repository variable**
   - Nombre: `API_URL`
   - Valor: la dirección de Render (sin `/` al final).
2. **Settings → Pages → Source: GitHub Actions**.
3. **Actions → Probar y publicar (web + APK) → Run workflow**.
4. Cuando termine en verde (unos 10 minutos):
   - **Página web:** `https://TU-USUARIO.github.io/Asistencia-Asamblea/`
   - **APK:** `https://TU-USUARIO.github.io/Asistencia-Asamblea/descargas/asistencia-asamblea.apk`
   - En la página web también aparece el botón **«Descargar la app para Android»**.

Cada vez que subas cambios a `main`, se vuelve a probar y publicar todo solo.

---

## Probar en el PC

**API** (con PostgreSQL instalado):
```powershell
cd api
npm install
$env:DATABASE_URL="postgres://postgres:TU_CLAVE@localhost:5432/asistencia_asamblea"
npm start
```
Crea antes la base `asistencia_asamblea` en pgAdmin. Usuario `admin`, contraseña `admin123` (si no definiste `ADMIN_CLAVE`).

**App** (la primera vez crea las carpetas de Android y web que faltan):
```powershell
cd app
flutter create --platforms=android,web --org co.asamblea --project-name asistencia_asamblea .
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:3000
```
Para el celular: `flutter build apk --release --dart-define=API_URL=https://TU-DIRECCION.onrender.com`.
El servidor también se puede cambiar desde el engranaje de la pantalla de ingreso.

**Pruebas de la API** (borran la base indicada, por eso su nombre debe contener «prueba»):
```powershell
$env:DATABASE_URL="postgres://postgres:TU_CLAVE@localhost:5432/asistencia_prueba"
npm test
```

---

## El día de la asamblea
1. **Abre la app 2 minutos antes.** El plan gratis de Render se duerme tras 15 minutos sin uso y el primer ingreso tarda cerca de un minuto.
2. En **Asambleas**, crea la asamblea y toca **Abrir** cuando empiece el registro.
3. Comparte el enlace web o el APK. Cada persona escribe su número de local y queda registrada.
4. Sigue el quórum en la pestaña **Quórum**.
5. Al terminar, toca **Cerrar** y descarga el **Excel** o el **acta**.

## Notas
- Los propietarios y apoderados ven las cédulas de otros locales con los últimos 4 dígitos; la administradora las ve completas.
- Si un local ya registró asistencia, otra persona no puede registrarlo de nuevo; la administradora puede corregirlo.
- El APK está firmado con la llave de prueba de GitHub Actions. Si una versión nueva no se instala encima, desinstala la anterior.
