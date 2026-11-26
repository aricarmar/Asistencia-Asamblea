'use strict';
// Votaciones: logística escribe la pregunta, todos ven las opciones y cada local vota con su coeficiente.
const { consulta, transaccion } = require('./bd');
const { cifrarClave } = require('./token');
const tiempoReal = require('./tiempo_real');
const { ErrorApi, normalizarNombre, csvCampo, escaparHtml, fechaColombia } = require('./utilidades');
const { asambleaAbierta, asambleaElegida, buscarLocalPorNumero, asistenciaDeLocal } = require('./rutas');

const ZONA = process.env.ZONA_HORARIA || 'America/Bogota';
const COPROPIEDAD = process.env.NOMBRE_COPROPIEDAD || 'Trebolis Capellanía Centro Comercial';
const ROLES_ASISTENTE = ['propietario', 'apoderado'];
const ROLES_GESTION = ['administradora', 'logistica'];
const OPCIONES_POR_DEFECTO = ['Sí', 'No', 'Abstención'];

const CAMPOS_PREGUNTA = `p.id, p.asamblea_id, p.numero, p.texto, p.opciones, p.estado,
  to_char(p.abierta_en AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora_apertura,
  to_char(p.cerrada_en AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora_cierre`;

const redondear = (n, d = 6) => Number(Number(n || 0).toFixed(d));

function limpiarOpciones(lista) {
  const opciones = (Array.isArray(lista) && lista.length ? lista : OPCIONES_POR_DEFECTO)
    .map((o) => normalizarNombre(o))
    .filter(Boolean);
  const unicas = [...new Set(opciones.map((o) => o.toLowerCase()))];
  if (opciones.length < 2) throw new ErrorApi(400, 'La pregunta necesita al menos 2 opciones.');
  if (opciones.length > 10) throw new ErrorApi(400, 'Máximo 10 opciones por pregunta.');
  if (unicas.length !== opciones.length) throw new ErrorApi(400, 'Hay opciones repetidas.');
  if (opciones.some((o) => o.length > 120)) throw new ErrorApi(400, 'Cada opción puede tener máximo 120 letras.');
  return opciones;
}

async function buscarPregunta(id, bd = { query: consulta }) {
  const { rows } = await bd.query(`SELECT ${CAMPOS_PREGUNTA} FROM preguntas p WHERE p.id = $1`, [Number(id)]);
  if (!rows[0]) throw new ErrorApi(404, 'Esa pregunta no existe.');
  return rows[0];
}

// Resultados por coeficiente: votos, suma de coeficiente y porcentajes de cada opción.
async function calcularResultados(p, bd = { query: consulta }) {
  const [votos, presentes, total] = await Promise.all([
    bd.query(
      `SELECT opcion, COUNT(*)::int AS votos, COALESCE(SUM(coeficiente), 0)::float8 AS coeficiente
       FROM votos WHERE pregunta_id = $1 GROUP BY opcion`,
      [p.id]
    ),
    bd.query(
      'SELECT COUNT(*)::int AS locales, COALESCE(SUM(coeficiente), 0)::float8 AS coeficiente FROM asistencias WHERE asamblea_id = $1',
      [p.asamblea_id]
    ),
    bd.query('SELECT COALESCE(SUM(coeficiente), 0)::float8 AS coeficiente FROM locales WHERE activo'),
  ]);
  const porOpcion = new Map(votos.rows.map((v) => [v.opcion, v]));
  const coefPresente = presentes.rows[0].coeficiente;
  const coefTotal = total.rows[0].coeficiente;
  const votaron = votos.rows.reduce((s, v) => ({ locales: s.locales + v.votos, coeficiente: s.coeficiente + v.coeficiente }), { locales: 0, coeficiente: 0 });
  const opciones = p.opciones.map((texto, indice) => {
    const v = porOpcion.get(indice) || { votos: 0, coeficiente: 0 };
    return {
      indice,
      texto,
      votos: v.votos,
      coeficiente: redondear(v.coeficiente),
      porcentaje_presentes: coefPresente > 0 ? redondear((v.coeficiente / coefPresente) * 100, 2) : 0,
      porcentaje_votos: votaron.coeficiente > 0 ? redondear((v.coeficiente / votaron.coeficiente) * 100, 2) : 0,
      porcentaje_total: coefTotal > 0 ? redondear((v.coeficiente / coefTotal) * 100, 2) : 0,
    };
  });
  let ganadora = null;
  if (votaron.locales > 0) {
    const mayor = Math.max(...opciones.map((o) => o.coeficiente));
    const empatadas = opciones.filter((o) => o.coeficiente === mayor);
    if (empatadas.length === 1) ganadora = empatadas[0].indice;
  }
  return {
    opciones,
    votaron_locales: votaron.locales,
    votaron_coeficiente: redondear(votaron.coeficiente),
    presentes_locales: presentes.rows[0].locales,
    presentes_coeficiente: redondear(coefPresente),
    faltan_locales: Math.max(presentes.rows[0].locales - votaron.locales, 0),
    faltan_coeficiente: redondear(Math.max(coefPresente - votaron.coeficiente, 0)),
    coeficiente_total: redondear(coefTotal),
    ganadora,
  };
}

