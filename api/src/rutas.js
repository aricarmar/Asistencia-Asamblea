'use strict';
const { consulta, transaccion } = require('./bd');
const { firmar, compararClave, cifrarClave } = require('./token');
const tiempoReal = require('./tiempo_real');
const {
  ErrorApi,
  normalizarNumero,
  normalizarCedula,
  normalizarNombre,
  ocultarCedula,
  leerDecimal,
  leerTablaLocales,
  csvCampo,
  escaparHtml,
  fechaColombia,
} = require('./utilidades');

const ZONA = process.env.ZONA_HORARIA || 'America/Bogota';
const ROLES_ASISTENTE = ['propietario', 'apoderado'];

const CAMPOS_LOCAL = `l.id, l.numero, l.coeficiente::float8 AS coeficiente, l.propietario_nombre, l.propietario_cedula,
  l.apoderado_nombre, l.apoderado_cedula, l.apoderado_registrado_por, l.activo`;

const CAMPOS_ASAMBLEA = `id, nombre, to_char(fecha, 'YYYY-MM-DD') AS fecha, estado,
  to_char(abierta_en AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora_apertura,
  to_char(cerrada_en AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora_cierre`;

const CAMPOS_ASISTENCIA = `a.id, a.asamblea_id, a.local_id, a.tipo, a.asistente_nombre, a.asistente_cedula,
  a.coeficiente::float8 AS coeficiente, a.registrado_por, a.hora_ingreso,
  to_char(a.hora_ingreso AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora`;

const ORDEN_NATURAL = `NULLIF(regexp_replace(l.numero, '\\D', '', 'g'), '')::numeric NULLS LAST, l.numero`;

// ---------- Ayudas de presentación ----------

function presentarAsistencia(a, completo) {
  if (!a) return null;
  return {
    id: a.id,
    tipo: a.tipo,
    nombre: a.asistente_nombre,
    cedula: completo ? a.asistente_cedula : ocultarCedula(a.asistente_cedula),
    coeficiente: a.coeficiente,
    hora: a.hora,
    registrado_por: a.registrado_por,
  };
}

function presentarLocal(l, completo, asistencia = null) {
  const ced = (c) => (completo ? c : ocultarCedula(c));
  return {
    id: l.id,
    numero: l.numero,
    coeficiente: l.coeficiente,
    propietario: { nombre: l.propietario_nombre, cedula: ced(l.propietario_cedula) },
    apoderado: l.apoderado_nombre
      ? { nombre: l.apoderado_nombre, cedula: ced(l.apoderado_cedula), registrado_por: l.apoderado_registrado_por }
      : null,
    activo: l.activo,
    asistencia: presentarAsistencia(asistencia, completo),
  };
}

// ---------- Consultas comunes ----------

async function asambleaAbierta(bd = { query: consulta }) {
  const { rows } = await bd.query(`SELECT ${CAMPOS_ASAMBLEA} FROM asambleas WHERE estado = 'abierta' LIMIT 1`);
  return rows[0] || null;
}

// La asamblea que se muestra: la indicada, la abierta o la más reciente.
async function asambleaElegida(id) {
  if (id) {
    const { rows } = await consulta(`SELECT ${CAMPOS_ASAMBLEA} FROM asambleas WHERE id = $1`, [Number(id)]);
    if (!rows[0]) throw new ErrorApi(404, 'Esa asamblea no existe.');
    return rows[0];
  }
  const abierta = await asambleaAbierta();
  if (abierta) return abierta;
  const { rows } = await consulta(`SELECT ${CAMPOS_ASAMBLEA} FROM asambleas ORDER BY fecha DESC, id DESC LIMIT 1`);
  return rows[0] || null;
}

