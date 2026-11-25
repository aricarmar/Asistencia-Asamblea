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
  await bd.pool.query('DROP TABLE IF EXISTS asistencias, asambleas, locales, administradores CASCADE');
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

test('datos de ejemplo: 30 locales que suman 100 de coeficiente', async () => {
  const r = await pedir('POST', '/api/admin/locales/ejemplo', { token: tokenAdmin });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.creados, 30);
  const otra = await pedir('POST', '/api/admin/locales/ejemplo', { token: tokenAdmin });
  assert.equal(otra.estado, 409);
  const q = await pedir('GET', '/api/quorum', { token: tokenAdmin });
  assert.equal(q.datos.total_locales, 30);
  assert.equal(q.datos.coeficiente_total, 100);
  assert.equal(q.datos.asamblea, null);
});

test('importar locales pegados desde Excel', async () => {
  const texto = [
    'Local\tCoeficiente\tPropietario\tCédula\tApoderado\tCédula apoderado',
    'L-1\t1,25\tRosa Elena Prieto\t52.123.456\t\t',
    'l-2\t0,75\tTomás Quintero\t79123456\tLaura Quintero\t1020304050',
    '101\t3,5\tNuevo dueño del 101\t11223344',
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
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: '101', tipo: 'propietario' } });
  assert.equal(r.estado, 200);
  assert.equal(r.datos.rol, 'propietario');
  assert.equal(r.datos.asamblea, null);
  assert.equal(r.datos.asistencia_nueva, false);
  assert.equal(r.datos.local.asistencia, null);
  tokenPropietario101 = r.datos.token;
  const s = await pedir('GET', '/api/sesion', { token: tokenPropietario101 });
  assert.equal(s.datos.local.numero, '101');
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
  assert.equal(q.datos.coeficiente_presente, 4.75); // 101 (3,5) + L-1 (1,25)
  assert.ok(q.datos.coeficiente_total > 100);
  assert.equal(q.datos.porcentaje, Number(((4.75 / q.datos.coeficiente_total) * 100).toFixed(2)));
  assert.equal(q.datos.hay_quorum, false);
});

test('el apoderado se registra solo con nombre y cédula', async () => {
  const sinDatos = await pedir('POST', '/api/acceso', { cuerpo: { numero: '102', tipo: 'apoderado' } });
  assert.equal(sinDatos.estado, 400);
  const r = await pedir('POST', '/api/acceso', {
    cuerpo: { numero: '102', tipo: 'apoderado', apoderado_nombre: '  Julián   Pérez ', apoderado_cedula: '1.098.765.432' },
  });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.equal(r.datos.rol, 'apoderado');
  assert.equal(r.datos.local.asistencia.tipo, 'apoderado');
  assert.equal(r.datos.local.asistencia.nombre, 'Julián Pérez');
  const admin = await pedir('GET', '/api/locales/102', { token: tokenAdmin });
  assert.equal(admin.datos.local.apoderado.cedula, '1098765432');
  assert.equal(admin.datos.local.apoderado.registrado_por, 'apoderado');
  assert.equal(admin.datos.local.asistencia.cedula, '1098765432');
  // El propietario de otro local ve la cédula oculta.
  const visto = await pedir('GET', '/api/locales/102', { token: tokenPropietario101 });
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
  const r = await pedir('POST', '/api/admin/asistencias', { token: tokenAdmin, cuerpo: { numero: '103', tipo: 'propietario' } });
  assert.equal(r.estado, 200);
  const dup = await pedir('POST', '/api/admin/asistencias', { token: tokenAdmin, cuerpo: { numero: '103', tipo: 'propietario' } });
  assert.equal(dup.estado, 409);
  assert.match(dup.datos.error, /ya está registrado/);
  const corregir = await pedir('POST', '/api/admin/asistencias', {
    token: tokenAdmin, cuerpo: { numero: '103', tipo: 'apoderado', nombre: 'Marta Gil', cedula: '43111222', reemplazar: true },
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
  assert.equal(todo.datos.locales.length, 32);
  assert.deepEqual(todo.datos.locales.slice(0, 3).map((l) => l.numero), ['L-1', 'L-2', '101']);
  const l101 = todo.datos.locales.find((l) => l.numero === '101');
  assert.equal(l101.coeficiente, 3.5);
  assert.equal(l101.asistencia.tipo, 'propietario');
  const l104 = todo.datos.locales.find((l) => l.numero === '104');
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
  assert.ok(texto.includes('L-1;1,25;Rosa Elena Prieto;52123456;Sí;Propietario'));
  const acta = await fetch(`${base}/api/admin/informes/acta?token=${tokenAdmin}`);
  const html = await acta.text();
  assert.ok(html.includes('Acta de asistencia – Asamblea ordinaria 2026'));
  assert.ok(html.includes('Julián Pérez'));
  const sinPermiso = await fetch(`${base}/api/admin/informes/acta?token=${tokenPropietario101}`);
  assert.equal(sinPermiso.status, 403);
});

test('editar y desactivar locales', async () => {
  const l = await pedir('GET', '/api/locales/104', { token: tokenAdmin });
  const id = l.datos.local.id;
  const e = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin,
    cuerpo: { numero: '104', coeficiente: '2,5', propietario_nombre: 'Dueña Nueva', propietario_cedula: '1.234.567', apoderado_nombre: '', apoderado_cedula: '' },
  });
  assert.equal(e.estado, 200, JSON.stringify(e.datos));
  assert.equal(e.datos.local.coeficiente, 2.5);
  assert.equal(e.datos.local.apoderado, null);
  const mitad = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin, cuerpo: { numero: '104', coeficiente: '2', propietario_nombre: 'X', propietario_cedula: '1', apoderado_nombre: 'Solo nombre' },
  });
  assert.equal(mitad.estado, 400);
  const choque = await pedir('PUT', `/api/admin/locales/${id}`, {
    token: tokenAdmin, cuerpo: { numero: '105', coeficiente: '2', propietario_nombre: 'X', propietario_cedula: '1' },
  });
  assert.equal(choque.estado, 409);
  assert.equal((await pedir('DELETE', `/api/admin/locales/${id}`, { token: tokenAdmin })).estado, 200);
  assert.equal((await pedir('GET', '/api/publico/local/104')).estado, 404);
  const crear = await pedir('POST', '/api/admin/locales', {
    token: tokenAdmin, cuerpo: { numero: '104', coeficiente: 1, propietario_nombre: 'Vuelve', propietario_cedula: '555666' },
  });
  assert.equal(crear.estado, 200);
  assert.equal(crear.datos.local.id, id);
  const yaExiste = await pedir('POST', '/api/admin/locales', {
    token: tokenAdmin, cuerpo: { numero: '104', coeficiente: 1, propietario_nombre: 'Vuelve', propietario_cedula: '555666' },
  });
  assert.equal(yaExiste.estado, 409);
});

test('cerrar la asamblea: quien entra después no queda registrado', async () => {
  assert.equal((await pedir('POST', `/api/admin/asambleas/${asambleaId}/cerrar`, { token: tokenAdmin })).estado, 200);
  const r = await pedir('POST', '/api/acceso', { cuerpo: { numero: '110', tipo: 'propietario' } });
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
