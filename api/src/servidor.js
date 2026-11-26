'use strict';
// Servidor HTTP de la API de Asistencia a Asamblea.
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { rutas: rutasBase } = require('./rutas');
const { rutasVotacion } = require('./votaciones');
const { rutasRespaldo } = require('./respaldo');

const rutas = [...rutasBase, ...rutasVotacion, ...rutasRespaldo];
const { verificar } = require('./token');
const { ErrorApi } = require('./utilidades');
const bd = require('./bd');
const tiempoReal = require('./tiempo_real');

const LIMITE_CUERPO = 15 * 1024 * 1024; // 15 MB (listas de Excel y respaldos)

// Modo sin internet: la app web compilada se sirve desde esta carpeta.
const CARPETA_WEB = path.resolve(process.env.CARPETA_WEB || path.join(__dirname, '..', 'publico'));
const TIPOS = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.wasm': 'application/wasm', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8', '.map': 'application/json',
  '.bin': 'application/octet-stream', '.frag': 'text/plain', '.apk': 'application/vnd.android.package-archive',
};

function servirArchivo(req, res, ruta) {
  if (!fs.existsSync(path.join(CARPETA_WEB, 'index.html'))) return false;
  let relativa = decodeURIComponent(ruta);
  if (relativa.endsWith('/')) relativa += 'index.html';
  let archivo = path.resolve(CARPETA_WEB, '.' + relativa);
  if (!archivo.startsWith(CARPETA_WEB)) return false;
  if (!fs.existsSync(archivo) || fs.statSync(archivo).isDirectory()) {
    // Rutas de la app: se responde con index.html
    if (path.extname(relativa)) return false;
    archivo = path.join(CARPETA_WEB, 'index.html');
  }
  const tipo = TIPOS[path.extname(archivo).toLowerCase()] || 'application/octet-stream';
  const esIndice = archivo.endsWith('index.html');
  res.writeHead(200, { 'Content-Type': tipo, 'Cache-Control': esIndice ? 'no-cache' : 'public, max-age=3600' });
  if (req.method === 'HEAD') return res.end(), true;
  fs.createReadStream(archivo).pipe(res);
  return true;
}

// Direcciones de este computador en la red Wi-Fi (para conectarse sin internet).
function direccionesLocales(puerto) {
  const lista = [];
  for (const interfaces of Object.values(os.networkInterfaces())) {
    for (const i of interfaces || []) {
      if (i.family === 'IPv4' && !i.internal) lista.push(`http://${i.address}:${puerto}`);
    }
  }
  return lista;
}

// Convierte '/api/locales/:numero' en una expresión regular.
const tabla = rutas.map(([metodo, patron, manejador, acceso]) => {
  const nombres = [];
  const regex = new RegExp('^' + patron.replace(/:(\w+)/g, (_, n) => { nombres.push(n); return '([^/]+)'; }) + '/?$');
  return { metodo, regex, nombres, manejador, acceso };
});

function cabecerasCors() {
  return {
    'Access-Control-Allow-Origin': process.env.ORIGEN_PERMITIDO || '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
  };
}

function responder(res, estado, datos) {
  res.writeHead(estado, { 'Content-Type': 'application/json; charset=utf-8', ...cabecerasCors() });
  res.end(JSON.stringify(datos));
}

function leerCuerpo(req) {
  return new Promise((resolve, reject) => {
    let tamano = 0;
    const partes = [];
    req.on('data', (c) => {
      tamano += c.length;
      if (tamano > LIMITE_CUERPO) {
        reject(new ErrorApi(413, 'Los datos enviados son demasiado grandes.'));
        req.destroy();
        return;
      }
      partes.push(c);
    });
    req.on('end', () => {
      if (!partes.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(partes).toString('utf8')));
      } catch {
        reject(new ErrorApi(400, 'Los datos enviados no tienen un formato válido.'));
      }
    });
    req.on('error', reject);
  });
}