async function buscarLocalPorNumero(numero, bd = { query: consulta }) {
  const n = normalizarNumero(numero);
  if (!n) throw new ErrorApi(400, 'Escribe el número del local.');
  const { rows } = await bd.query(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.numero = $1 AND l.activo`, [n]);
  if (!rows[0]) throw new ErrorApi(404, `El local ${n} no está registrado. Revisa el número o habla con la administradora.`);
  return rows[0];
}

async function asistenciaDeLocal(asambleaId, localId, bd = { query: consulta }) {
  if (!asambleaId) return null;
  const { rows } = await bd.query(
    `SELECT ${CAMPOS_ASISTENCIA} FROM asistencias a WHERE a.asamblea_id = $1 AND a.local_id = $2`,
    [asambleaId, localId]
  );
  return rows[0] || null;
}

// Registra la asistencia de un local. Si ya estaba registrado devuelve el registro existente.
async function registrarAsistencia(bd, { asamblea, local, tipo, nombre, cedula, registradoPor, reemplazar = false }) {
  const insertado = await bd.query(
    `INSERT INTO asistencias (asamblea_id, local_id, tipo, asistente_nombre, asistente_cedula, coeficiente, registrado_por)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (asamblea_id, local_id) DO NOTHING
     RETURNING id`,
    [asamblea.id, local.id, tipo, nombre, cedula, local.coeficiente, registradoPor]
  );
  if (insertado.rows[0]) {
    return { nueva: true, asistencia: await asistenciaDeLocal(asamblea.id, local.id, bd) };
  }
  if (reemplazar) {
    await bd.query(
      `UPDATE asistencias SET tipo = $3, asistente_nombre = $4, asistente_cedula = $5, registrado_por = $6
       WHERE asamblea_id = $1 AND local_id = $2`,
      [asamblea.id, local.id, tipo, nombre, cedula, registradoPor]
    );
    return { nueva: true, asistencia: await asistenciaDeLocal(asamblea.id, local.id, bd) };
  }
  return { nueva: false, asistencia: await asistenciaDeLocal(asamblea.id, local.id, bd) };
}

async function calcularQuorum(asamblea) {
  const totales = await consulta(
    'SELECT COUNT(*)::int AS locales, COALESCE(SUM(coeficiente), 0)::float8 AS coeficiente FROM locales WHERE activo'
  );
  let presentes = { locales: 0, coeficiente: 0, propietarios: 0, apoderados: 0 };
  if (asamblea) {
    const { rows } = await consulta(
      `SELECT COUNT(*)::int AS locales, COALESCE(SUM(coeficiente), 0)::float8 AS coeficiente,
              COUNT(*) FILTER (WHERE tipo = 'propietario')::int AS propietarios,
              COUNT(*) FILTER (WHERE tipo = 'apoderado')::int AS apoderados
       FROM asistencias WHERE asamblea_id = $1`,
      [asamblea.id]
    );
    presentes = rows[0];
  }
  const total = totales.rows[0];
  const porcentaje = total.coeficiente > 0 ? (presentes.coeficiente / total.coeficiente) * 100 : 0;
  return {
    asamblea,
    total_locales: total.locales,
    coeficiente_total: Number(total.coeficiente.toFixed(6)),
    locales_presentes: presentes.locales,
    propietarios: presentes.propietarios,
    apoderados: presentes.apoderados,
    coeficiente_presente: Number(presentes.coeficiente.toFixed(6)),
    porcentaje: Number(porcentaje.toFixed(2)),
    hay_quorum: porcentaje > 50,
  };
}

function exigirTexto(valor, mensaje) {
  const t = normalizarNombre(valor);
  if (!t) throw new ErrorApi(400, mensaje);
  return t;
}

// Datos de la persona que asiste por el local.
function personaQueAsiste(local, tipo, nombre, cedula) {
  if (!ROLES_ASISTENTE.includes(tipo)) throw new ErrorApi(400, 'Indica si asistes como propietario o como apoderado.');
  if (tipo === 'propietario') {
    return { nombre: local.propietario_nombre, cedula: local.propietario_cedula, apoderadoNuevo: false };
  }
  const n = normalizarNombre(nombre);
  const c = normalizarCedula(cedula);
  if (n || c) {
    if (!n) throw new ErrorApi(400, 'Escribe el nombre completo del apoderado.');
    if (c.length < 5) throw new ErrorApi(400, 'Escribe la cédula del apoderado (solo números).');
    return { nombre: n, cedula: c, apoderadoNuevo: n !== local.apoderado_nombre || c !== local.apoderado_cedula };
  }
  if (local.apoderado_nombre && local.apoderado_cedula) {
    return { nombre: local.apoderado_nombre, cedula: local.apoderado_cedula, apoderadoNuevo: false };
  }
  throw new ErrorApi(400, 'Escribe el nombre y la cédula del apoderado.');
}

async function guardarApoderado(bd, localId, nombre, cedula, registradoPor) {
  await bd.query(
    `UPDATE locales SET apoderado_nombre = $2, apoderado_cedula = $3, apoderado_registrado_por = $4, actualizado_en = now()
     WHERE id = $1`,
    [localId, nombre, cedula, registradoPor]
  );
}

// ---------- Rutas públicas (sin iniciar sesión) ----------

async function salud() {
  await consulta('SELECT 1');
  return { ok: true, servicio: 'asistencia-asamblea', hora: new Date().toISOString() };
}

// Paso 1 del ingreso: muestra a quién pertenece el local (con la cédula oculta).
async function consultarLocalPublico({ parametros }) {
  const local = await buscarLocalPorNumero(parametros.numero);
  const asamblea = await asambleaAbierta();
  const asistencia = asamblea ? await asistenciaDeLocal(asamblea.id, local.id) : null;
  return { local: presentarLocal(local, false, asistencia), asamblea };
}

// Paso 2 del ingreso: el propietario o el apoderado entra y queda registrado.
async function ingresarConLocal({ cuerpo }) {
  const tipo = String(cuerpo.tipo || '').toLowerCase();
  const resultado = await transaccion(async (bd) => {
    const local = await buscarLocalPorNumero(cuerpo.numero, bd);
    const persona = personaQueAsiste(local, tipo, cuerpo.apoderado_nombre, cuerpo.apoderado_cedula);
    if (tipo === 'apoderado' && persona.apoderadoNuevo) {
      await guardarApoderado(bd, local.id, persona.nombre, persona.cedula, 'apoderado');
      local.apoderado_nombre = persona.nombre;
      local.apoderado_cedula = persona.cedula;
      local.apoderado_registrado_por = 'apoderado';
    }
    const asamblea = await asambleaAbierta(bd);
    let registro = { nueva: false, asistencia: null };
    if (asamblea) {
      registro = await registrarAsistencia(bd, {
        asamblea, local, tipo, nombre: persona.nombre, cedula: persona.cedula, registradoPor: 'asistente',
      });
    }
    return { local, persona, asamblea, registro };
  });

  const { local, persona, asamblea, registro } = resultado;
  if (registro.nueva) tiempoReal.avisar('asistencia', { local: local.numero });
  const token = firmar({ rol: tipo, local_id: local.id, nombre: persona.nombre, cedula: persona.cedula });
  return {
    token,
    rol: tipo,
    nombre: persona.nombre,
    local: presentarLocal(local, false, registro.asistencia),
    asamblea,
    asistencia_nueva: registro.nueva,
  };
}

async function ingresarAdministradora({ cuerpo }) {
  const usuario = String(cuerpo.usuario || '').trim().toLowerCase();
  const { rows } = await consulta('SELECT id, usuario, nombre, clave_hash FROM administradores WHERE usuario = $1', [usuario]);
  const admin = rows[0];
  if (!admin || !compararClave(cuerpo.clave || '', admin.clave_hash)) {
    throw new ErrorApi(401, 'Usuario o contraseña incorrectos.');
  }
  const token = firmar({ rol: 'administradora', admin_id: admin.id, nombre: admin.nombre });
  return { token, rol: 'administradora', nombre: admin.nombre, usuario: admin.usuario };
}

// ---------- Rutas con sesión (cualquier rol) ----------

async function miSesion({ sesion }) {
  if (sesion.rol === 'administradora') {
    return { rol: sesion.rol, nombre: sesion.nombre, asamblea: await asambleaAbierta() };
  }
  const { rows } = await consulta(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.id = $1`, [sesion.local_id]);
  if (!rows[0] || !rows[0].activo) throw new ErrorApi(401, 'Tu local ya no está registrado. Vuelve a ingresar.');
  const asamblea = await asambleaAbierta();
  const asistencia = asamblea ? await asistenciaDeLocal(asamblea.id, rows[0].id) : null;
  return {
    rol: sesion.rol,
    nombre: sesion.nombre,
    cedula: ocultarCedula(sesion.cedula),
    local: presentarLocal(rows[0], false, asistencia),
    asamblea,
  };
}

