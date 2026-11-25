'use strict';
// Conexión a PostgreSQL (Neon en la nube o local en el PC).
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { cifrarClave } = require('./token');

const url = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/asistencia_asamblea';
const esLocal = /localhost|127\.0\.0\.1|host=\/|@\/|%2F/.test(url);

const pool = new Pool({
  connectionString: url,
  ssl: process.env.PGSSL === 'false' || esLocal ? false : { rejectUnauthorized: false },
  max: 10,
});

pool.on('error', (err) => console.error('Error en la conexión a la base de datos:', err.message));

function consulta(texto, parametros) {
  return pool.query(texto, parametros);
}

// Ejecuta varias consultas en una sola transacción.
async function transaccion(fn) {
  const cliente = await pool.connect();
  try {
    await cliente.query('BEGIN');
    const resultado = await fn(cliente);
    await cliente.query('COMMIT');
    return resultado;
  } catch (err) {
    await cliente.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    cliente.release();
  }
}

// Crea las tablas y la cuenta de la administradora si no existen.
async function preparar() {
  const esquema = fs.readFileSync(path.join(__dirname, 'esquema.sql'), 'utf8');
  await pool.query(esquema);

  const { rows } = await pool.query('SELECT COUNT(*)::int AS total FROM administradores');
  if (rows[0].total === 0) {
    const usuario = (process.env.ADMIN_USUARIO || 'admin').trim().toLowerCase();
    const clave = process.env.ADMIN_CLAVE || 'admin123';
    const nombre = process.env.ADMIN_NOMBRE || 'Administradora';
    await pool.query(
      'INSERT INTO administradores (usuario, nombre, clave_hash) VALUES ($1, $2, $3)',
      [usuario, nombre, cifrarClave(clave)]
    );
    console.log(`Cuenta de administradora creada: usuario "${usuario}".`);
  }
}

module.exports = { pool, consulta, transaccion, preparar };
