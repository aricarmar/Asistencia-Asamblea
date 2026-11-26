'use strict';
// Respaldos: pasar los datos de la nube al computador (modo sin internet) y devolverlos después.
const { consulta, transaccion } = require('./bd');
const tiempoReal = require('./tiempo_real');
const { ErrorApi, escaparHtml } = require('./utilidades');

const COPROPIEDAD = process.env.NOMBRE_COPROPIEDAD || 'Trebolis Capellanía Centro Comercial';

const CONSULTAS = {
  locales: `SELECT id, numero, coeficiente::text AS coeficiente, propietario_nombre, propietario_cedula, apoderado_nombre,
              apoderado_cedula, apoderado_registrado_por, activo, actualizado_en FROM locales ORDER BY id`,
  asambleas: `SELECT id, nombre, to_char(fecha, 'YYYY-MM-DD') AS fecha, estado, abierta_en, cerrada_en, creado_en
              FROM asambleas ORDER BY id`,
  asistencias: `SELECT id, asamblea_id, local_id, tipo, asistente_nombre, asistente_cedula, coeficiente::text AS coeficiente,
              registrado_por, hora_ingreso FROM asistencias ORDER BY id`,
  preguntas: `SELECT id, asamblea_id, numero, texto, opciones, estado, abierta_en, cerrada_en, creado_en FROM preguntas ORDER BY id`,
  votos: `SELECT id, pregunta_id, local_id, opcion, coeficiente::text AS coeficiente, tipo, votante_nombre, votante_cedula,
              registrado_por, hora FROM votos ORDER BY id`,
};

async function exportar() {
  const tablas = {};
  for (const [nombre, sql] of Object.entries(CONSULTAS)) {
    const { rows } = await consulta(sql);
    tablas[nombre] = rows;
  }
  const fecha = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  const datos = { tipo: 'respaldo-asistencia-asamblea', version: 1, copropiedad: COPROPIEDAD, creado: new Date().toISOString(), tablas };
  return {
    __crudo: true,
    tipo: 'application/json; charset=utf-8',
    cabeceras: { 'Content-Disposition': `attachment; filename="respaldo-asamblea-${fecha}.json"` },
    cuerpo: JSON.stringify(datos),
  };
}

function validar(respaldo) {
  if (!respaldo || respaldo.tipo !== 'respaldo-asistencia-asamblea' || !respaldo.tablas) {
    throw new ErrorApi(400, 'Ese archivo no es un respaldo de la app de asamblea.');
  }
  for (const t of Object.keys(CONSULTAS)) {
    if (!Array.isArray(respaldo.tablas[t])) throw new ErrorApi(400, `Al respaldo le falta la tabla ${t}.`);
  }
}

async function importar({ cuerpo }) {
  if (String(cuerpo.confirmacion || '').trim().toUpperCase() !== 'BORRAR') {
    throw new ErrorApi(400, 'Para cargar el respaldo escribe BORRAR (se reemplazan todos los datos actuales).');
  }
  const r = cuerpo.respaldo;
  validar(r);
  const t = r.tablas;
  await transaccion(async (bd) => {
    await bd.query('DELETE FROM votos');
    await bd.query('DELETE FROM preguntas');
    await bd.query('DELETE FROM asistencias');
    await bd.query('DELETE FROM asambleas');
    await bd.query('DELETE FROM locales');
    for (const l of t.locales) {
      await bd.query(
        `INSERT INTO locales (id, numero, coeficiente, propietario_nombre, propietario_cedula, apoderado_nombre, apoderado_cedula,
           apoderado_registrado_por, activo, actualizado_en)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, COALESCE($10::timestamptz, now()))`,
        [l.id, l.numero, l.coeficiente, l.propietario_nombre, l.propietario_cedula, l.apoderado_nombre, l.apoderado_cedula,
          l.apoderado_registrado_por, l.activo !== false, l.actualizado_en]
      );
    }
    for (const a of t.asambleas) {
      await bd.query(
        `INSERT INTO asambleas (id, nombre, fecha, estado, abierta_en, cerrada_en, creado_en)
         VALUES ($1, $2, $3::date, $4, $5::timestamptz, $6::timestamptz, COALESCE($7::timestamptz, now()))`,
        [a.id, a.nombre, a.fecha, a.estado, a.abierta_en, a.cerrada_en, a.creado_en]
      );
    }
    for (const a of t.asistencias) {
      await bd.query(
        `INSERT INTO asistencias (id, asamblea_id, local_id, tipo, asistente_nombre, asistente_cedula, coeficiente, registrado_por, hora_ingreso)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::timestamptz)`,
        [a.id, a.asamblea_id, a.local_id, a.tipo, a.asistente_nombre, a.asistente_cedula, a.coeficiente, a.registrado_por, a.hora_ingreso]
      );
    }
    for (const p of t.preguntas) {
      await bd.query(
        `INSERT INTO preguntas (id, asamblea_id, numero, texto, opciones, estado, abierta_en, cerrada_en, creado_en)
         VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7::timestamptz, $8::timestamptz, COALESCE($9::timestamptz, now()))`,
        [p.id, p.asamblea_id, p.numero, p.texto, JSON.stringify(p.opciones), p.estado, p.abierta_en, p.cerrada_en, p.creado_en]
      );
    }
    for (const v of t.votos) {
      await bd.query(
        `INSERT INTO votos (id, pregunta_id, local_id, opcion, coeficiente, tipo, votante_nombre, votante_cedula, registrado_por, hora)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::timestamptz)`,
        [v.id, v.pregunta_id, v.local_id, v.opcion, v.coeficiente, v.tipo, v.votante_nombre, v.votante_cedula, v.registrado_por, v.hora]
      );
    }
    // Los contadores de id siguen después del último número cargado.
    for (const tabla of ['locales', 'asambleas', 'asistencias', 'preguntas', 'votos']) {
      await bd.query(
        `SELECT setval(pg_get_serial_sequence('${tabla}', 'id'), COALESCE((SELECT MAX(id) FROM ${tabla}), 0) + 1, false)`
      );
    }
  });
  ['locales', 'asamblea', 'asistencia', 'votacion'].forEach((e) => tiempoReal.avisar(e));
  return {
    ok: true,
    locales: t.locales.length,
    asambleas: t.asambleas.length,
    asistencias: t.asistencias.length,
    preguntas: t.preguntas.length,
    votos: t.votos.length,
  };
}

