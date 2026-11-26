'use strict';
// Pruebas de la API contra una base PostgreSQL real.
// Uso: DATABASE_URL=postgres://.../asistencia_prueba npm test
// Por seguridad, la base debe llamarse con la palabra "prueba" porque se borra al empezar.
const test = require('node:test');
const assert = require('node:assert/strict');

const url = process.env.DATABASE_URL || '';
if (!/prueba/i.test(new URL(url || 'postgres://x/x').pathname + (new URL(url || 'postgres://x/x').searchParams.get('dbname') || ''))) {
  throw new Error('Define DATABASE_URL apuntando a una base cuyo nombre contenga "prueba" (se borra al empezar).');
}
process.env.TOKEN_SECRETO = 'secreto-de-prueba';
process.env.NODE_ENV = 'test';
// Carpeta con una "app web" de prueba (modo sin internet).
const fs = require('fs');
const os = require('os');
const path = require('path');
const carpetaWeb = fs.mkdtempSync(path.join(os.tmpdir(), 'web-'));
fs.mkdirSync(path.join(carpetaWeb, 'assets'));
fs.writeFileSync(path.join(carpetaWeb, 'index.html'), '<!DOCTYPE html><title>App de prueba</title>');
fs.writeFileSync(path.join(carpetaWeb, 'main.dart.js'), 'console.log(1)');
fs.writeFileSync(path.join(carpetaWeb, 'canvaskit.wasm'), 'wasm');
process.env.CARPETA_WEB = carpetaWeb;
process.env.ADMIN_USUARIO = 'admin';
process.env.ADMIN_CLAVE = 'clave123';

const bd = require('../src/bd');
const { arrancar } = require('../src/servidor');
const tiempoReal = require('../src/tiempo_real');

let servidor;
let base;
let tokenAdmin;

async function pedir(metodo, ruta, { cuerpo, token } = {}) {
  const res = await fetch(base + ruta, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  const tipo = res.headers.get('content-type') || '';
  const datos = tipo.includes('json') ? await res.json() : await res.text();
  return { estado: res.status, datos, cabeceras: res.headers };
}

test.before(async () => {
  await bd.pool.query('DROP TABLE IF EXISTS votos, preguntas, asistencias, asambleas, locales, administradores CASCADE');
  servidor = await arrancar(0);
  base = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  tiempoReal.cerrar();
  await new Promise((r) => servidor.close(r));
  await bd.pool.end();
});

test('la API responde y la base está lista', async () => {
  const r = await pedir('GET', '/api/salud');
  assert.equal(r.estado, 200);
  assert.equal(r.datos.ok, true);
});

test('ingreso de la administradora', async () => {
  const mal = await pedir('POST', '/api/admin/ingreso', { cuerpo: { usuario: 'admin', clave: 'otra' } });
  assert.equal(mal.estado, 401);
  const bien = await pedir('POST', '/api/admin/ingreso', { cuerpo: { usuario: ' ADMIN ', clave: 'clave123' } });
  assert.equal(bien.estado, 200);
  assert.equal(bien.datos.rol, 'administradora');
  tokenAdmin = bien.datos.token;
});

test('rutas protegidas exigen sesión', async () => {
  assert.equal((await pedir('GET', '/api/quorum')).estado, 401);
  assert.equal((await pedir('GET', '/api/admin/locales', { token: 'basura.firma' })).estado, 401);
});

test('datos de ejemplo: 51 locales (1 a 51) que suman 100 de coeficiente', async () => {
  const r = await pedir('POST', '/api/admin/locales/ejemplo', { token: tokenAdmin });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.creados, 51);
  const otra = await pedir('POST', '/api/admin/locales/ejemplo', { token: tokenAdmin });
  assert.equal(otra.estado, 409);
  const q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.total_locales, 51);
  assert.equal(q.datos.coeficiente_total, 100);
  assert.equal(q.datos.asamblea, null);
});

test('importar locales pegados desde Excel', async () => {
  const texto = [
    'Local\tCoeficiente\tPropietario\tCédula\tApoderado\tCédula apoderado',
    'L-1\t1,25\tRosa Elena Prieto\t52.123.456\t\t',
    'l-2\t0,75\tTomás Quintero\t79123456\tLaura Quintero\t1020304050',
    '1\t3,5\tNuevo dueño del 1\t11223344',
    'L-3\tabc\tSin coeficiente\t123',
  ].join('\n');
  const r = await pedir('POST', '/api/admin/locales/importar', { token: tokenAdmin, cuerpo: { texto } });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.equal(r.datos.creados, 2);
  assert.equal(r.datos.actualizados, 1);
  assert.equal(r.datos.errores.length, 1);
  const l2 = await pedir('GET', '/api/locales/L-2', { token: tokenAdmin });
  assert.equal(l2.datos.local.coeficiente, 0.75);
  assert.equal(l2.datos.local.apoderado.nombre, 'Laura Quintero');
  assert.equal(l2.datos.local.apoderado.registrado_por, 'administradora');
  const l1 = await pedir('GET', '/api/locales/l-1', { token: tokenAdmin });
  assert.equal(l1.datos.local.propietario.cedula, '52123456');

  const repetidos = await pedir('POST', '/api/admin/locales/importar', {
    token: tokenAdmin, cuerpo: { texto: 'A\t1\tX\t123\nA\t2\tY\t456' },
  });
  assert.equal(repetidos.estado, 400);
});

