'use strict';

class ErrorApi extends Error {
  constructor(estado, mensaje) {
    super(mensaje);
    this.estado = estado;
  }
}

// "  l-101 " -> "L-101"
function normalizarNumero(numero) {
  return String(numero ?? '').trim().toUpperCase().replace(/\s+/g, ' ');
}

// Deja solo dígitos y letras (las cédulas de extranjería pueden tener letras).
function normalizarCedula(cedula) {
  return String(cedula ?? '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();
}

function normalizarNombre(nombre) {
  return String(nombre ?? '').trim().replace(/\s+/g, ' ');
}

// Oculta la cédula dejando ver solo los últimos 4 dígitos: 1023456789 -> ******6789
function ocultarCedula(cedula) {
  if (!cedula) return null;
  const c = String(cedula);
  if (c.length <= 4) return c;
  return '*'.repeat(c.length - 4) + c.slice(-4);
}

// Acepta "0,8523", "0.8523", "1.234,56" o "1,234.56".
function leerDecimal(valor) {
  if (typeof valor === 'number') return Number.isFinite(valor) ? valor : NaN;
  let t = String(valor ?? '').trim().replace(/\s|%/g, '');
  if (!t) return NaN;
  const coma = t.lastIndexOf(',');
  const punto = t.lastIndexOf('.');
  if (coma > -1 && punto > -1) {
    if (coma > punto) t = t.replace(/\./g, '').replace(',', '.');
    else t = t.replace(/,/g, '');
  } else if (coma > -1) {
    t = t.replace(',', '.');
  }
  return /^-?\d+(\.\d+)?$/.test(t) ? Number(t) : NaN;
}

// Convierte el texto pegado desde Excel (o un CSV) en filas.
// Columnas: número, coeficiente, propietario, cédula propietario, [apoderado], [cédula apoderado]
function leerTablaLocales(texto) {
  const lineas = String(texto || '').split(/\r?\n/).map((l) => l.trimEnd()).filter((l) => l.trim());
  const filas = [];
  const errores = [];
  lineas.forEach((linea, i) => {
    let separador = '\t';
    if (!linea.includes('\t')) separador = linea.includes(';') ? ';' : ',';
    const partes = linea.split(separador).map((p) => p.trim().replace(/^"|"$/g, ''));
    const [numero, coeficienteTexto, propNombre, propCedula, apoNombre, apoCedula] = partes;
    const coeficiente = leerDecimal(coeficienteTexto);
    if (Number.isNaN(coeficiente)) {
      // Probablemente es la fila de títulos; solo se reporta si no es la primera.
      if (i > 0) errores.push(`Línea ${i + 1}: el coeficiente "${coeficienteTexto ?? ''}" no es un número.`);
      return;
    }
    if (!normalizarNumero(numero) || !normalizarNombre(propNombre) || !normalizarCedula(propCedula)) {
      errores.push(`Línea ${i + 1}: faltan el número de local, el propietario o su cédula.`);
      return;
    }
    filas.push({
      numero: normalizarNumero(numero),
      coeficiente,
      propietario_nombre: normalizarNombre(propNombre),
      propietario_cedula: normalizarCedula(propCedula),
      apoderado_nombre: normalizarNombre(apoNombre) || null,
      apoderado_cedula: normalizarCedula(apoCedula) || null,
    });
  });
  return { filas, errores };
}

function csvCampo(valor) {
  const t = valor === null || valor === undefined ? '' : String(valor);
  return /[";\n\r]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
}

function escaparHtml(valor) {
  return String(valor ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// "2026-11-28" -> "28/11/2026"
function fechaColombia(fecha) {
  const p = String(fecha || '').split('-');
  return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : String(fecha || '');
}

module.exports = {
  fechaColombia,
  ErrorApi,
  normalizarNumero,
  normalizarCedula,
  normalizarNombre,
  ocultarCedula,
  leerDecimal,
  leerTablaLocales,
  csvCampo,
  escaparHtml,
};
