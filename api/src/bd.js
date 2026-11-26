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

// En el computador (modo sin internet) crea la base de datos si todavía no existe.
async function crearBaseSiFalta() {
  try {
    await pool.query('SELECT 1');
  } catch (err) {
    if (err.code !== '3D000' || !esLocal) throw err;
    const u = new URL(url);
    const nombre = decodeURIComponent(u.pathname.slice(1));
    if (!/^[A-Za-z0-9_]+$/.test(nombre)) throw err;
    u.pathname = '/postgres';
    const { Client } = require('pg');
    const cliente = new Client({ connectionString: u.toString(), ssl: false });
    await cliente.connect();
    await cliente.query(`CREATE DATABASE ${nombre}`);
    await cliente.end();
    console.log(`Base de datos "${nombre}" creada en este computador.`);
  }
}

// Crea las tablas y la cuenta de la administradora si no existen.
async function preparar() {
  await crearBaseSiFalta();
  const esquema = fs.readFileSync(path.join(__dirname, 'esquema.sql'), 'utf8');
  await pool.query(esquema);

  const usuario = (process.env.ADMIN_USUARIO || 'admin').trim().toLowerCase();
  const nombre = (process.env.ADMIN_NOMBRE || 'Sandra Libey Martinez Real').trim();
  const { rows } = await pool.query("SELECT COUNT(*)::int AS total FROM administradores WHERE rol = 'administradora'");
  if (rows[0].total === 0) {
    const clave = process.env.ADMIN_CLAVE || 'admin123';
    await pool.query(
      "INSERT INTO administradores (usuario, nombre, clave_hash, rol) VALUES ($1, $2, $3, 'administradora')",
      [usuario, nombre, cifrarClave(clave)]
    );
    console.log(`Cuenta de administradora creada: usuario "${usuario}".`);
  } else {
    // Mantiene el nombre de la administradora al día con ADMIN_NOMBRE.
    await pool.query(
      "UPDATE administradores SET nombre = $2 WHERE usuario = $1 AND rol = 'administradora' AND nombre <> $2",
      [usuario, nombre]
    );
  }
}

module.exports = { pool, consulta, transaccion, preparar };