// Para quien ingresó antes de que la administradora abriera la asamblea.
async function registrarMiAsistencia({ sesion }) {
  if (!ROLES_ASISTENTE.includes(sesion.rol)) throw new ErrorApi(403, 'Esta opción es para propietarios y apoderados.');
  const registro = await transaccion(async (bd) => {
    const asamblea = await asambleaAbierta(bd);
    if (!asamblea) throw new ErrorApi(409, 'Todavía no hay una asamblea abierta. Espera a que la administradora la abra.');
    const { rows } = await bd.query(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.id = $1 AND l.activo`, [sesion.local_id]);
    if (!rows[0]) throw new ErrorApi(401, 'Tu local ya no está registrado. Vuelve a ingresar.');
    return registrarAsistencia(bd, {
      asamblea, local: rows[0], tipo: sesion.rol, nombre: sesion.nombre, cedula: sesion.cedula, registradoPor: 'asistente',
    });
  });
  if (registro.nueva) tiempoReal.avisar('asistencia');
  return { asistencia_nueva: registro.nueva, asistencia: presentarAsistencia(registro.asistencia, false) };
}

async function verQuorum({ consultaUrl }) {
  return calcularQuorum(await asambleaElegida(consultaUrl.get('asamblea_id')));
}

// Pestaña "Locales": digita el número y ve propietario o apoderado con su cédula.
async function buscarLocal({ parametros, sesion, consultaUrl }) {
  const completo = sesion.rol === 'administradora';
  const local = await buscarLocalPorNumero(parametros.numero);
  const asamblea = await asambleaElegida(consultaUrl.get('asamblea_id'));
  const asistencia = asamblea ? await asistenciaDeLocal(asamblea.id, local.id) : null;
  return { local: presentarLocal(local, completo, asistencia), asamblea };
}

// ---------- Rutas de la administradora: locales ----------

function datosLocal(cuerpo) {
  const coeficiente = leerDecimal(cuerpo.coeficiente);
  if (Number.isNaN(coeficiente) || coeficiente < 0) throw new ErrorApi(400, 'El coeficiente debe ser un número, por ejemplo 0,8523.');
  const apoderadoNombre = normalizarNombre(cuerpo.apoderado_nombre) || null;
  const apoderadoCedula = normalizarCedula(cuerpo.apoderado_cedula) || null;
  if (Boolean(apoderadoNombre) !== Boolean(apoderadoCedula)) {
    throw new ErrorApi(400, 'Para el apoderado escribe el nombre y la cédula, o deja los dos vacíos.');
  }
  const numero = normalizarNumero(cuerpo.numero);
  if (!numero) throw new ErrorApi(400, 'Escribe el número del local.');
  const propietarioCedula = normalizarCedula(cuerpo.propietario_cedula);
  if (!propietarioCedula) throw new ErrorApi(400, 'Escribe la cédula del propietario.');
  return {
    numero,
    coeficiente,
    propietario_nombre: exigirTexto(cuerpo.propietario_nombre, 'Escribe el nombre del propietario.'),
    propietario_cedula: propietarioCedula,
    apoderado_nombre: apoderadoNombre,
    apoderado_cedula: apoderadoCedula,
  };
}

async function listarLocales({ consultaUrl }) {
  const buscar = String(consultaUrl.get('buscar') || '').trim();
  const inactivos = consultaUrl.get('inactivos') === 'si';
  const asamblea = await asambleaElegida(consultaUrl.get('asamblea_id'));
  const parametros = [asamblea ? asamblea.id : 0];
  let filtro = inactivos ? 'TRUE' : 'l.activo';
  if (buscar) {
    parametros.push(`%${buscar}%`);
    filtro += ` AND (l.numero ILIKE $2 OR l.propietario_nombre ILIKE $2 OR l.propietario_cedula ILIKE $2
                     OR l.apoderado_nombre ILIKE $2 OR l.apoderado_cedula ILIKE $2)`;
  }
  const { rows } = await consulta(
    `SELECT ${CAMPOS_LOCAL}, a.id AS asistencia_id, a.tipo, a.asistente_nombre, a.asistente_cedula,
            a.coeficiente::float8 AS asistencia_coeficiente, a.registrado_por,
            to_char(a.hora_ingreso AT TIME ZONE '${ZONA}', 'HH24:MI') AS hora
     FROM locales l
     LEFT JOIN asistencias a ON a.local_id = l.id AND a.asamblea_id = $1
     WHERE ${filtro}
     ORDER BY ${ORDEN_NATURAL}`,
    parametros
  );
  const locales = rows.map((r) => {
    const asistencia = r.asistencia_id
      ? { ...r, id: r.asistencia_id, coeficiente: r.asistencia_coeficiente }
      : null;
    return presentarLocal(r, true, asistencia);
  });
  return { asamblea, locales };
}

async function crearLocal({ cuerpo }) {
  const d = datosLocal(cuerpo);
  const existente = await consulta('SELECT id, activo FROM locales WHERE numero = $1', [d.numero]);
  if (existente.rows[0] && existente.rows[0].activo) throw new ErrorApi(409, `El local ${d.numero} ya existe.`);
  const valores = [d.numero, d.coeficiente, d.propietario_nombre, d.propietario_cedula, d.apoderado_nombre, d.apoderado_cedula,
    d.apoderado_nombre ? 'administradora' : null];
  const { rows } = await consulta(
    `INSERT INTO locales (numero, coeficiente, propietario_nombre, propietario_cedula, apoderado_nombre, apoderado_cedula, apoderado_registrado_por)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (numero) DO UPDATE SET coeficiente = EXCLUDED.coeficiente, propietario_nombre = EXCLUDED.propietario_nombre,
       propietario_cedula = EXCLUDED.propietario_cedula, apoderado_nombre = EXCLUDED.apoderado_nombre,
       apoderado_cedula = EXCLUDED.apoderado_cedula, apoderado_registrado_por = EXCLUDED.apoderado_registrado_por,
       activo = TRUE, actualizado_en = now()
     RETURNING id`,
    valores
  );
  tiempoReal.avisar('locales');
  const { rows: l } = await consulta(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.id = $1`, [rows[0].id]);
  return { local: presentarLocal(l[0], true) };
}

async function editarLocal({ parametros, cuerpo }) {
  const id = Number(parametros.id);
  const d = datosLocal(cuerpo);
  const { rows: actual } = await consulta(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.id = $1`, [id]);
  if (!actual[0]) throw new ErrorApi(404, 'Ese local no existe.');
  const choque = await consulta('SELECT id FROM locales WHERE numero = $1 AND id <> $2', [d.numero, id]);
  if (choque.rows[0]) throw new ErrorApi(409, `Ya hay otro local con el número ${d.numero}.`);
  const apoderadoCambio = d.apoderado_nombre !== actual[0].apoderado_nombre || d.apoderado_cedula !== actual[0].apoderado_cedula;
  const registradoPor = !d.apoderado_nombre ? null : apoderadoCambio ? 'administradora' : actual[0].apoderado_registrado_por;
  await consulta(
    `UPDATE locales SET numero = $2, coeficiente = $3, propietario_nombre = $4, propietario_cedula = $5,
       apoderado_nombre = $6, apoderado_cedula = $7, apoderado_registrado_por = $8, activo = TRUE, actualizado_en = now()
     WHERE id = $1`,
    [id, d.numero, d.coeficiente, d.propietario_nombre, d.propietario_cedula, d.apoderado_nombre, d.apoderado_cedula, registradoPor]
  );
  tiempoReal.avisar('locales');
  const { rows } = await consulta(`SELECT ${CAMPOS_LOCAL} FROM locales l WHERE l.id = $1`, [id]);
  return { local: presentarLocal(rows[0], true) };
}

async function desactivarLocal({ parametros }) {
  const { rowCount } = await consulta('UPDATE locales SET activo = FALSE, actualizado_en = now() WHERE id = $1', [Number(parametros.id)]);
  if (!rowCount) throw new ErrorApi(404, 'Ese local no existe.');
  tiempoReal.avisar('locales');
  return { ok: true };
}

// Pegar desde Excel: número | coeficiente | propietario | cédula | apoderado | cédula apoderado
async function importarLocales({ cuerpo }) {
  const { filas, errores } = leerTablaLocales(cuerpo.texto);
  if (!filas.length) {
    throw new ErrorApi(400, errores[0] || 'No encontré locales. Copia desde Excel las columnas: número, coeficiente, propietario, cédula.');
  }
  const repetidos = filas.map((f) => f.numero).filter((n, i, t) => t.indexOf(n) !== i);
  if (repetidos.length) throw new ErrorApi(400, `Hay locales repetidos en la lista: ${[...new Set(repetidos)].join(', ')}.`);

  const resumen = await transaccion(async (bd) => {
    let creados = 0;
    let actualizados = 0;
    for (const f of filas) {
      const { rows } = await bd.query(
        `INSERT INTO locales (numero, coeficiente, propietario_nombre, propietario_cedula, apoderado_nombre, apoderado_cedula, apoderado_registrado_por)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (numero) DO UPDATE SET coeficiente = EXCLUDED.coeficiente, propietario_nombre = EXCLUDED.propietario_nombre,
           propietario_cedula = EXCLUDED.propietario_cedula,
           apoderado_nombre = COALESCE(EXCLUDED.apoderado_nombre, locales.apoderado_nombre),
           apoderado_cedula = COALESCE(EXCLUDED.apoderado_cedula, locales.apoderado_cedula),
           apoderado_registrado_por = CASE WHEN EXCLUDED.apoderado_nombre IS NULL THEN locales.apoderado_registrado_por ELSE 'administradora' END,
           activo = TRUE, actualizado_en = now()
         RETURNING (xmax = 0) AS creado`,
        [f.numero, f.coeficiente, f.propietario_nombre, f.propietario_cedula, f.apoderado_nombre, f.apoderado_cedula,
          f.apoderado_nombre ? 'administradora' : null]
      );
      if (rows[0].creado) creados += 1;
      else actualizados += 1;
    }
    let desactivados = 0;
    if (cuerpo.reemplazar === true) {
      const r = await bd.query('UPDATE locales SET activo = FALSE WHERE activo AND NOT (numero = ANY($1::text[]))', [filas.map((f) => f.numero)]);
      desactivados = r.rowCount;
    }
    return { creados, actualizados, desactivados };
  });
  tiempoReal.avisar('locales');
  const total = filas.reduce((s, f) => s + f.coeficiente, 0);
  return { ...resumen, errores, suma_coeficientes: Number(total.toFixed(6)) };
}

// Datos de prueba para ensayar la app (solo si no hay locales).
async function cargarEjemplo() {
  const { rows } = await consulta('SELECT COUNT(*)::int AS total FROM locales WHERE activo');
  if (rows[0].total > 0) throw new ErrorApi(409, 'Ya hay locales registrados. Los datos de ejemplo solo se cargan con la lista vacía.');
  const nombres = [
    'María Fernanda López', 'Carlos Andrés Gómez', 'Luz Marina Rodríguez', 'Jorge Enrique Martínez', 'Ana Lucía Herrera',
    'Pedro Pablo Castro', 'Diana Carolina Ruiz', 'Andrés Felipe Torres', 'Claudia Patricia Díaz', 'Juan Camilo Rojas',
    'Sandra Milena Vargas', 'Óscar Iván Moreno', 'Paola Andrea Jiménez', 'Luis Alberto Ramírez', 'Gloria Inés Suárez',
    'Héctor Fabio Ortiz', 'Natalia Ospina', 'Ricardo Mejía', 'Yolanda Cárdenas', 'Fernando Salazar',
    'Martha Cecilia Peña', 'Diego Alejandro Ríos', 'Liliana Restrepo', 'Germán Acosta', 'Beatriz Cortés',
    'Mauricio Pardo', 'Adriana Lozano', 'Julio César Muñoz', 'Esperanza Gil', 'Camilo Andrés Pineda',
  ];
  const areas = nombres.map((_, i) => 20 + ((i * 37) % 45));
  const sumaAreas = areas.reduce((s, a) => s + a, 0);
  const coeficientes = areas.map((a) => Number(((a / sumaAreas) * 100).toFixed(4)));
  const ajuste = Number((100 - coeficientes.reduce((s, c) => s + c, 0)).toFixed(4));
  coeficientes[0] = Number((coeficientes[0] + ajuste).toFixed(4));
  await transaccion(async (bd) => {
    for (let i = 0; i < nombres.length; i += 1) {
      const numero = String(i < 15 ? 101 + i : 201 + (i - 15));
      const cedula = String(10203040 + i * 1234567);
      const conApoderado = i % 7 === 3;
      await bd.query(
        `INSERT INTO locales (numero, coeficiente, propietario_nombre, propietario_cedula, apoderado_nombre, apoderado_cedula, apoderado_registrado_por)
         VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (numero) DO NOTHING`,
        [numero, coeficientes[i], nombres[i], cedula,
          conApoderado ? 'Apoderado de ejemplo ' + numero : null,
          conApoderado ? String(80000000 + i * 4321) : null,
          conApoderado ? 'administradora' : null]
      );
    }
  });
  tiempoReal.avisar('locales');
  return { creados: nombres.length };
}

// ---------- Rutas de la administradora: asambleas ----------

async function listarAsambleas() {
  const { rows } = await consulta(
    `SELECT ${CAMPOS_ASAMBLEA},
            (SELECT COUNT(*)::int FROM asistencias a WHERE a.asamblea_id = asambleas.id) AS asistentes
     FROM asambleas ORDER BY fecha DESC, id DESC`
  );
  return { asambleas: rows };
}

async function crearAsamblea({ cuerpo }) {
  const nombre = exigirTexto(cuerpo.nombre, 'Escribe el nombre de la asamblea, por ejemplo "Asamblea ordinaria 2026".');
  const fecha = cuerpo.fecha && /^\d{4}-\d{2}-\d{2}$/.test(cuerpo.fecha) ? cuerpo.fecha : null;
  const { rows } = await consulta(
    `INSERT INTO asambleas (nombre, fecha) VALUES ($1, COALESCE($2::date, (now() AT TIME ZONE '${ZONA}')::date)) RETURNING id`,
    [nombre, fecha]
  );
  return { asamblea: await asambleaElegida(rows[0].id) };
}

async function abrirAsamblea({ parametros }) {
  const id = Number(parametros.id);
  const abierta = await asambleaAbierta();
  if (abierta && abierta.id !== id) throw new ErrorApi(409, `Ya está abierta "${abierta.nombre}". Ciérrala primero.`);
  const { rowCount } = await consulta(
    `UPDATE asambleas SET estado = 'abierta', abierta_en = COALESCE(abierta_en, now()), cerrada_en = NULL WHERE id = $1`,
    [id]
  );
  if (!rowCount) throw new ErrorApi(404, 'Esa asamblea no existe.');
  tiempoReal.avisar('asamblea');
  return { asamblea: await asambleaElegida(id) };
}

async function cerrarAsamblea({ parametros }) {
  const id = Number(parametros.id);
  const { rowCount } = await consulta(
    `UPDATE asambleas SET estado = 'cerrada', cerrada_en = now() WHERE id = $1 AND estado = 'abierta'`,
    [id]
  );
  if (!rowCount) throw new ErrorApi(409, 'Esa asamblea no está abierta.');
  tiempoReal.avisar('asamblea');
  return { asamblea: await asambleaElegida(id) };
}

async function borrarAsamblea({ parametros }) {
  const id = Number(parametros.id);
  const { rows } = await consulta(
    `SELECT estado, (SELECT COUNT(*)::int FROM asistencias WHERE asamblea_id = $1) AS asistentes FROM asambleas WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw new ErrorApi(404, 'Esa asamblea no existe.');
  if (rows[0].estado === 'abierta' || rows[0].asistentes > 0) {
    throw new ErrorApi(409, 'Solo se pueden borrar asambleas cerradas o sin abrir y sin asistentes.');
  }
  await consulta('DELETE FROM asambleas WHERE id = $1', [id]);
  return { ok: true };
}

// ---------- Rutas de la administradora: asistencia ----------

async function listarAsistencias({ consultaUrl }) {
  const asamblea = await asambleaElegida(consultaUrl.get('asamblea_id'));
  if (!asamblea) return { asamblea: null, asistencias: [] };
  const { rows } = await consulta(
    `SELECT ${CAMPOS_ASISTENCIA}, l.numero
     FROM asistencias a JOIN locales l ON l.id = a.local_id
     WHERE a.asamblea_id = $1 ORDER BY a.hora_ingreso DESC`,
    [asamblea.id]
  );
  return {
    asamblea,
    asistencias: rows.map((r) => ({ ...presentarAsistencia(r, true), numero: r.numero })),
  };
}

async function registrarAsistenciaAdmin({ cuerpo }) {
  const tipo = String(cuerpo.tipo || '').toLowerCase();
  const resultado = await transaccion(async (bd) => {
    const asamblea = await asambleaAbierta(bd);
    if (!asamblea) throw new ErrorApi(409, 'Primero abre una asamblea en la pestaña Asambleas.');
    const local = await buscarLocalPorNumero(cuerpo.numero, bd);
    const persona = personaQueAsiste(local, tipo, cuerpo.nombre, cuerpo.cedula);
    if (tipo === 'apoderado' && persona.apoderadoNuevo) {
      await guardarApoderado(bd, local.id, persona.nombre, persona.cedula, 'administradora');
    }
    const registro = await registrarAsistencia(bd, {
      asamblea, local, tipo, nombre: persona.nombre, cedula: persona.cedula,
      registradoPor: 'administradora', reemplazar: cuerpo.reemplazar === true,
    });
    return { local, registro };
  });
  const { local, registro } = resultado;
  if (!registro.nueva) {
    const a = registro.asistencia;
    throw new ErrorApi(409, `El local ${local.numero} ya está registrado a las ${a.hora} (${a.tipo}: ${a.asistente_nombre}).`);
  }
  tiempoReal.avisar('asistencia', { local: local.numero });
  return { asistencia: { ...presentarAsistencia(registro.asistencia, true), numero: local.numero } };
}

async function borrarAsistencia({ parametros }) {
  const { rowCount } = await consulta('DELETE FROM asistencias WHERE id = $1', [Number(parametros.id)]);
  if (!rowCount) throw new ErrorApi(404, 'Ese registro de asistencia no existe.');
  tiempoReal.avisar('asistencia');
  return { ok: true };
}

async function datosInforme(asambleaId) {
  const asamblea = await asambleaElegida(asambleaId);
  if (!asamblea) throw new ErrorApi(404, 'Todavía no hay asambleas.');
  const quorum = await calcularQuorum(asamblea);
  const { rows } = await consulta(
    `SELECT l.numero, l.coeficiente::float8 AS coeficiente_local, l.propietario_nombre, l.propietario_cedula,
            ${CAMPOS_ASISTENCIA}
     FROM locales l
     LEFT JOIN asistencias a ON a.local_id = l.id AND a.asamblea_id = $1
     WHERE l.activo OR a.id IS NOT NULL
     ORDER BY ${ORDEN_NATURAL}`,
    [asamblea.id]
  );
  return { asamblea, quorum, filas: rows };
}

// Archivo que se abre en Excel (separado por punto y coma, con tildes correctas).
async function exportarCsv({ consultaUrl }) {
  const { asamblea, quorum, filas } = await datosInforme(consultaUrl.get('asamblea_id'));
  const dec = (n) => (n === null || n === undefined ? '' : String(n).replace('.', ','));
  const tipoTexto = (t) => (t === 'apoderado' ? 'Apoderado' : t === 'propietario' ? 'Propietario' : '');
  const lineas = [
    ['Asamblea', asamblea.nombre].map(csvCampo).join(';'),
    ['Fecha', fechaColombia(asamblea.fecha)].map(csvCampo).join(';'),
    ['Quórum (%)', dec(quorum.porcentaje)].map(csvCampo).join(';'),
    '',
    ['Local', 'Coeficiente', 'Propietario', 'Cédula propietario', 'Asistió', 'Asiste como', 'Nombre de quien asiste',
      'Cédula de quien asiste', 'Hora', 'Registrado por'].map(csvCampo).join(';'),
    ...filas.map((f) => [
      f.numero, dec(f.coeficiente_local), f.propietario_nombre, f.propietario_cedula,
      f.id ? 'Sí' : 'No', tipoTexto(f.tipo), f.asistente_nombre || '', f.asistente_cedula || '', f.hora || '',
      f.registrado_por === 'administradora' ? 'Administradora' : f.registrado_por ? 'App' : '',
    ].map(csvCampo).join(';')),
  ];
  const nombreArchivo = `asistencia-${asamblea.fecha}.csv`;
  return {
    __crudo: true,
    tipo: 'text/csv; charset=utf-8',
    cabeceras: { 'Content-Disposition': `attachment; filename="${nombreArchivo}"` },
    cuerpo: '﻿' + lineas.join('\r\n'),
  };
}

// Acta de asistencia lista para imprimir o guardar como PDF desde el navegador.
async function actaHtml({ consultaUrl }) {
  const { asamblea, quorum, filas } = await datosInforme(consultaUrl.get('asamblea_id'));
  const e = escaparHtml;
  const asistentes = filas.filter((f) => f.id);
  const filasHtml = asistentes.map((f, i) => `
      <tr><td>${i + 1}</td><td>${e(f.numero)}</td><td class="n">${e(String(f.coeficiente).replace('.', ','))}</td>
      <td>${e(f.tipo === 'apoderado' ? 'Apoderado' : 'Propietario')}</td><td>${e(f.asistente_nombre)}</td>
      <td>${e(f.asistente_cedula)}</td><td>${e(f.hora)}</td><td class="firma"></td></tr>`).join('');
  const html = `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Acta de asistencia – ${e(asamblea.nombre)}</title>
<style>
  body{font-family:Arial,Helvetica,sans-serif;margin:24px;color:#1b1b1b}
  h1{font-size:20px;margin:0 0 4px} .sub{color:#555;margin-bottom:16px}
  .res{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:16px}
  .res div{border:1px solid #ccc;border-radius:8px;padding:8px 12px}
  .res b{display:block;font-size:18px}
  table{border-collapse:collapse;width:100%;font-size:12px}
  th,td{border:1px solid #bbb;padding:5px 6px;text-align:left} th{background:#eef2f7}
  td.n{text-align:right} td.firma{width:140px}
  .boton{margin-bottom:16px;padding:8px 14px;font-size:14px;cursor:pointer}
  @media print{.boton{display:none} body{margin:10mm}}
</style></head><body>
<button class="boton" onclick="window.print()">Imprimir o guardar como PDF</button>
<h1>Acta de asistencia – ${e(asamblea.nombre)}</h1>
<div class="sub">Fecha: ${e(fechaColombia(asamblea.fecha))}${asamblea.hora_apertura ? ` · Apertura: ${e(asamblea.hora_apertura)}` : ''}${asamblea.hora_cierre ? ` · Cierre: ${e(asamblea.hora_cierre)}` : ''}</div>
<div class="res">
  <div>Quórum<b>${e(String(quorum.porcentaje).replace('.', ','))} %</b></div>
  <div>Locales presentes<b>${quorum.locales_presentes} de ${quorum.total_locales}</b></div>
  <div>Propietarios<b>${quorum.propietarios}</b></div>
  <div>Apoderados<b>${quorum.apoderados}</b></div>
  <div>Estado<b>${quorum.hay_quorum ? 'Hay quórum' : 'Sin quórum'}</b></div>
</div>
<table><thead><tr><th>#</th><th>Local</th><th>Coeficiente</th><th>Asiste como</th><th>Nombre</th><th>Cédula</th><th>Hora</th><th>Firma</th></tr></thead>
<tbody>${filasHtml || '<tr><td colspan="8">Sin asistentes registrados.</td></tr>'}</tbody></table>
</body></html>`;
  return { __crudo: true, tipo: 'text/html; charset=utf-8', cuerpo: html };
}

async function cambiarClave({ sesion, cuerpo }) {
  const { rows } = await consulta('SELECT clave_hash FROM administradores WHERE id = $1', [sesion.admin_id]);
  if (!rows[0] || !compararClave(cuerpo.actual || '', rows[0].clave_hash)) throw new ErrorApi(400, 'La contraseña actual no es correcta.');
  const nueva = String(cuerpo.nueva || '');
  if (nueva.length < 6) throw new ErrorApi(400, 'La nueva contraseña debe tener al menos 6 caracteres.');
  await consulta('UPDATE administradores SET clave_hash = $2 WHERE id = $1', [sesion.admin_id, cifrarClave(nueva)]);
  return { ok: true };
}

// ---------- Tabla de rutas ----------
// acceso: null = pública, 'sesion' = cualquier rol, 'admin' = solo administradora

const rutas = [
  ['GET', '/api/salud', salud, null],
  ['GET', '/api/publico/local/:numero', consultarLocalPublico, null],
  ['POST', '/api/acceso', ingresarConLocal, null],
  ['POST', '/api/admin/ingreso', ingresarAdministradora, null],

  ['GET', '/api/sesion', miSesion, 'sesion'],
  ['POST', '/api/mi-asistencia', registrarMiAsistencia, 'sesion'],
  ['GET', '/api/quorum', verQuorum, 'sesion'],
  ['GET', '/api/locales/:numero', buscarLocal, 'sesion'],

  ['GET', '/api/admin/locales', listarLocales, 'admin'],
  ['POST', '/api/admin/locales', crearLocal, 'admin'],
  ['POST', '/api/admin/locales/importar', importarLocales, 'admin'],
  ['POST', '/api/admin/locales/ejemplo', cargarEjemplo, 'admin'],
  ['PUT', '/api/admin/locales/:id', editarLocal, 'admin'],
  ['DELETE', '/api/admin/locales/:id', desactivarLocal, 'admin'],

  ['GET', '/api/admin/asambleas', listarAsambleas, 'admin'],
  ['POST', '/api/admin/asambleas', crearAsamblea, 'admin'],
  ['POST', '/api/admin/asambleas/:id/abrir', abrirAsamblea, 'admin'],
  ['POST', '/api/admin/asambleas/:id/cerrar', cerrarAsamblea, 'admin'],
  ['DELETE', '/api/admin/asambleas/:id', borrarAsamblea, 'admin'],

  ['GET', '/api/admin/asistencias', listarAsistencias, 'admin'],
  ['POST', '/api/admin/asistencias', registrarAsistenciaAdmin, 'admin'],
  ['DELETE', '/api/admin/asistencias/:id', borrarAsistencia, 'admin'],
  ['GET', '/api/admin/informes/asistencia.csv', exportarCsv, 'admin'],
  ['GET', '/api/admin/informes/acta', actaHtml, 'admin'],

  ['PUT', '/api/admin/clave', cambiarClave, 'admin'],
];

module.exports = { rutas };
