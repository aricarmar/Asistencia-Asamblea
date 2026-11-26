import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

/// Crear, abrir y cerrar asambleas.
class AsambleasPestana extends StatefulWidget {
  const AsambleasPestana({super.key});

  @override
  State<AsambleasPestana> createState() => _AsambleasPestanaState();
}

class _AsambleasPestanaState extends State<AsambleasPestana> with RefrescoEnVivo<AsambleasPestana> {
  List<Asamblea> _asambleas = [];
  bool _cargado = false;
  String? _error;

  @override
  Set<String> get eventosQueEscucha => const {'asamblea', 'asistencia', 'conectado'};

  @override
  void initState() {
    super.initState();
    escucharEnVivo();
    _cargar();
  }

  @override
  void alCambiar() => _cargar();

  Future<void> _cargar() async {
    try {
      final r = await Api.i.get('/api/admin/asambleas');
      if (!mounted) return;
      setState(() {
        _asambleas = (r['asambleas'] as List? ?? const []).map((e) => Asamblea.desde(e)).whereType<Asamblea>().toList();
        _cargado = true;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _accion(Future<void> Function() fn, String exito) async {
    try {
      await fn();
      if (mounted) mostrarMensaje(context, exito);
      await _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _nueva() async {
    final nombre = TextEditingController(text: 'Asamblea general ordinaria ${DateTime.now().year}');
    DateTime fecha = DateTime.now();
    final crear = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => AlertDialog(
          title: const Text('Nueva asamblea'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombre,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: const Text('Fecha'),
                  subtitle: Text('${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}'),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: contexto,
                      initialDate: fecha,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2035),
                    );
                    if (elegida != null) actualizar(() => fecha = elegida);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (crear != true) return;
    final f = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    await _accion(
      () => Api.i.post('/api/admin/asambleas', {'nombre': nombre.text.trim(), 'fecha': f}),
      'Asamblea creada. Ábrela cuando empiece el registro.',
    );
  }

  Future<void> _abrir(Asamblea a) async {
    final ok = await confirmar(
      context,
      titulo: 'Abrir asamblea',
      mensaje: 'Desde ahora, quien ingrese con su número de local queda registrado como asistente de «${a.nombre}».',
      accion: 'Abrir',
    );
    if (ok) await _accion(() => Api.i.post('/api/admin/asambleas/${a.id}/abrir'), 'Asamblea abierta.');
  }

  Future<void> _cerrar(Asamblea a) async {
    final ok = await confirmar(
      context,
      titulo: 'Cerrar asamblea',
      mensaje: 'Ya nadie más quedará registrado al ingresar. Puedes volver a abrirla si lo necesitas.',
      accion: 'Cerrar',
      peligrosa: true,
    );
    if (ok) await _accion(() => Api.i.post('/api/admin/asambleas/${a.id}/cerrar'), 'Asamblea cerrada.');
  }

  Future<void> _borrar(Asamblea a) async {
    if (a.asistentes == 0) {
      final ok = await confirmar(
        context,
        titulo: 'Borrar asamblea',
        mensaje: '¿Borrar «${a.nombre}»?',
        accion: 'Borrar',
        peligrosa: true,
      );
      if (ok) await _accion(() => Api.i.delete('/api/admin/asambleas/${a.id}'), 'Asamblea borrada.');
      return;
    }
    final ok = await confirmarEscribiendo(
      context,
      titulo: 'Borrar «${a.nombre}»',
      mensaje: 'Esta asamblea tiene ${a.asistentes} asistentes registrados. Al borrarla se pierde su lista de asistencia '
          'y ya no podrás descargar su acta ni su Excel. Úsalo solo para asambleas de prueba.',
    );
    if (ok) await _accion(() => Api.i.delete('/api/admin/asambleas/${a.id}?forzar=si'), 'Asamblea borrada.');
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (!_cargado) return const Cargando();
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nueva,
        icon: const Icon(Icons.add),
        label: const Text('Nueva asamblea'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Contenedor(
              anchoMaximo: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                  if (_asambleas.isEmpty)
                    const MensajeEstado(
                      icono: Icons.event_outlined,
                      titulo: 'No hay asambleas',
                      detalle: 'Toca «Nueva asamblea» para crear la primera.',
                    ),
                  ..._asambleas.map((a) {
                    final color = a.abierta ? verdeOk : (a.cerrada ? colores.outline : ambar);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(a.nombre, style: Theme.of(context).textTheme.titleMedium),
                                ),
                                Chip(
                                  label: Text(a.estadoTexto),
                                  side: BorderSide(color: color),
                                  avatar: Icon(Icons.circle, size: 12, color: color),
                                ),
                              ],
                            ),
                            Text(
                              '${fechaBonita(a.fecha)}'
                              '${a.horaApertura != null ? ' · Abierta a las ${a.horaApertura}' : ''}'
                              '${a.horaCierre != null ? ' · Cerrada a las ${a.horaCierre}' : ''}'
                              ' · ${a.asistentes} asistentes',
                              style: TextStyle(color: colores.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!a.abierta)
                                  FilledButton.icon(
                                    onPressed: () => _abrir(a),
                                    icon: const Icon(Icons.play_arrow),
                                    label: Text(a.cerrada ? 'Volver a abrir' : 'Abrir'),
                                  ),
                                if (a.abierta)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: colores.error),
                                    onPressed: () => _cerrar(a),
                                    icon: const Icon(Icons.stop),
                                    label: const Text('Cerrar'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => abrirEnlace(
                                    context,
                                    Api.i.informe('/api/admin/informes/acta', asambleaId: a.id),
                                  ),
                                  icon: const Icon(Icons.print_outlined),
                                  label: const Text('Acta'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => abrirEnlace(
                                    context,
                                    Api.i.informe('/api/admin/informes/asistencia.csv', asambleaId: a.id),
                                  ),
                                  icon: const Icon(Icons.table_view_outlined),
                                  label: const Text('Excel'),
                                ),
                                if (!a.abierta)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: colores.error),
                                    onPressed: () => _borrar(a),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Borrar'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
