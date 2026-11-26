import 'dart:async';

import 'package:flutter/material.dart';

import '../modelos.dart';
import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../tema.dart';
import '../util.dart';
import '../widgets/comunes.dart';
import 'consulta_local.dart';
import 'salir.dart';
import 'votacion.dart';

/// Inicio del propietario o apoderado: "Mi asistencia" y "Locales".
class InicioAsistentePantalla extends StatefulWidget {
  const InicioAsistentePantalla({super.key});

  @override
  State<InicioAsistentePantalla> createState() => _InicioAsistentePantallaState();
}

class _InicioAsistentePantallaState extends State<InicioAsistentePantalla> {
  int _pestana = 0;
  StreamSubscription<String>? _suscripcion;
  int? _ultimaPreguntaAvisada;

  static const _titulos = ['Mi asistencia', 'Votación', 'Consultar local'];

  @override
  void initState() {
    super.initState();
    TiempoReal.i.iniciar();
    _suscripcion = TiempoReal.i.eventos.listen((evento) {
      if (evento == 'votacion' || evento == 'conectado') _revisarVotacion();
    });
    _revisarVotacion();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  /// Si logística abrió una pregunta nueva y este local no ha votado, se muestra la pestaña Votación.
  Future<void> _revisarVotacion() async {
    try {
      final r = await Api.i.get('/api/votacion/actual');
      final actual = VotacionActual.desde(r);
      final p = actual.pregunta;
      if (!mounted || p == null || actual.miVoto != null || p.id == _ultimaPreguntaAvisada) return;
      _ultimaPreguntaAvisada = p.id;
      setState(() => _pestana = 1);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('¡Nueva votación! Pregunta ${p.numero}: ${p.texto}'),
          duration: const Duration(seconds: 5),
        ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_pestana]),
        actions: [
          const BotonTema(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => cerrarSesion(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _pestana,
        children: const [
          MiAsistenciaPestana(),
          VotacionPestana(),
          ConsultaLocalPestana(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Mi asistencia'),
          NavigationDestination(icon: Icon(Icons.how_to_vote_outlined), selectedIcon: Icon(Icons.how_to_vote), label: 'Votación'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Locales'),
        ],
      ),
    );
  }
}

class MiAsistenciaPestana extends StatefulWidget {
  const MiAsistenciaPestana({super.key});

  @override
  State<MiAsistenciaPestana> createState() => _MiAsistenciaPestanaState();
}

class _MiAsistenciaPestanaState extends State<MiAsistenciaPestana> with RefrescoEnVivo<MiAsistenciaPestana> {
  Map<String, dynamic>? _sesion;
  Quorum? _quorum;
  String? _error;
  bool _registrando = false;

  @override
  void initState() {
    super.initState();
    TiempoReal.i.iniciar();
    escucharEnVivo();
    _cargar();
  }

  @override
  void alCambiar() => _cargar();

  Future<void> _cargar() async {
    try {
      final respuestas = await Future.wait([Api.i.get('/api/sesion'), Api.i.get('/api/quorum')]);
      if (!mounted) return;
      setState(() {
        _sesion = respuestas[0];
        _quorum = Quorum.desde(respuestas[1]);
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _registrar() async {
    setState(() => _registrando = true);
    try {
      final r = await Api.i.post('/api/mi-asistencia');
      if (!mounted) return;
      mostrarMensaje(
        context,
        r['asistencia_nueva'] == true ? '¡Listo! Tu asistencia quedó registrada.' : 'Este local ya tenía la asistencia registrada.',
      );
      await _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sesion == null && _error != null) {
      return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    }
    if (_sesion == null) return const Cargando();

    final local = Local.desde(Map<String, dynamic>.from(_sesion!['local'] as Map));
    final asamblea = Asamblea.desde(_sesion!['asamblea']);
    final rol = _sesion!['rol'] == 'apoderado' ? 'Apoderado' : 'Propietario';
    final a = local.asistencia;
    final colores = Theme.of(context).colorScheme;

    Widget estado;
    if (asamblea == null) {
      estado = const Aviso(
        icono: Icons.hourglass_empty,
        color: ambar,
        texto: 'Todavía no hay una asamblea abierta',
        detalle: 'Cuando la administradora la abra, aquí aparecerá el botón para registrar tu asistencia.',
      );
    } else if (a != null) {
      estado = Aviso(
        icono: Icons.check_circle,
        color: verdeOk,
        texto: 'Asistencia registrada a las ${a.hora}',
        detalle: '${a.tipoTexto}: ${a.nombre} (C.C. ${a.cedula})\n${asamblea.nombre}',
      );
    } else {
      estado = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Aviso(
            icono: Icons.event_available,
            color: ambar,
            texto: 'La asamblea está abierta',
            detalle: '${asamblea.nombre}. Toca el botón para registrar tu asistencia.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _registrando ? null : _registrar,
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Registrar mi asistencia'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenedor(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radios.tarjeta),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colores.verde, Colores.lima],
                    ),
                  ),
                  child: Row(
                    children: [
                      const LogoTrebolis(ancho: 84),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, ${_sesion!['nombre'] ?? ''}',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$rol · Local ${local.numero}\nCoeficiente ${decimal(local.coeficiente)} %',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                estado,
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                ],
                const SizedBox(height: 12),
                if (_quorum != null) TarjetaQuorum(quorum: _quorum!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
