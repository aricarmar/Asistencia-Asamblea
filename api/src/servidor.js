'use strict';
// Servidor HTTP de la API de Asistencia a Asamblea.
const http = require('http');
const { rutas } = require('./rutas');
const { verificar } = require('./token');
const { ErrorApi } = require('./utilidades');
const bd = require('./bd');
const tiempoReal = require('./tiempo_real');

const LIMITE_CUERPO = 2 * 1024 * 1024; // 2 MB (suficiente para pegar cientos de locales)

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
  if (url.pathname === '/' && req.method === 'GET') {
    return responder(res, 200, { servicio: 'API de Asistencia a Asamblea', salud: '/api/salud' });
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
  console.log(`API de Asistencia a Asamblea escuchando en el puerto ${servidor.address().port}`);
  return servidor;
}

if (require.main === module) {
  arrancar().catch((err) => {
    console.error('No se pudo iniciar la API:', err.message);
    process.exit(1);
  });
}

module.exports = { arrancar };