async function presentarPregunta(p, conResultados, bd) {
  const base = {
    id: p.id,
    asamblea_id: p.asamblea_id,
    numero: p.numero,
    texto: p.texto,
    opciones: p.opciones,
    estado: p.estado,
    hora_apertura: p.hora_apertura,
    hora_cierre: p.hora_cierre,
  };
  if (conResultados) base.resultados = await calcularResultados(p, bd);
  return base;
}

// ---------- Para todos (propietarios, apoderados y gestión) ----------

async function votacionActual({ sesion }) {
  const asamblea = await asambleaAbierta();
  const gestion = ROLES_GESTION.includes(sesion.rol);
  const respuesta = { asamblea, pregunta: null, ultima: null, puede_votar: false, motivo: null, mi_voto: null };
  if (!asamblea) {
    respuesta.motivo = 'No hay una asamblea abierta.';
    return respuesta;
  }
  const abierta = await consulta(`SELECT ${CAMPOS_PREGUNTA} FROM preguntas p WHERE p.estado = 'abierta' AND p.asamblea_id = $1`, [asamblea.id]);
  const cerrada = await consulta(
    `SELECT ${CAMPOS_PREGUNTA} FROM preguntas p WHERE p.estado = 'cerrada' AND p.asamblea_id = $1
     ORDER BY p.cerrada_en DESC NULLS LAST, p.id DESC LIMIT 1`,
    [asamblea.id]
  );
  if (abierta.rows[0]) respuesta.pregunta = await presentarPregunta(abierta.rows[0], gestion);
  if (cerrada.rows[0]) respuesta.ultima = await presentarPregunta(cerrada.rows[0], true);

  if (ROLES_ASISTENTE.includes(sesion.rol)) {
    const { rows } = await consulta('SELECT numero, coeficiente::float8 AS coeficiente FROM locales WHERE id = $1', [sesion.local_id]);
    respuesta.local_numero = rows[0] ? rows[0].numero : null;
    respuesta.coeficiente = rows[0] ? rows[0].coeficiente : 0;
    const asistencia = await asistenciaDeLocal(asamblea.id, sesion.local_id);
    if (respuesta.pregunta) {
      const voto = await consulta(
        'SELECT opcion, votante_nombre, to_char(hora AT TIME ZONE $3, \'HH24:MI\') AS hora FROM votos WHERE pregunta_id = $1 AND local_id = $2',
        [respuesta.pregunta.id, sesion.local_id, ZONA]
      );
      if (voto.rows[0]) {
        respuesta.mi_voto = { opcion: voto.rows[0].opcion, nombre: voto.rows[0].votante_nombre, hora: voto.rows[0].hora };
        respuesta.motivo = 'Tu local ya votó esta pregunta.';
      } else if (!asistencia) {
        respuesta.motivo = 'Para votar, primero registra tu asistencia en «Mi asistencia».';
      } else {
        respuesta.puede_votar = true;
      }
    } else {
      respuesta.motivo = 'No hay una votación abierta en este momento.';
    }
  }
  return respuesta;
}