test('consulta pública del local muestra la cédula oculta', async () => {
  const r = await pedir('GET', '/api/publico/local/%20l-2%20');
  assert.equal(r.estado, 200);
  assert.equal(r.datos.local.numero, 'L-2');
  assert.equal(r.datos.local.propietario.cedula, '****3456');
  assert.equal(r.datos.local.apoderado.cedula, '******4050');
  const no = await pedir('GET', '/api/publico/local/999');
  assert.equal(no.estado, 404);
  assert.match(no.datos.error, /no está registrado/);
});

let tokenPropietario101;

test('ingresar sin asamblea abierta no registra asistencia', async () => {
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: '1', tipo: 'propietario' } });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.rol, 'propietario');
  assert.equal(r.datos.asamblea, null);
  assert.equal(r.datos.asistencia_nueva, false);
  assert.equal(r.datos.local.asistencia, null);
  tokenPropietario101 = r.datos.token;
  const s = await pedir('GET', '/api/sesion', { token: tokenPropietario101 });
  assert.equal(s.datos.local.numero, '1');
  assert.equal((await pedir('POST', '/api/mi-asistencia', { token: tokenPropietario101 })).estado, 409);
  assert.equal((await pedir('GET', '/api/admin/locales', { token: tokenPropietario101 })).estado, 403);
});

let asambleaId;

test('crear y abrir asamblea; solo una abierta a la vez', async () => {
  const a = await pedir('POST', '/api/admin/asambleas', { token: tokenAdmin, cuerpo: { nombre: 'Asamblea ordinaria 2026', fecha: '2026-11-28' } });
  assert.equal(a.estado, 200);
  asambleaId = a.datos.asamblea.id;
  assert.equal(a.datos.asamblea.fecha, '2026-11-28');
  assert.equal(a.datos.asamblea.estado, 'creada');
  const b = await pedir('POST', '/api/admin/asambleas', { token: tokenAdmin, cuerpo: { nombre: 'Extraordinaria' } });
  assert.equal((await pedir('POST', `/api/admin/asambleas/${asambleaId}/abrir`, { token: tokenAdmin })).estado, 200);
  const choque = await pedir('POST', `/api/admin/asambleas/${b.datos.asamblea.id}/abrir`, { token: tokenAdmin });
  assert.equal(choque.estado, 409);
  assert.equal((await pedir('DELETE', `/api/admin/asambleas/${b.datos.asamblea.id}`, { token: tokenAdmin })).estado, 200);
});

test('tiempo real: avisa cuando alguien registra asistencia', async () => {
  const ws = new WebSocket(base.replace('http', 'ws') + '/ws');
  const eventos = [];
  await new Promise((resolve, reject) => {
    ws.onmessage = (m) => { eventos.push(JSON.parse(m.data)); if (eventos.length === 1) resolve(); };
    ws.onerror = reject;
  });
  const r = await pedir('POST', '/api/mi-asistencia', { token: tokenPropietario101 });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.asistencia_nueva, true);
  await new Promise((res) => setTimeout(res, 200));
  ws.close();
  assert.ok(eventos.some((e) => e.evento === 'asistencia'), JSON.stringify(eventos));
  const otra = await pedir('POST', '/api/mi-asistencia', { token: tokenPropietario101 });
  assert.equal(otra.datos.asistencia_nueva, false);
});

test('el propietario queda presente al ingresar y el quórum sube', async () => {
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: 'L-1', tipo: 'propietario' } });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.asistencia_nueva, true);
  assert.equal(r.datos.local.asistencia.tipo, 'propietario');
  assert.equal(r.datos.local.asistencia.nombre, 'Rosa Elena Prieto');
  assert.match(r.datos.local.asistencia.hora, /^\d\d:\d\d$/);
  // Si alguien más entra con el mismo local, no se duplica.
  const dup = await pedir('POST', '/api/acceso', { cuerpo: { numero: 'L-1', tipo: 'apoderado', apoderado_nombre: 'Otra Persona', apoderado_cedula: '99887766' } });
  assert.equal(dup.datos.asistencia_nueva, false);
  assert.equal(dup.datos.local.asistencia.tipo, 'propietario');

  const q = await pedir('GET', '/api/quorum', { token: r.datos.token });
  assert.equal(q.datos.locales_presentes, 2);
  assert.equal(q.datos.coeficiente_presente, 4.75); // 1 (3,5) + L-1 (1,25)
  assert.ok(q.datos.coeficiente_total > 100);
  assert.equal(q.datos.porcentaje, Number(((4.75 / q.datos.coeficiente_total) * 100).toFixed(2)));
  assert.equal(q.datos.hay_quorum, false);
});

