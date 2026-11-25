'use strict';
// Sesiones firmadas y claves cifradas usando solo el módulo crypto de Node.
const crypto = require('crypto');

const SECRETO = process.env.TOKEN_SECRETO || 'cambia-este-secreto-en-produccion';
const DURACION_HORAS = Number(process.env.SESION_HORAS || 24);

function b64(texto) {
  return Buffer.from(texto).toString('base64url');
}

function firmar(datos) {
  const cuerpo = b64(JSON.stringify({ ...datos, exp: Date.now() + DURACION_HORAS * 3600 * 1000 }));
  const firma = crypto.createHmac('sha256', SECRETO).update(cuerpo).digest('base64url');
  return `${cuerpo}.${firma}`;
}

function verificar(token) {
  if (!token || typeof token !== 'string' || !token.includes('.')) return null;
  const [cuerpo, firma] = token.split('.');
  const esperada = crypto.createHmac('sha256', SECRETO).update(cuerpo).digest('base64url');
  const a = Buffer.from(firma || '');
  const b = Buffer.from(esperada);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const datos = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
    if (!datos.exp || datos.exp < Date.now()) return null;
    return datos;
  } catch {
    return null;
  }
}

function cifrarClave(clave) {
  const sal = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(clave), sal, 64).toString('hex');
  return `scrypt$${sal}$${hash}`;
}

function compararClave(clave, guardada) {
  const [tipo, sal, hash] = String(guardada || '').split('$');
  if (tipo !== 'scrypt' || !sal || !hash) return false;
  const calculado = crypto.scryptSync(String(clave), sal, 64);
  const original = Buffer.from(hash, 'hex');
  return original.length === calculado.length && crypto.timingSafeEqual(original, calculado);
}

module.exports = { firmar, verificar, cifrarClave, compararClave };