async function votar({ sesion, cuerpo }) {
  if (!ROLES_ASISTENTE.includes(sesion.rol)) throw new ErrorApi(403, 'Solo propietarios y apoderados votan desde aquí.');
  const opcion = Number(cuerpo.opcion);
  const resultado = await transaccion(async (bd) => {
    const p = await buscarPregunta(cuerpo.pregunta_id, bd);
    if (p.estado !== 'abierta') throw new ErrorApi(409, 'Esta votación ya se cerró.');
    if (!Number.isInteger(opcion) || opcion < 0 || opcion >= p.opciones.length) throw new ErrorApi(400, 'Esa opción no existe.');
    const asistencia = await asistenciaDeLocal(p.asamblea_id, sesion.local_id, bd);
    if (!asistencia) throw new ErrorApi(409, 'Para votar, primero registra tu asistencia.');
    const insertado = await bd.query(
      `INSERT INTO votos (pregunta_id, local_id, opcion, coeficiente, tipo, votante_nombre, votante_cedula, registrado_por)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'asistente')
       ON CONFLICT (pregunta_id, local_id) DO NOTHING RETURNING id`,
      [p.id, sesion.local_id, opcion, asistencia.coeficiente, sesion.rol, sesion.nombre, sesion.cedula]
    );
    if (!insertado.rows[0]) throw new ErrorApi(409, 'Tu local ya votó esta pregunta.');
    return { p, coeficiente: asistencia.coeficiente };
  });
  tiempoReal.avisar('voto', { pregunta_id: resultado.p.id });
  return { ok: true, opcion, texto: resultado.p.opciones[opcion], coeficiente: resultado.coeficiente };
}

// ---------- Logística y administradora ----------

async function listarPreguntas({ consultaUrl }) {
  const asamblea = await asambleaElegida(consultaUrl.get('asamblea_id'));
  if (!asamblea) return { asamblea: null, preguntas: [] };
  const { rows } = await consulta(`SELECT ${CAMPOS_PREGUNTA} FROM preguntas p WHERE p.asamblea_id = $1 ORDER BY p.numero DESC`, [asamblea.id]);
  const preguntas = [];
  for (const p of rows) preguntas.push(await presentarPregunta(p, true));
  return { asamblea, preguntas, opciones_por_defecto: OPCIONES_POR_DEFECTO };
}

async function crearPregunta({ cuerpo }) {
  const texto = String(cuerpo.texto || '').trim();
  if (texto.length < 3) throw new ErrorApi(400, 'Escribe la pregunta.');
  if (texto.length > 1000) throw new ErrorApi(400, 'La pregunta es demasiado larga (máximo 1000 letras).');
  const opciones = limpiarOpciones(cuerpo.opciones);
  const asamblea = await asambleaAbierta();
  if (!asamblea) throw new ErrorApi(409, 'Primero la administradora debe abrir la asamblea.');
  if (cuerpo.abrir === true) {
    const otra = await consulta(`SELECT numero FROM preguntas WHERE estado = 'abierta'`);
    if (otra.rows[0]) throw new ErrorApi(409, `Ya está abierta la pregunta ${otra.rows[0].numero}. Ciérrala primero.`);
  }
  const { rows } = await consulta(
    `INSERT INTO preguntas (asamblea_id, numero, texto, opciones)
     VALUES ($1, (SELECT COALESCE(MAX(numero), 0) + 1 FROM preguntas WHERE asamblea_id = $1), $2, $3::jsonb)
     RETURNING id`,
    [asamblea.id, texto, JSON.stringify(opciones)]
  );
  const p = await buscarPregunta(rows[0].id);
  // Si se pide, se abre de una vez.
  if (cuerpo.abrir === true) return abrirPregunta({ parametros: { id: p.id } });
  tiempoReal.avisar('votacion');
  return { pregunta: await presentarPregunta(p, true) };
}

async function editarPregunta({ parametros, cuerpo }) {
  const p = await buscarPregunta(parametros.id);
  if (p.estado !== 'creada') throw new ErrorApi(409, 'Solo se pueden editar preguntas que todavía no se han abierto.');
  const texto = String(cuerpo.texto || '').trim();
  if (texto.length < 3) throw new ErrorApi(400, 'Escribe la pregunta.');
  const opciones = limpiarOpciones(cuerpo.opciones);
  await consulta('UPDATE preguntas SET texto = $2, opciones = $3::jsonb WHERE id = $1', [p.id, texto, JSON.stringify(opciones)]);
  tiempoReal.avisar('votacion');
  return { pregunta: await presentarPregunta(await buscarPregunta(p.id), true) };
}