test('el apoderado se registra solo con nombre y cédula', async () => {
  const sinDatos = await pedir('POST', '/api/acceso', { cuerpo: { numero: '2', tipo: 'apoderado' } });
  assert.equal(sinDatos.estado, 400);
  const r = await pedir('POST', '/api/acceso', {
    cuerpo: { numero: '2', tipo: 'apoderado', apoderado_nombre: '  Julián   Pérez ', apoderado_cedula: '1.098.765.432' },
  });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.equal(r.datos.rol, 'apoderado');
  assert.equal(r.datos.local.asistencia.tipo, 'apoderado');
  assert.equal(r.datos.local.asistencia.nombre, 'Julián Pérez');
  const admin = await pedir('GET', '/api/locales/2', { token: tokenAdmin });
  assert.equal(admin.datos.local.apoderado.cedula, '1098765432');
  assert.equal(admin.datos.local.apoderado.registrado_por, 'apoderado');
  assert.equal(admin.datos.local.asistencia.cedula, '1098765432');
  // El propietario de otro local ve la cédula oculta.
  const visto = await pedir('GET', '/api/locales/2', { token: tokenPropietario101 });
  assert.equal(visto.datos.local.apoderado.cedula, '******5432');
  assert.equal(visto.datos.local.asistencia.cedula, '******5432');
});

test('apoderado cargado por la administradora entra sin volver a escribir datos', async () => {
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: 'L-2', tipo: 'apoderado' } });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.nombre, 'Laura Quintero');
  assert.equal(r.datos.local.asistencia.nombre, 'Laura Quintero');
});

test('la administradora registra asistencia manual y corrige', async () => {
  const r = await pedir('POST', '/api/admin/asistencias', { token: tokenAdmin, cuerpo: { numero: '3', tipo: 'propietario' } });
  assert.equal(r.estado, 200);
  const dup = await pedir('POST', '/api/admin/asistencias', { token: tokenAdmin, cuerpo: { numero: '3', tipo: 'propietario' } });
  assert.equal(dup.estado, 409);
  assert.match(dup.datos.error, /ya está registrado/);
  const corregir = await pedir('POST', '/api/admin/asistencias', {
    token: tokenAdmin, cuerpo: { numero: '3', tipo: 'apoderado', nombre: 'Marta Gil', cedula: '43111222', reemplazar: true },
  });
  assert.equal(corregir.estado, 200);
  assert.equal(corregir.datos.asistencia.tipo, 'apoderado');
  assert.equal(corregir.datos.asistencia.registrado_por, 'administradora');

  const lista = await pedir('GET', '/api/admin/asistencias', { token: tokenAdmin });
  assert.equal(lista.datos.asistencias.length, 5);
  const q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.propietarios, 2);
  assert.equal(q.datos.apoderados, 3);

  const borrar = await pedir('DELETE', `/api/admin/asistencias/${corregir.datos.asistencia.id}`, { token: tokenAdmin });
  assert.equal(borrar.estado, 200);
  const q2 = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q2.datos.locales_presentes, 4);
});

test('lista de locales con buscador y estado de asistencia', async () => {
  const todo = await pedir('GET', '/api/admin/locales', { token: tokenAdmin });
  assert.equal(todo.datos.locales.length, 53);
  assert.deepEqual(todo.datos.locales.slice(0, 3).map((l) => l.numero), ['1', 'L-1', '2']);
  const l101 = todo.datos.locales.find((l) => l.numero === '1');
  assert.equal(l101.coeficiente, 3.5);
  assert.equal(l101.asistencia.tipo, 'propietario');
  const l104 = todo.datos.locales.find((l) => l.numero === '4');
  assert.equal(l104.asistencia, null);
  assert.ok(l104.coeficiente > 0);
  const buscado = await pedir('GET', '/api/admin/locales?buscar=quintero', { token: tokenAdmin });
  assert.equal(buscado.datos.locales.length, 1);
});

