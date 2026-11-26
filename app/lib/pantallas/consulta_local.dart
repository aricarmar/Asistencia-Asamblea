import 'package:flutter/material.dart';

import '../modelos.dart';
import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../util.dart';
import '../widgets/comunes.dart';
import 'admin/formulario_local.dart';
import 'admin/registrar_asistencia.dart';

/// Pestaña "Locales": se digita el número y aparece el local con su coeficiente,
/// el propietario con cédula o su apoderado con cédula.
class ConsultaLocalPestana extends StatefulWidget {
  const ConsultaLocalPestana({super.key});

  @override
  State<ConsultaLocalPestana> createState() => _ConsultaLocalPestanaState();
}

class _ConsultaLocalPestanaState extends State<ConsultaLocalPestana> with RefrescoEnVivo<ConsultaLocalPestana> {
  final _numero = TextEditingController();
  Local? _local;
  Asamblea? _asamblea;
  String? _error;
  bool _buscando = false;

  bool get _esAdmin => Api.i.esAdmin;
  bool get _esGestion => Api.i.esGestion;

  @override
  void initState() {
    super.initState();
    escucharEnVivo();
  }

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  @override
  void alCambiar() {
    if (_local != null) _buscar(silencioso: true);
  }

  Future<void> _buscar({bool silencioso = false}) async {
    final numero = _numero.text.trim();
    if (numero.isEmpty) {
      setState(() => _error = 'Escribe el número del local.');
      return;
    }
    if (!silencioso) {
      setState(() {
        _buscando = true;
        _error = null;
      });
    }
    try {
      final r = await Api.i.get('/api/locales/${Uri.encodeComponent(numero)}');
      if (!mounted) return;
      setState(() {
        _local = Local.desde(Map<String, dynamic>.from(r['local'] as Map));
        _asamblea = Asamblea.desde(r['asamblea']);
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        if (!silencioso) _local = null;
      });
    } finally {
      if (mounted && !silencioso) setState(() => _buscando = false);
    }
  }

  Future<void> _registrar(Local local) async {
    final ok = await mostrarRegistrarAsistencia(context, numero: local.numero);
    if (ok) _buscar(silencioso: true);
  }

  Future<void> _editar(Local local) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FormularioLocalPantalla(local: local)),
    );
    if (ok == true) {
      if (!mounted) return;
      _buscar(silencioso: true);
    }
  }

  Future<void> _quitarAsistencia(Local local) async {
    final a = local.asistencia;
    if (a == null) return;
    final ok = await confirmar(
      context,
      titulo: 'Quitar asistencia del local ${local.numero}',
      mensaje: '¿Quitar la asistencia de ${a.nombre} (${a.tipoTexto})? El quórum bajará. '
          'Si la persona vuelve a ingresar, queda registrada otra vez.',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/admin/asistencias/${a.id}');
      if (mounted) mostrarMensaje(context, 'Asistencia quitada.');
      _buscar(silencioso: true);
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _quitarApoderado(Local local) async {
    final apoderado = local.apoderado;
    if (apoderado == null) return;
    final ok = await confirmar(
      context,
      titulo: 'Quitar apoderado del local ${local.numero}',
      mensaje: '¿Quitar a ${apoderado.nombre} como apoderado? Si ya registró asistencia, esa asistencia se conserva '
          '(puedes quitarla aparte).',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/admin/locales/${local.id}/apoderado');
      if (mounted) mostrarMensaje(context, 'Apoderado quitado.');
      _buscar(silencioso: true);
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final local = _local;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Contenedor(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escribe el número de un local para ver su coeficiente, el propietario y su apoderado.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _numero,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'Número de local',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      onSubmitted: (_) {
                        if (!_buscando) _buscar();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _buscando ? null : () => _buscar(),
                      child: _buscando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null) Aviso(icono: Icons.error_outline, color: colores.error, texto: _error!),
              if (local != null) ...[
                if (_error != null) const SizedBox(height: 12),
                TarjetaLocal(
                  local: local,
                  mostrarAsistencia: _asamblea != null,
                  acciones: _esGestion
                      ? [
                          if (_asamblea != null && _asamblea!.abierta && !local.presente)
                            FilledButton.icon(
                              onPressed: () => _registrar(local),
                              icon: const Icon(Icons.how_to_reg),
                              label: const Text('Registrar asistencia'),
                            ),
                          if (_esAdmin)
                            OutlinedButton.icon(
                              onPressed: () => _editar(local),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar local'),
                            ),
                          if (local.presente)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colores.error,
                                side: BorderSide(color: colores.error),
                              ),
                              onPressed: () => _quitarAsistencia(local),
                              icon: const Icon(Icons.person_remove_outlined),
                              label: const Text('Quitar asistencia'),
                            ),
                          if (_esAdmin && local.apoderado != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colores.error,
                                side: BorderSide(color: colores.error),
                              ),
                              onPressed: () => _quitarApoderado(local),
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text('Quitar apoderado'),
                            ),
                        ]
                      : const [],
                ),
                if (_asamblea != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Asamblea: ${_asamblea!.nombre} (${_asamblea!.estadoTexto})',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colores.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