// Página sencilla para escoger el archivo de respaldo y cargarlo (se abre en el navegador).
async function paginaImportar({ consultaUrl }) {
  const token = escaparHtml(consultaUrl.get('token') || '');
  const html = `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Cargar respaldo</title>
<style>
  body{font-family:Arial,Helvetica,sans-serif;background:#F3F6EF;margin:0;padding:24px;color:#1C2620}
  .caja{max-width:560px;margin:auto;background:#fff;border-radius:24px;padding:24px;box-shadow:0 4px 18px #0001}
  h1{color:#2F7D32;font-size:22px;margin-top:0} .aviso{background:#FFF1D6;border-radius:16px;padding:12px 16px;margin:14px 0}
  input[type=text]{width:100%;box-sizing:border-box;padding:12px 16px;border-radius:30px;border:1px solid #ccc;font-size:16px}
  button{background:#2F7D32;color:#fff;border:0;border-radius:30px;padding:14px 22px;font-size:16px;font-weight:bold;cursor:pointer;width:100%}
  button:disabled{background:#9bb59c} #resultado{margin-top:16px;white-space:pre-line} .ok{color:#2F7D32} .error{color:#D93A3A}
</style></head><body><div class="caja">
<h1>Cargar respaldo</h1>
<div>${escaparHtml(COPROPIEDAD)}</div>
<div class="aviso"><b>Atención:</b> se reemplazan TODOS los datos de este servidor (locales, asambleas, asistencia y votaciones)
por los del archivo. Las cuentas de usuario no cambian.</div>
<p><b>1.</b> Escoge el archivo de respaldo (.json):</p>
<p><input id="archivo" type="file" accept=".json,application/json"></p>
<p><b>2.</b> Para confirmar, escribe BORRAR:</p>
<p><input id="confirmacion" type="text" placeholder="BORRAR"></p>
<button id="boton">Cargar respaldo</button>
<div id="resultado"></div>
</div>
<script>
const token = ${JSON.stringify(token)};
document.getElementById('boton').onclick = async () => {
  const salida = document.getElementById('resultado');
  const archivo = document.getElementById('archivo').files[0];
  if (!archivo) { salida.className = 'error'; salida.textContent = 'Escoge el archivo de respaldo.'; return; }
  let respaldo;
  try { respaldo = JSON.parse(await archivo.text()); } catch (e) { salida.className = 'error'; salida.textContent = 'El archivo no es válido.'; return; }
  const boton = document.getElementById('boton'); boton.disabled = true; salida.className = ''; salida.textContent = 'Cargando…';
  try {
    const r = await fetch('/api/admin/respaldo/importar', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
      body: JSON.stringify({ respaldo, confirmacion: document.getElementById('confirmacion').value }) });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error || 'No se pudo cargar.');
    salida.className = 'ok';
    salida.textContent = '¡Listo! Se cargaron ' + d.locales + ' locales, ' + d.asambleas + ' asambleas, ' + d.asistencias + ' asistencias, '
      + d.preguntas + ' preguntas y ' + d.votos + ' votos.\\nYa puedes cerrar esta pestaña.';
  } catch (e) { salida.className = 'error'; salida.textContent = e.message; }
  boton.disabled = false;
};
</script></body></html>`;
  return { __crudo: true, tipo: 'text/html; charset=utf-8', cuerpo: html };
}

// Para el código QR: ¿está en modo sin internet? ¿cuál es la dirección del computador en el Wi-Fi?
async function red() {
  const fs = require('fs');
  const os = require('os');
  const path = require('path');
  const carpeta = path.resolve(process.env.CARPETA_WEB || path.join(__dirname, '..', 'publico'));
  const modoLocal = !process.env.RENDER && fs.existsSync(path.join(carpeta, 'index.html'));
  const puerto = Number(process.env.PORT || 3000);
  const direcciones = [];
  if (modoLocal) {
    for (const interfaces of Object.values(os.networkInterfaces())) {
      for (const i of interfaces || []) {
        if (i.family === 'IPv4' && !i.internal) direcciones.push(`http://${i.address}:${puerto}/`);
      }
    }
  }
  return { modo_local: modoLocal, direcciones };
}

const rutasRespaldo = [
  ['GET', '/api/red', red, null],
  ['GET', '/api/admin/respaldo', exportar, 'admin'],
  ['GET', '/api/admin/respaldo/importar', paginaImportar, 'admin'],
  ['POST', '/api/admin/respaldo/importar', importar, 'admin'],
];

module.exports = { rutasRespaldo };