test('informes: Excel (CSV) y acta para imprimir', async () => {
  const csv = await fetch(`${base}/api/admin/informes/asistencia.csv?token=${tokenAdmin}`);
  assert.equal(csv.status, 200);
  assert.match(csv.headers.get('content-disposition'), /asistencia-2026-11-28\.csv/);
  const texto = await csv.text();
  assert.ok(texto.includes('Local;Coeficiente;Propietario'));
  assert.ok(texto.includes('Fecha;28/11/2026'));
  assert.ok(texto.replace(/^\uFEFF/, '').startsWith('Trebolis Capellanía Centro Comercial'));
  assert.ok(texto.includes('L-1;1,25;Rosa Elena Prieto;52123456;Sí;Propietario'));
  const acta = await fetch(`${base}/api/admin/informes/acta?token=${tokenAdmin}`);
  const html = await acta.text();
  assert.ok(html.includes('Acta de asistencia – Asamblea ordinaria 2026'));
  assert.ok(html.includes('Julián Pérez'));
  const sinPermiso = await fetch(`${base}/api/admin/informes/acta?token=${tokenPropietario101}`);
  assert.equal(sinPermiso.status, 403);
});

test('editar y desactivar locales', async () => {
  const l = await pedir('GET', '/api/locales/4', { token: tokenAdmin });
  const id = l.datos.local.id;
  const e = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin,
    cuerpo: { numero: '4', coeficiente: '2,5', propietario_nombre: 'Dueña Nueva', propietario_cedula: '1.234.567', apoderado_nombre: '', apoderado_cedula: '' },
  });
  assert.equal(e.estado, 200, JSON.stringify(e.datos));
  assert.equal(e.datos.local.coeficiente, 2.5);
  assert.equal(e.datos.local.apoderado, null);
  const mitad = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin, cuerpo: { numero: '4', coeficiente: '2', propietario_nombre: 'X', propietario_cedula: '1', apoderado_nombre: 'Solo nombre' },
  });
  assert.equal(mitad.estado, 400);
  const choque = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin, cuerpo: { numero: '5', coeficiente: '2', propietario_nombre: 'X', propietario_cedula: '1' },
  });
  assert.equal(choque.estado, 409);
  assert.equal((await pedir('DELETE', `/api/admin/locales/${id}`, { token: tokenAdmin })).estado, 200);
  assert.equal((await pedir('GET', '/api/publico/local/4')).estado, 404);
  const crear = await pedir('POST', '/api/admin/locales', {
    token: tokenAdmin, cuerpo: { numero: '4', coeficiente: 1, propietario_nombre: 'Vuelve', propietario_cedula: '555666' },
  });
  assert.equal(crear.estado, 200);
  assert.equal(crear.datos.local.id, id);
  const yaExiste = await pedir('POST', '/api/admin/locales', {
    token: tokenAdmin, cuerpo: { numero: '4', coeficiente: 1, propietario_nombre: 'Vuelve', propietario_cedula: '555666' },
  });
  assert.equal(yaExiste.estado, 409);
});

test('cerrar la asamblea: quien entra después no queda registrado', async () => {
  assert.equal((await pedir('POST', `/api/admin/asambleas/${asambleaId}/cerrar`, { token: tokenAdmin })).estado, 200);
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: '10', tipo: 'propietario' } });
  assert.equal(r.datos.asistencia_nueva, false);
  assert.equal(r.datos.asamblea, null);
  // El quórum sigue mostrando la última asamblea.
  const q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.asamblea.estado, 'cerrada');
  assert.equal(q.datos.locales_presentes, 4);
  const lista = await pedir('GET', '/api/admin/asambleas', { token: tokenAdmin });
  assert.equal(lista.datos.asambleas[0].asistentes, 4);
  assert.equal((await pedir('DELETE', `/api/admin/asambleas/${asambleaId}`, { token: tokenAdmin })).estado, 409);
});

test('cambiar la contraseña de la administradora', async () => {
  const mal = await pedir('PUT', '/api/admin/clave', { token: tokenAdmin, cuerpo: { actual: 'x', nueva: 'nueva123' } });
  assert.equal(mal.estado, 400);
  const bien = await pedir('PUT', '/api/admin/clave', { token: tokenAdmin, cuerpo: { actual: 'clave123', nueva: 'nueva123' } });
  assert.equal(bien.estado, 200);
  const ingreso = await pedir('POST', '/api/admin/ingreso', { cuerpo: { usuario: 'admin', clave: 'nueva123' } });
  assert.equal(ingreso.estado, 200);
});

test('quitar el apoderado de un local', async () => {
  const l = await pedir('GET', '/api/locales/L-2', { token: tokenAdmin });
  assert.ok(l.datos.local.apoderado);
  const r = await pedir('DELETE', `/api/admin/locales/${l.datos.local.id}/apoderado`, { token: tokenAdmin });
  assert.equal(r.estado, 200);
  const despues = await pedir('GET', '/api/locales/L-2', { token: tokenAdmin });
  assert.equal(despues.datos.local.apoderado, null);
});