async function abrirPregunta({ parametros }) {
  const p = await buscarPregunta(parametros.id);
  const asamblea = await asambleaAbierta();
  if (!asamblea || asamblea.id !== p.asamblea_id) throw new ErrorApi(409, 'La asamblea de esta pregunta no está abierta.');
  const otra = await consulta(`SELECT id, numero FROM preguntas WHERE estado = 'abierta' AND id <> $1`, [p.id]);
  if (otra.rows[0]) throw new ErrorApi(409, `Ya está abierta la pregunta ${otra.rows[0].numero}. Ciérrala primero.`);
  await consulta(
    `UPDATE preguntas SET estado = 'abierta', abierta_en = COALESCE(abierta_en, now()), cerrada_en = NULL WHERE id = $1`,
    [p.id]
  );
  tiempoReal.avisar('votacion', { pregunta_id: p.id, abierta: true });
  return { pregunta: await presentarPregunta(await buscarPregunta(p.id), true) };
}

async function cerrarPregunta({ parametros }) {
  const { rowCount } = await consulta(
    `UPDATE preguntas SET estado = 'cerrada', cerrada_en = now() WHERE id = $1 AND estado = 'abierta'`,
    [Number(parametros.id)]
  );
  if (!rowCount) throw new ErrorApi(409, 'Esa votación no está abierta.');
  tiempoReal.avisar('votacion', { pregunta_id: Number(parametros.id), cerrada: true });
  return { pregunta: await presentarPregunta(await buscarPregunta(parametros.id), true) };
}

async function borrarPregunta({ parametros, consultaUrl }) {
  const p = await buscarPregunta(parametros.id);
  if (p.estado === 'abierta') throw new ErrorApi(409, 'Primero cierra la votación y luego bórrala.');
  const { rows } = await consulta('SELECT COUNT(*)::int AS votos FROM votos WHERE pregunta_id = $1', [p.id]);
  if (rows[0].votos > 0 && consultaUrl.get('forzar') !== 'si') {
    throw new ErrorApi(409, `Esta pregunta tiene ${rows[0].votos} votos. Confirma escribiendo BORRAR.`);
  }
  await consulta('DELETE FROM preguntas WHERE id = $1', [p.id]);
  tiempoReal.avisar('votacion');
  return { ok: true, votos_borrados: rows[0].votos };
}

async function listarVotos({ parametros }) {
  const p = await buscarPregunta(parametros.id);
  const { rows } = await consulta(
    `SELECT v.id, l.numero, v.opcion, v.coeficiente::float8 AS coeficiente, v.tipo, v.votante_nombre, v.votante_cedula,
            v.registrado_por, to_char(v.hora AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora
     FROM votos v JOIN locales l ON l.id = v.local_id
     WHERE v.pregunta_id = $1
     ORDER BY NULLIF(regexp_replace(l.numero, '\\D', '', 'g'), '')::numeric NULLS LAST, l.numero`,
    [p.id]
  );
  return {
    pregunta: await presentarPregunta(p, true),
    votos: rows.map((v) => ({ ...v, opcion_texto: p.opciones[v.opcion] })),
  };
}

// Voto de alguien que no tiene celular (lo registra logística o la administradora).
async function votoManual({ parametros, cuerpo, sesion }) {
  const opcion = Number(cuerpo.opcion);
  const resultado = await transaccion(async (bd) => {
    const p = await buscarPregunta(parametros.id, bd);
    if (p.estado !== 'abierta') throw new ErrorApi(409, 'Esta votación no está abierta.');
    if (!Number.isInteger(opcion) || opcion < 0 || opcion >= p.opciones.length) throw new ErrorApi(400, 'Elige una opción.');
    const local = await buscarLocalPorNumero(cuerpo.numero, bd);
    const asistencia = await asistenciaDeLocal(p.asamblea_id, local.id, bd);
    if (!asistencia) throw new ErrorApi(409, `El local ${local.numero} no ha registrado asistencia. Regístrala primero.`);
    const valores = [p.id, local.id, opcion, asistencia.coeficiente, asistencia.tipo, asistencia.asistente_nombre,
      asistencia.asistente_cedula, sesion.rol];
    const insertado = await bd.query(
      `INSERT INTO votos (pregunta_id, local_id, opcion, coeficiente, tipo, votante_nombre, votante_cedula, registrado_por)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (pregunta_id, local_id) DO NOTHING RETURNING id`,
      valores
    );
    if (!insertado.rows[0]) {
      if (cuerpo.reemplazar !== true) {
        const { rows } = await bd.query('SELECT opcion FROM votos WHERE pregunta_id = $1 AND local_id = $2', [p.id, local.id]);
        throw new ErrorApi(409, `El local ${local.numero} ya votó «${p.opciones[rows[0].opcion]}».`);
      }
      await bd.query(
        'UPDATE votos SET opcion = $3, registrado_por = $4, hora = now() WHERE pregunta_id = $1 AND local_id = $2',
        [p.id, local.id, opcion, sesion.rol]
      );
    }
    return { p, local };
  });
  tiempoReal.avisar('voto', { pregunta_id: resultado.p.id });
  return { ok: true, numero: resultado.local.numero, texto: resultado.p.opciones[opcion] };
}

