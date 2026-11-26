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

**Votaciones**
1. La persona de **logística** escribe la pregunta y sus opciones (por defecto *Sí / No / Abstención*) y toca **Abrir votación**.
2. En el celular de todos los asistentes se abre sola la pestaña **Votación** con las opciones y el aviso *«Tu voto vale X % (Local N)»*.
3. Cada local vota **una sola vez** y solo si registró asistencia. Logística puede registrar votos manuales y quitar un voto para corregir.
4. Logística ve los resultados **en vivo por coeficiente**; al **cerrar**, todos ven el resultado.
5. Las votaciones salen en el **acta** y en el **Excel de votaciones**.

**Administradora: Sandra Libey Martinez Real** (usuario `admin`)
- **Quórum:** porcentaje de coeficiente presente, locales presentes, propietarios, apoderados y últimos en llegar.
- **Consultar:** escribe un número de local y ve propietario y apoderado con cédula completa; puede registrar la asistencia o editar el local.
- **Asistencia:** lista de asistentes, registro manual, quitar registros, **descargar Excel** y **acta para imprimir o guardar como PDF**.
- **Locales:** crear, editar, quitar y **pegar la lista completa desde Excel** (usa `plantillas/plantilla-locales.xlsx`, que ya trae los locales 1 al 51).
- **Asambleas:** crear, abrir y cerrar. Solo puede haber una abierta a la vez.

**Logística** (usuario `logistica`, la crea la administradora en su menú → *Usuario de logística*): ve Quórum, Consultar, Asistencia y Votaciones.

Hay quórum cuando el coeficiente presente supera el 50 %.

## Base de datos (tablas en español)

| Tabla | Para qué |
|---|---|
| `locales` | número, coeficiente, propietario y cédula, apoderado y cédula |
| `asambleas` | nombre, fecha y estado (creada, abierta, cerrada) |
| `asistencias` | quién asistió por cada local, como propietario o apoderado, y a qué hora |
| `administradores` | cuentas de la administradora y de logística (contraseña cifrada) |
| `preguntas` | preguntas de cada asamblea con sus opciones y estado (sin abrir, abierta, cerrada) |
| `votos` | el voto de cada local en cada pregunta, con su coeficiente |

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
   - **APK:** `https://TU-USUARIO.github.io/Asistencia-Asamblea/descargas/asamblea-trebolis.apk`
     (también queda en *Actions → la ejecución → Artifacts*). Envíalo por WhatsApp como documento.

Cada vez que subas cambios a `main`, se vuelve a probar y publicar todo solo.

---

## Compilar en tu PC (app de Windows y APK)

Doble clic en **`compilar-en-mi-pc.bat`** (necesita Flutter, Android Studio y Visual Studio con C++, igual que el proyecto de parqueaderos).
Al terminar, en el **Escritorio** quedan:
- el acceso directo **Asamblea Trebolis** (app de Windows);
- la carpeta **Asamblea Trebolis** con **`asamblea-trebolis.apk`**, para enviar por WhatsApp como *Documento*.

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

## Asamblea sin internet (modo local)

Para cuando en el lugar no haya internet o muchas personas no tengan datos. El **computador** de la asamblea hace de
servidor y todos se conectan a una **red Wi-Fi del lugar** (un router o un celular compartiendo red, aunque no tenga datos).
Las personas entran desde el **navegador del celular** escaneando el código QR, sin instalar nada.

**En casa, con internet (una sola vez y cada vez que actualices la app):**
1. Doble clic en `modo-local/1-preparar-modo-local.bat`. Necesita Node.js y Flutter instalados.
2. En la app en la nube, menú de Sandra → **Descargar respaldo** (guarda el archivo `.json`).

**El día de la asamblea (sin internet):**
1. Conecta el computador al Wi-Fi de la asamblea.
2. Doble clic en `modo-local/2-iniciar-modo-local.bat`. Escribe la contraseña de PostgreSQL (la de pgAdmin) y una contraseña para la administradora.
   Si Windows pregunta por el Firewall, marca redes privadas y públicas y dale **Permitir**
   (o ejecuta `3-abrir-puerto-firewall.bat` como administrador).
3. En el computador abre `http://localhost:3000`, entra como administradora y en el menú → **Cargar respaldo** (el `.json` de casa).
4. Menú → **Compartir la app**: muestra el **código QR** con la dirección del computador (por ejemplo `http://192.168.1.10:3000`).
   Proyéctalo o imprímelo: la gente se conecta al Wi-Fi y lo escanea.
5. Al terminar, menú → **Descargar respaldo**. Ya con internet, entra a la app en la nube → **Cargar respaldo**
   para que los resultados queden también en línea.

Quien no tenga celular: **logística** registra su asistencia y su voto a mano.

## El día de la asamblea
1. **Abre la app 2 minutos antes.** El plan gratis de Render se duerme tras 15 minutos sin uso y el primer ingreso tarda cerca de un minuto.
2. En **Asambleas**, crea la asamblea y toca **Abrir** cuando empiece el registro.
3. Menú → **Compartir la app**: código QR, enlace y mensaje listo para WhatsApp. El APK se envía por WhatsApp como documento
   (`asamblea-trebolis.apk`). Cada persona escribe su número de local y queda registrada.
4. Sigue el quórum en la pestaña **Quórum**.
5. Al terminar, toca **Cerrar** y descarga el **Excel** o el **acta**.

## Notas
- Los propietarios y apoderados ven las cédulas de otros locales con los últimos 4 dígitos; la administradora las ve completas.
- Si un local ya registró asistencia, otra persona no puede registrarlo de nuevo; la administradora puede corregirlo.
- El APK está firmado con la llave de prueba de GitHub Actions. Si una versión nueva no se instala encima, desinstala la anterior.