test('quitar un local con la asamblea abierta también quita su asistencia', async () => {
  const a = await pedir('POST', '/api/admin/asambleas', { token: tokenAdmin, cuerpo: { nombre: 'Prueba de borrado' } });
  const id = a.datos.asamblea.id;
  await pedir('POST', `/api/admin/asambleas/${id}/abrir`, { token: tokenAdmin });
  await pedir('POST', '/api/acceso', { cuerpo: { numero: '20', tipo: 'propietario' } });
  await pedir('POST', '/api/acceso', { cuerpo: { numero: '21', tipo: 'propietario' } });
  let q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.locales_presentes, 2);
  const l20 = await pedir('GET', '/api/locales/20', { token: tokenAdmin });
  await pedir('DELETE', `/api/admin/locales/${l20.datos.local.id}`, { token: tokenAdmin });
  q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.locales_presentes, 1);

  // Una asamblea abierta no se borra; cerrada y con asistentes, solo confirmando.
  assert.equal((await pedir('DELETE', `/api/admin/asambleas/${id}`, { token: tokenAdmin })).estado, 409);
  await pedir('POST', `/api/admin/asambleas/${id}/cerrar`, { token: tokenAdmin });
  const sinConfirmar = await pedir('DELETE', `/api/admin/asambleas/${id}`, { token: tokenAdmin });
  assert.equal(sinConfirmar.estado, 409);
  assert.match(sinConfirmar.datos.error, /BORRAR/);
  const borrada = await pedir('DELETE', `/api/admin/asambleas/${id}?forzar=si`, { token: tokenAdmin });
  assert.equal(borrada.estado, 200);
  assert.equal(borrada.datos.asistencias_borradas, 1);
});

test('borrar todos los locales y volver a cargar los de ejemplo', async () => {
  const mal = await pedir('POST', '/api/admin/locales/borrar-todos', { token: tokenAdmin, cuerpo: { confirmacion: 'si' } });
  assert.equal(mal.estado, 400);
  const bien = await pedir('POST', '/api/admin/locales/borrar-todos', { token: tokenAdmin, cuerpo: { confirmacion: 'borrar' } });
  assert.equal(bien.estado, 200);
  assert.ok(bien.datos.locales_quitados > 50);
  let q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.total_locales, 0);
  assert.equal((await pedir('GET', '/api/publico/local/1')).estado, 404);
  // Los de ejemplo se pueden cargar otra vez aunque los números ya existían.
  const ej = await pedir('POST', '/api/admin/locales/ejemplo', { token: tokenAdmin });
  assert.equal(ej.estado, 200);
  q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.total_locales, 51);
  assert.equal(q.datos.coeficiente_total, 100);
});

// ---------------- Votaciones ----------------

let tokenLogistica;
let tokenVotante1;
let tokenVotante2;
let preguntaId;

test('la administradora tiene el nombre configurado', async () => {
  const s = await pedir('GET', '/api/sesion', { token: tokenAdmin });
  assert.equal(s.estado, 200);
  const r = await pedir('POST', '/api/admin/ingreso', { cuerpo: { usuario: 'admin', clave: 'nueva123' } });
  assert.equal(r.datos.nombre, 'Sandra Libey Martinez Real');
  assert.equal(r.datos.rol, 'administradora');
});

test('la administradora crea la cuenta de logística', async () => {
  const antes = await pedir('GET', '/api/admin/logistica', { token: tokenAdmin });
  assert.equal(antes.datos.existe, false);
  const sinClave = await pedir('PUT', '/api/admin/logistica', { token: tokenAdmin, cuerpo: { nombre: 'Equipo logístico' } });
  assert.equal(sinClave.estado, 400);
  const ok = await pedir('PUT', '/api/admin/logistica', { token: tokenAdmin, cuerpo: { nombre: 'Equipo logístico', clave: 'logi2026' } });
  assert.equal(ok.estado, 200);
  assert.equal(ok.datos.existe, true);
  const ingreso = await pedir('POST', '/api/admin/ingreso', { cuerpo: { usuario: 'logistica', clave: 'logi2026' } });
  assert.equal(ingreso.estado, 200);
  assert.equal(ingreso.datos.rol, 'logistica');
  tokenLogistica = ingreso.datos.token;
  // Logística no maneja locales ni asambleas, pero sí asistencia y votaciones.
  assert.equal((await pedir('GET', '/api/admin/locales', { token: tokenLogistica })).estado, 403);
  assert.equal((await pedir('POST', '/api/admin/asambleas', { token: tokenLogistica, cuerpo: { nombre: 'x' } })).estado, 403);
  assert.equal((await pedir('GET', '/api/admin/asistencias', { token: tokenLogistica })).estado, 200);
  const consulta = await pedir('GET', '/api/locales/1', { token: tokenLogistica });
  assert.ok(!consulta.datos.local.propietario.cedula.includes('*'));
});

