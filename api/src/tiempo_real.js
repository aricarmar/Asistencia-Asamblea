'use strict';
// Avisos en tiempo real: cuando alguien registra asistencia, todas las pantallas actualizan el quórum.
const { WebSocketServer } = require('ws');

let wss = null;

function iniciar(servidor) {
  wss = new WebSocketServer({ server: servidor, path: '/ws' });
  wss.on('connection', (socket) => {
    socket.esta_vivo = true;
    socket.on('pong', () => { socket.esta_vivo = true; });
    socket.send(JSON.stringify({ evento: 'conectado' }));
  });
  // Mantiene viva la conexión (Render corta las conexiones inactivas).
  const intervalo = setInterval(() => {
    wss.clients.forEach((s) => {
      if (!s.esta_vivo) return s.terminate();
      s.esta_vivo = false;
      s.ping();
    });
  }, 30000);
  wss.on('close', () => clearInterval(intervalo));
}

function avisar(evento, datos = {}) {
  if (!wss) return;
  const mensaje = JSON.stringify({ evento, ...datos });
  wss.clients.forEach((s) => {
    if (s.readyState === 1) s.send(mensaje);
  });
}

function cerrar() {
  if (wss) wss.close();
}

module.exports = { iniciar, avisar, cerrar };