async function atender(req, res) {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, cabecerasCors());
    return res.end();
  }
  const url = new URL(req.url, 'http://localhost');
  if ((req.method === 'GET' || req.method === 'HEAD') && !url.pathname.startsWith('/api/') && url.pathname !== '/ws') {
    if (servirArchivo(req, res, url.pathname)) return undefined;
    if (url.pathname === '/') {
      return responder(res, 200, { servicio: 'API de Asistencia a Asamblea', salud: '/api/salud' });
    }
  }

  const ruta = tabla.find((r) => r.metodo === req.method && r.regex.test(url.pathname));
  if (!ruta) return responder(res, 404, { error: 'Ruta no encontrada.' });

  try {
    const coincidencia = url.pathname.match(ruta.regex);
    const parametros = {};
    ruta.nombres.forEach((n, i) => { parametros[n] = decodeURIComponent(coincidencia[i + 1]); });

    let sesion = null;
    if (ruta.acceso) {
      const encabezado = req.headers.authorization || '';
      const token = encabezado.startsWith('Bearer ') ? encabezado.slice(7) : url.searchParams.get('token');
      sesion = verificar(token);
      if (!sesion) throw new ErrorApi(401, 'Tu sesión terminó. Vuelve a ingresar.');
      if (ruta.acceso === 'admin' && sesion.rol !== 'administradora') {
        throw new ErrorApi(403, 'Esta opción es solo para la administradora.');
      }
      if (ruta.acceso === 'gestion' && sesion.rol !== 'administradora' && sesion.rol !== 'logistica') {
        throw new ErrorApi(403, 'Esta opción es solo para la administradora y logística.');
      }
    }

    const cuerpo = ['POST', 'PUT'].includes(req.method) ? await leerCuerpo(req) : {};
    const resultado = await ruta.manejador({ parametros, cuerpo, sesion, consultaUrl: url.searchParams, req });

    if (resultado && resultado.__crudo) {
      res.writeHead(200, { 'Content-Type': resultado.tipo, ...cabecerasCors(), ...(resultado.cabeceras || {}) });
      return res.end(resultado.cuerpo);
    }
    return responder(res, 200, resultado);
  } catch (err) {
    if (err instanceof ErrorApi) return responder(res, err.estado, { error: err.message });
    if (err && err.code === '23505') return responder(res, 409, { error: 'Ese registro ya existe.' });
    console.error(err);
    return responder(res, 500, { error: 'Ocurrió un error en el servidor. Intenta de nuevo.' });
  }
}

function crearServidor() {
  const servidor = http.createServer((req, res) => {
    atender(req, res).catch((err) => {
      console.error(err);
      if (!res.headersSent) responder(res, 500, { error: 'Error inesperado.' });
    });
  });
  tiempoReal.iniciar(servidor);
  return servidor;
}

async function arrancar(puerto = Number(process.env.PORT || 3000)) {
  await bd.preparar();
  const servidor = crearServidor();
  await new Promise((resolve) => servidor.listen(puerto, resolve));
  const puertoReal = servidor.address().port;
  console.log(`API de Asistencia a Asamblea escuchando en el puerto ${puertoReal}`);
  if (fs.existsSync(path.join(CARPETA_WEB, 'index.html')) && process.env.NODE_ENV !== 'test') {
    console.log('');
    console.log('=== MODO SIN INTERNET ===');
    console.log('Conecta los celulares a la misma red Wi-Fi de este computador y abre en el navegador:');
    direccionesLocales(puertoReal).forEach((d) => console.log('   ' + d));
    console.log(`En este computador: http://localhost:${puertoReal}`);
    console.log('');
  }
  return servidor;
}

if (require.main === module) {
  arrancar().catch((err) => {
    console.error('No se pudo iniciar la API:', err.message);
    process.exit(1);
  });
}

module.exports = { arrancar, direccionesLocales };