test('no se pueden crear preguntas sin asamblea abierta', async () => {
  const r = await pedir('POST', '/api/gestion/preguntas', { token: tokenLogistica, cuerpo: { texto: '¿Aprueba el presupuesto?' } });
  assert.equal(r.estado, 409);
});

test('logística crea y abre una pregunta; los asistentes la ven', async () => {
  const a = await pedir('POST', '/api/admin/asambleas', { token: tokenAdmin, cuerpo: { nombre: 'Asamblea con votaciones' } });
  await pedir('POST', `/api/admin/asambleas/${a.datos.asamblea.id}/abrir`, { token: tokenAdmin });
  const v1 = await pedir('POST', '/api/acceso', { cuerpo: { numero: '1', tipo: 'propietario' } });
  const v2 = await pedir('POST', '/api/acceso', { cuerpo: { numero: '2', tipo: 'apoderado', apoderado_nombre: 'Laura Gómez', apoderado_cedula: '52998877' } });
  tokenVotante1 = v1.datos.token;
  tokenVotante2 = v2.datos.token;

  const repetidas = await pedir('POST', '/api/gestion/preguntas', { token: tokenLogistica, cuerpo: { texto: '¿Algo?', opciones: ['Sí', 'sí'] } });
  assert.equal(repetidas.estado, 400);
  const creada = await pedir('POST', '/api/gestion/preguntas', {
    token: tokenLogistica, cuerpo: { texto: '¿Aprueba el presupuesto 2027?' },
  });
  assert.equal(creada.estado, 200, JSON.stringify(creada.datos));
  assert.deepEqual(creada.datos.pregunta.opciones, ['Sí', 'No', 'Abstención']);
  assert.equal(creada.datos.pregunta.numero, 1);
  preguntaId = creada.datos.pregunta.id;

  const antes = await pedir('GET', '/api/votacion/actual', { token: tokenVotante1 });
  assert.equal(antes.datos.pregunta, null);

  const ws = new WebSocket(base.replace('http', 'ws') + '/ws');
  const eventos = [];
  await new Promise((r) => { ws.onmessage = (m) => { eventos.push(JSON.parse(m.data)); r(); }; });
  const abierta = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/abrir`, { token: tokenLogistica });
  assert.equal(abierta.estado, 200);
  await new Promise((r) => setTimeout(r, 200));
  ws.close();
  assert.ok(eventos.some((e) => e.evento === 'votacion' && e.abierta === true));

  const ahora = await pedir('GET', '/api/votacion/actual', { token: tokenVotante1 });
  assert.equal(ahora.datos.pregunta.texto, '¿Aprueba el presupuesto 2027?');
  assert.equal(ahora.datos.puede_votar, true);
  assert.equal(ahora.datos.local_numero, '1');
  assert.ok(ahora.datos.coeficiente > 0);
  assert.equal(ahora.datos.pregunta.resultados, undefined); // el asistente no ve resultados en vivo

  // Solo una pregunta abierta a la vez
  const otra = await pedir('POST', '/api/gestion/preguntas', { token: tokenLogistica, cuerpo: { texto: '¿Otra?', abrir: true } });
  assert.equal(otra.estado, 409);
});

test('cada local vota una vez con su coeficiente', async () => {
  const sinAsistencia = await pedir('POST', '/api/acceso', { cuerpo: { numero: '30', tipo: 'propietario' } });
  // Entró con asamblea abierta, así que quedó registrado y puede votar.
  assert.equal(sinAsistencia.datos.asistencia_nueva, true);

  const mala = await pedir('POST', '/api/votacion/votar', { token: tokenVotante1, cuerpo: { pregunta_id: preguntaId, opcion: 7 } });
  assert.equal(mala.estado, 400);
  const v1 = await pedir('POST', '/api/votacion/votar', { token: tokenVotante1, cuerpo: { pregunta_id: preguntaId, opcion: 0 } });
  assert.equal(v1.estado, 200);
  assert.equal(v1.datos.texto, 'Sí');
  const dos = await pedir('POST', '/api/votacion/votar', { token: tokenVotante1, cuerpo: { pregunta_id: preguntaId, opcion: 1 } });
  assert.equal(dos.estado, 409);
  const v2 = await pedir('POST', '/api/votacion/votar', { token: tokenVotante2, cuerpo: { pregunta_id: preguntaId, opcion: 1 } });
  assert.equal(v2.estado, 200);
  const yo = await pedir('GET', '/api/votacion/actual', { token: tokenVotante1 });
  assert.equal(yo.datos.puede_votar, false);
  assert.equal(yo.datos.mi_voto.opcion, 0);
  // La administradora no vota desde la app de asistente
  assert.equal((await pedir('POST', '/api/votacion/votar', { token: tokenAdmin, cuerpo: { pregunta_id: preguntaId, opcion: 0 } })).estado, 403);
});

test('voto manual de logística y resultados por coeficiente', async () => {
  const sinAsistencia = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/votos`, {
    token: tokenLogistica, cuerpo: { numero: '40', opcion: 0 },
  });
  assert.equal(sinAsistencia.estado, 409);
  assert.match(sinAsistencia.datos.error, /no ha registrado asistencia/);
  const manual = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/votos`, {
    token: tokenLogistica, cuerpo: { numero: '30', opcion: 0 },
  });
  assert.equal(manual.estado, 200);
  const dup = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/votos`, { token: tokenLogistica, cuerpo: { numero: '30', opcion: 2 } });
  assert.equal(dup.estado, 409);
  const corregido = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/votos`, {
    token: tokenLogistica, cuerpo: { numero: '30', opcion: 2, reemplazar: true },
  });
  assert.equal(corregido.estado, 200);

  const coef = {};
  for (const n of ['1', '2', '30']) {
    const l = await pedir('GET', `/api/locales/${n}`, { token: tokenAdmin });
    coef[n] = l.datos.local.coeficiente;
  }
  const lista = await pedir('GET', '/api/gestion/preguntas', { token: tokenLogistica });
  assert.equal(lista.datos.preguntas.length, 1);
  const r = lista.datos.preguntas.find((p) => p.id === preguntaId).resultados;
  assert.equal(r.votaron_locales, 3);
  assert.equal(r.presentes_locales, 3);
  assert.equal(r.faltan_locales, 0);
  assert.equal(r.opciones[0].votos, 1);
  assert.equal(r.opciones[0].coeficiente, coef['1']);
  assert.equal(r.opciones[1].coeficiente, coef['2']);
  assert.equal(r.opciones[2].coeficiente, coef['30']);
  const presentes = coef['1'] + coef['2'] + coef['30'];
  assert.equal(r.opciones[0].porcentaje_presentes, Number(((coef['1'] / presentes) * 100).toFixed(2)));
  assert.equal(r.opciones[0].porcentaje_total, Number(coef['1'].toFixed(2)));

  const votos = await pedir('GET', `/api/gestion/preguntas/${preguntaId}/votos`, { token: tokenLogistica });
  assert.equal(votos.datos.votos.length, 3);
  const v30 = votos.datos.votos.find((v) => v.numero === '30');
  assert.equal(v30.opcion_texto, 'Abstención');
  assert.equal(v30.registrado_por, 'logistica');
  // Quitar un voto (corrección)
  const borrar = await pedir('DELETE', `/api/gestion/votos/${v30.id}`, { token: tokenLogistica });
  assert.equal(borrar.estado, 200);
  const despues = await pedir('GET', `/api/gestion/preguntas/${preguntaId}/votos`, { token: tokenLogistica });
  assert.equal(despues.datos.pregunta.resultados.faltan_locales, 1);
});

test('cerrar la votación: los asistentes ven el resultado', async () => {
  assert.equal((await pedir('DELETE', `/api/gestion/preguntas/${preguntaId}`, { token: tokenLogistica })).estado, 409);
  const cerrada = await pedir('POST', `/api/gestion/preguntas/${preguntaId}/cerrar`, { token: tokenLogistica });
  assert.equal(cerrada.estado, 200);
  const tarde = await pedir('POST', '/api/votacion/votar', { token: tokenVotante2, cuerpo: { pregunta_id: preguntaId, opcion: 0 } });
  assert.equal(tarde.estado, 409);
  const vista = await pedir('GET', '/api/votacion/actual', { token: tokenVotante1 });
  assert.equal(vista.datos.pregunta, null);
  assert.equal(vista.datos.ultima.id, preguntaId);
  assert.ok(vista.datos.ultima.resultados.opciones.length === 3);
  assert.ok([0, 1, null].includes(vista.datos.ultima.resultados.ganadora));

  // Editar solo antes de abrir
  assert.equal((await pedir('PUT', `/api/gestion/preguntas/${preguntaId}`, { token: tokenLogistica, cuerpo: { texto: 'x?' } })).estado, 409);
  const nueva = await pedir('POST', '/api/gestion/preguntas', {
    token: tokenLogistica, cuerpo: { texto: '¿Quién será el revisor fiscal?', opciones: ['Ana Ruiz', 'Pedro Díaz', 'En blanco'] },
  });
  assert.equal(nueva.datos.pregunta.numero, 2);
  const editada = await pedir('PUT', `/api/gestion/preguntas/${nueva.datos.pregunta.id}`, {
    token: tokenLogistica, cuerpo: { texto: '¿Quién será el revisor fiscal 2027?', opciones: ['Ana Ruiz', 'Pedro Díaz'] },
  });
  assert.equal(editada.estado, 200);
  assert.deepEqual(editada.datos.pregunta.opciones, ['Ana Ruiz', 'Pedro Díaz']);
  assert.equal((await pedir('DELETE', `/api/gestion/preguntas/${nueva.datos.pregunta.id}`, { token: tokenLogistica })).estado, 200);
});

test('informes de votaciones: Excel y acta', async () => {
  const csv = await fetch(`${base}/api/gestion/informes/votaciones.csv?token=${tokenLogistica}`);
  assert.equal(csv.status, 200);
  const texto = await csv.text();
  assert.ok(texto.includes('Pregunta 1;¿Aprueba el presupuesto 2027?'));
  assert.ok(texto.includes('Opción;Votos (locales);Coeficiente'));
  const acta = await (await fetch(`${base}/api/admin/informes/acta?token=${tokenLogistica}`)).text();
  assert.ok(acta.includes('<h2>Votaciones</h2>'));
  assert.ok(acta.includes('Sandra Libey Martinez Real'));
  // Con votos, borrar la pregunta exige confirmación
  const sin = await pedir('DELETE', `/api/gestion/preguntas/${preguntaId}`, { token: tokenLogistica });
  assert.equal(sin.estado, 409);
  assert.match(sin.datos.error, /BORRAR/);
});

// ---------------- Modo sin internet ----------------

test('el servidor entrega la app web y sigue respondiendo la API', async () => {
  const inicio = await fetch(base + '/');
  assert.equal(inicio.status, 200);
  assert.match(inicio.headers.get('content-type'), /text\/html/);
  assert.match(await inicio.text(), /App de prueba/);
  const js = await fetch(base + '/main.dart.js');
  assert.match(js.headers.get('content-type'), /javascript/);
  const wasm = await fetch(base + '/canvaskit.wasm');
  assert.equal(wasm.headers.get('content-type'), 'application/wasm');
  const rutaApp = await fetch(base + '/consultar');
  assert.match(await rutaApp.text(), /App de prueba/);
  assert.equal((await fetch(base + '/no-existe.png')).status, 404);
  assert.equal((await fetch(base + '/%2e%2e/package.json')).status, 404);
  const salud = await pedir('GET', '/api/salud');
  assert.equal(salud.datos.ok, true);
});

test('respaldo: se descarga y se vuelve a cargar igual', async () => {
  const descarga = await fetch(`${base}/api/admin/respaldo?token=${tokenAdmin}`);
  assert.equal(descarga.status, 200);
  assert.match(descarga.headers.get('content-disposition'), /respaldo-asamblea-/);
  const respaldo = await descarga.json();
  assert.equal(respaldo.tablas.locales.length > 50, true);
  assert.equal(respaldo.tablas.preguntas.length, 1);
  const votosAntes = respaldo.tablas.votos.length;
  assert.ok(votosAntes >= 2);

  // Cambios después del respaldo
  await pedir('POST', '/api/admin/locales', { token: tokenAdmin, cuerpo: { numero: '99', coeficiente: 1, propietario_nombre: 'Temporal', propietario_cedula: '123456' } });
  assert.equal((await pedir('GET', '/api/publico/local/99')).estado, 200);

  assert.equal((await pedir('POST', '/api/admin/respaldo/importar', { token: tokenLogistica, cuerpo: { respaldo, confirmacion: 'BORRAR' } })).estado, 403);
  assert.equal((await pedir('POST', '/api/admin/respaldo/importar', { token: tokenAdmin, cuerpo: { respaldo, confirmacion: 'no' } })).estado, 400);
  assert.equal((await pedir('POST', '/api/admin/respaldo/importar', { token: tokenAdmin, cuerpo: { respaldo: { x: 1 }, confirmacion: 'BORRAR' } })).estado, 400);
  const carga = await pedir('POST', '/api/admin/respaldo/importar', { token: tokenAdmin, cuerpo: { respaldo, confirmacion: 'BORRAR' } });
  assert.equal(carga.estado, 200, JSON.stringify(carga.datos));
  assert.equal(carga.datos.votos, votosAntes);
  assert.equal((await pedir('GET', '/api/publico/local/99')).estado, 404);

  // Todo sigue funcionando después de cargar el respaldo (los contadores de id quedaron bien).
  const nuevo = await pedir('POST', '/api/admin/locales', { token: tokenAdmin, cuerpo: { numero: '98', coeficiente: 1, propietario_nombre: 'Nuevo', propietario_cedula: '654321' } });
  assert.equal(nuevo.estado, 200, JSON.stringify(nuevo.datos));
  const lista = await pedir('GET', '/api/gestion/preguntas', { token: tokenLogistica });
  assert.equal(lista.datos.preguntas[0].texto, '¿Aprueba el presupuesto 2027?');
  assert.equal(lista.datos.preguntas[0].resultados.votaron_locales, votosAntes);
  const pagina = await fetch(`${base}/api/admin/respaldo/importar?token=${tokenAdmin}`);
  assert.match(await pagina.text(), /Cargar respaldo/);
});
