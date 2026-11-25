import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// Escucha los avisos del servidor (alguien registró asistencia, se abrió la asamblea...).
class TiempoReal {
  TiempoReal._();
  static final TiempoReal i = TiempoReal._();

  final StreamController<String> _eventos = StreamController<String>.broadcast();
  Stream<String> get eventos => _eventos.stream;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _suscripcion;
  Timer? _reintento;
  bool _activo = false;

  void iniciar() {
    if (_activo) return;
    _activo = true;
    _conectar();
  }

  void detener() {
    _activo = false;
    _reintento?.cancel();
    _suscripcion?.cancel();
    _suscripcion = null;
    _canal?.sink.close();
    _canal = null;
  }

  Future<void> _conectar() async {
    if (!_activo) return;
    try {
      final base = Uri.parse(Api.i.baseUrl);
      final direccion = Uri(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/ws',
      );
      final canal = WebSocketChannel.connect(direccion);
      _canal = canal;
      await canal.ready;
      _suscripcion = canal.stream.listen(
        (mensaje) {
          try {
            final datos = jsonDecode(mensaje as String);
            final evento = datos is Map ? datos['evento'] : null;
            if (evento is String) _eventos.add(evento);
          } catch (_) {}
        },
        onDone: _programarReintento,
        onError: (_) => _programarReintento(),
        cancelOnError: true,
      );
    } catch (_) {
      _programarReintento();
    }
  }

  void _programarReintento() {
    _suscripcion?.cancel();
    _suscripcion = null;
    _canal = null;
    if (!_activo) return;
    _reintento?.cancel();
    _reintento = Timer(const Duration(seconds: 5), _conectar);
  }
}

/// Para pantallas que se actualizan solas cuando llega un aviso.
mixin RefrescoEnVivo<T extends StatefulWidget> on State<T> {
  StreamSubscription<String>? _suscripcionEnVivo;
  Timer? _espera;

  /// Qué hacer cuando llega un aviso (normalmente volver a cargar los datos).
  void alCambiar();

  Set<String> get eventosQueEscucha => const {'asistencia', 'asamblea', 'locales', 'conectado'};

  void escucharEnVivo() {
    _suscripcionEnVivo = TiempoReal.i.eventos.listen((evento) {
      if (!eventosQueEscucha.contains(evento)) return;
      _espera?.cancel();
      // Espera un momento para no recargar 50 veces si entran muchos al tiempo.
      _espera = Timer(const Duration(milliseconds: 800), () {
        if (mounted) alCambiar();
      });
    });
  }

  @override
  void dispose() {
    _suscripcionEnVivo?.cancel();
    _espera?.cancel();
    super.dispose();
  }
}
