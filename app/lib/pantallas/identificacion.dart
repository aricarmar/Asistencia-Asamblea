import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../modelos.dart';
import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import 'inicio_asistente.dart';

/// Segundo paso: ¿asiste el propietario o un apoderado?
class IdentificacionPantalla extends StatefulWidget {
  final Map<String, dynamic> datos;
  const IdentificacionPantalla({super.key, required this.datos});

  @override
  State<IdentificacionPantalla> createState() => _IdentificacionPantallaState();
}

class _IdentificacionPantallaState extends State<IdentificacionPantalla> {
  late final Local _local;
  late final Asamblea? _asamblea;
  String _tipo = 'propietario';
  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _cedula = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _local = Local.desde(Map<String, dynamic>.from(widget.datos['local'] as Map));
    _asamblea = Asamblea.desde(widget.datos['asamblea']);
  }

  @override
  void dispose() {
    _nombres.dispose();
    _apellidos.dispose();
    _cedula.dispose();
    super.dispose();
  }

  String _limpio(TextEditingController c) => c.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _ingresar() async {
    final cuerpo = <String, dynamic>{'numero': _local.numero, 'tipo': _tipo};
    if (_tipo == 'apoderado') {
      final nombres = _limpio(_nombres);
      final apellidos = _limpio(_apellidos);
      final cedula = _cedula.text.trim();
      if (nombres.isEmpty) {
        setState(() => _error = 'Escribe los nombres del apoderado.');
        return;
      }
      if (apellidos.isEmpty) {
        setState(() => _error = 'Escribe los apellidos del apoderado.');
        return;
      }
      if (cedula.length < 5) {
        setState(() => _error = 'Escribe la cédula del apoderado (solo números).');
        return;
      }
      cuerpo['apoderado_nombre'] = '$nombres $apellidos';
      cuerpo['apoderado_cedula'] = cedula;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final respuesta = await Api.i.post('/api/acceso', cuerpo);
      await Api.i.guardarSesion(respuesta);
      TiempoReal.i.iniciar();
      if (!mounted) return;
      final nueva = respuesta['asistencia_nueva'] == true;
      final hayAsamblea = respuesta['asamblea'] != null;
      final mensaje = nueva
          ? '¡Listo! Tu asistencia quedó registrada.'
          : hayAsamblea
              ? 'Ingresaste. Este local ya tenía la asistencia registrada.'
              : 'Ingresaste. La asamblea todavía no está abierta.';
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioAsistentePantalla()),
        (_) => false,
      );
      mensajero.showSnackBar(SnackBar(content: Text(mensaje)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yaRegistrado = _local.asistencia;
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Local ${_local.numero}'),
        actions: const [BotonTema()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Contenedor(
            anchoMaximo: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TarjetaLocal(local: _local, mostrarAsistencia: false),
                const SizedBox(height: 12),
                if (_asamblea == null)
                  const Aviso(
                    icono: Icons.info_outline,
                    color: ambar,
                    texto: 'La asamblea todavía no está abierta',
                    detalle: 'Puedes ingresar ya. Cuando la abran, toca «Registrar mi asistencia».',
                  )
                else if (yaRegistrado != null)
                  Aviso(
                    icono: Icons.check_circle,
                    color: verdeOk,
                    texto: 'Este local ya registró asistencia a las ${yaRegistrado.hora}',
                    detalle: '${yaRegistrado.tipoTexto}: ${yaRegistrado.nombre}',
                  )
                else
                  Aviso(
                    icono: Icons.event_available,
                    color: verdeOk,
                    texto: 'Asamblea abierta: ${_asamblea!.nombre}',
                    detalle: 'Al ingresar queda registrada tu asistencia.',
                  ),
                const SizedBox(height: 20),
                Text('¿Cómo asistes?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                OpcionSeleccion(
                  icono: Icons.person,
                  titulo: 'Soy el propietario',
                  subtitulo: _local.propietario.nombre,
                  seleccionada: _tipo == 'propietario',
                  alTocar: () => setState(() {
                    _tipo = 'propietario';
                    _error = null;
                  }),
                ),
                OpcionSeleccion(
                  icono: Icons.badge_outlined,
                  titulo: 'Soy el apoderado',
                  subtitulo: 'Asisto en representación del propietario',
                  seleccionada: _tipo == 'apoderado',
                  alTocar: () => setState(() {
                    _tipo = 'apoderado';
                    _error = null;
                  }),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _tipo != 'apoderado'
                      ? const SizedBox(width: double.infinity)
                      : Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Datos del apoderado del local ${_local.numero}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Escríbelos como aparecen en tu cédula.',
                                  style: TextStyle(color: colores.onSurfaceVariant),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _nombres,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombres',
                                    hintText: 'Ej: Juan Carlos',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _apellidos,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Apellidos',
                                    hintText: 'Ej: Pérez Rodríguez',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _cedula,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(
                                    labelText: 'Número de cédula',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  onSubmitted: (_) {
                                    if (!_enviando) _ingresar();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Aviso(icono: Icons.error_outline, color: colores.error, texto: _error!),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _enviando ? null : _ingresar,
                  icon: _enviando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_asamblea != null && yaRegistrado == null ? 'Ingresar y registrar asistencia' : 'Ingresar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