async function borrarVoto({ parametros }) {
  const { rows } = await consulta('DELETE FROM votos WHERE id = $1 RETURNING pregunta_id', [Number(parametros.id)]);
  if (!rows[0]) throw new ErrorApi(404, 'Ese voto no existe.');
  tiempoReal.avisar('voto', { pregunta_id: rows[0].pregunta_id });
  return { ok: true };
}

// ---------- Informes ----------

async function datosVotaciones(asambleaId) {
  const asamblea = await asambleaElegida(asambleaId);
  if (!asamblea) throw new ErrorApi(404, 'Todavía no hay asambleas.');
  const { rows } = await consulta(`SELECT ${CAMPOS_PREGUNTA} FROM preguntas p WHERE p.asamblea_id = $1 ORDER BY p.numero`, [asamblea.id]);
  const preguntas = [];
  for (const p of rows) preguntas.push(await presentarPregunta(p, true));
  return { asamblea, preguntas };
}

async function exportarVotacionesCsv({ consultaUrl }) {
  const { asamblea, preguntas } = await datosVotaciones(consultaUrl.get('asamblea_id'));
  const dec = (n) => String(n ?? '').replace('.', ',');
  const linea = (campos) => campos.map(csvCampo).join(';');
  const lineas = [linea([COPROPIEDAD]), linea(['Asamblea', asamblea.nombre]), linea(['Fecha', fechaColombia(asamblea.fecha)]), ''];
  for (const p of preguntas) {
    const r = p.resultados;
    lineas.push(linea([`Pregunta ${p.numero}`, p.texto]));
    lineas.push(linea(['Estado', p.estado === 'cerrada' ? 'Cerrada' : p.estado === 'abierta' ? 'Abierta' : 'Sin abrir']));
    lineas.push(linea(['Opción', 'Votos (locales)', 'Coeficiente', '% de los presentes', '% de los votos', '% del total']));
    r.opciones.forEach((o) => lineas.push(linea([o.texto, o.votos, dec(o.coeficiente), dec(o.porcentaje_presentes), dec(o.porcentaje_votos), dec(o.porcentaje_total)])));
    lineas.push(linea(['No votaron (presentes)', r.faltan_locales, dec(r.faltan_coeficiente)]));
    lineas.push('');
    const detalle = await listarVotos({ parametros: { id: p.id } });
    lineas.push(linea(['Local', 'Coeficiente', 'Votó', 'Asiste como', 'Nombre', 'Cédula', 'Hora', 'Registrado por']));
    detalle.votos.forEach((v) => lineas.push(linea([v.numero, dec(v.coeficiente), v.opcion_texto,
      v.tipo === 'apoderado' ? 'Apoderado' : 'Propietario', v.votante_nombre, v.votante_cedula, v.hora,
      v.registrado_por === 'asistente' ? 'App' : v.registrado_por === 'logistica' ? 'Logística' : 'Administradora'])));
    lineas.push('');
  }
  return {
    __crudo: true,
    tipo: 'text/csv; charset=utf-8',
    cabeceras: { 'Content-Disposition': `attachment; filename="votaciones-${asamblea.fecha}.csv"` },
    cuerpo: '﻿' + lineas.join('\r\n'),
  };
}

// Sección de votaciones para el acta (HTML).
async function htmlVotaciones(asambleaId) {
  const { preguntas } = await datosVotaciones(asambleaId);
  if (!preguntas.length) return '';
  const e = escaparHtml;
  const d = (n) => e(String(n).replace('.', ','));
  const bloques = preguntas.map((p) => {
    const r = p.resultados;
    const filas = r.opciones.map((o) => `<tr${r.ganadora === o.indice ? ' class="gana"' : ''}><td>${e(o.texto)}</td><td class="n">${o.votos}</td>
      <td class="n">${d(o.coeficiente)}</td><td class="n">${d(o.porcentaje_presentes)} %</td><td class="n">${d(o.porcentaje_total)} %</td></tr>`).join('');
    return `<h3>Pregunta ${p.numero}: ${e(p.texto)}</h3>
      <div class="sub">${p.estado === 'cerrada' ? `Votación cerrada a las ${e(p.hora_cierre || '')}` : p.estado === 'abierta' ? 'Votación abierta' : 'Sin abrir'}
      · Votaron ${r.votaron_locales} de ${r.presentes_locales} locales presentes</div>
      <table><thead><tr><th>Opción</th><th>Votos</th><th>Coeficiente</th><th>% de los presentes</th><th>% del total</th></tr></thead>
      <tbody>${filas}<tr><td>No votaron</td><td class="n">${r.faltan_locales}</td><td class="n">${d(r.faltan_coeficiente)}</td><td></td><td></td></tr></tbody></table>`;
  }).join('');
  return `<h2>Votaciones</h2>${bloques}`;
}

// ---------- Cuenta de logística (la crea la administradora) ----------

async function verLogistica() {
  const { rows } = await consulta("SELECT usuario, nombre FROM administradores WHERE rol = 'logistica' ORDER BY id LIMIT 1");
  return { existe: Boolean(rows[0]), usuario: rows[0] ? rows[0].usuario : 'logistica', nombre: rows[0] ? rows[0].nombre : '' };
}

async function guardarLogistica({ cuerpo }) {
  const nombre = normalizarNombre(cuerpo.nombre) || 'Logística';
  const clave = String(cuerpo.clave || '');
  const { rows } = await consulta("SELECT id FROM administradores WHERE rol = 'logistica' ORDER BY id LIMIT 1");
  if (clave && clave.length < 6) throw new ErrorApi(400, 'La contraseña debe tener al menos 6 caracteres.');
  if (!rows[0]) {
    if (!clave) throw new ErrorApi(400, 'Escribe una contraseña para la cuenta de logística.');
    const choque = await consulta("SELECT id FROM administradores WHERE usuario = 'logistica'");
    if (choque.rows[0]) throw new ErrorApi(409, 'Ya existe un usuario llamado logistica.');
    await consulta(
      "INSERT INTO administradores (usuario, nombre, clave_hash, rol) VALUES ('logistica', $1, $2, 'logistica')",
      [nombre, cifrarClave(clave)]
    );
  } else if (clave) {
    await consulta('UPDATE administradores SET nombre = $2, clave_hash = $3 WHERE id = $1', [rows[0].id, nombre, cifrarClave(clave)]);
  } else {
    await consulta('UPDATE administradores SET nombre = $2 WHERE id = $1', [rows[0].id, nombre]);
  }
  return verLogistica();
}

// acceso: 'sesion' = cualquiera con sesión, 'gestion' = administradora o logística, 'admin' = solo administradora
const rutasVotacion = [
  ['GET', '/api/votacion/actual', votacionActual, 'sesion'],
  ['POST', '/api/votacion/votar', votar, 'sesion'],

  ['GET', '/api/gestion/preguntas', listarPreguntas, 'gestion'],
  ['POST', '/api/gestion/preguntas', crearPregunta, 'gestion'],
  ['PUT', '/api/gestion/preguntas/:id', editarPregunta, 'gestion'],
  ['POST', '/api/gestion/preguntas/:id/abrir', abrirPregunta, 'gestion'],
  ['POST', '/api/gestion/preguntas/:id/cerrar', cerrarPregunta, 'gestion'],
  ['DELETE', '/api/gestion/preguntas/:id', borrarPregunta, 'gestion'],
  ['GET', '/api/gestion/preguntas/:id/votos', listarVotos, 'gestion'],
  ['POST', '/api/gestion/preguntas/:id/votos', votoManual, 'gestion'],
  ['DELETE', '/api/gestion/votos/:id', borrarVoto, 'gestion'],
  ['GET', '/api/gestion/informes/votaciones.csv', exportarVotacionesCsv, 'gestion'],

  ['GET', '/api/admin/logistica', verLogistica, 'admin'],
  ['PUT', '/api/admin/logistica', guardarLogistica, 'admin'],
];

module.exports = { rutasVotacion, htmlVotaciones, ROLES_GESTION };
