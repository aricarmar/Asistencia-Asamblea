import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';
import 'registrar_asistencia.dart';

/// Lista de asistentes de la asamblea, con registro manual y descargas.
class AsistenciaPestana extends StatefulWidget {
  const AsistenciaPestana({super.key});

  @override
  State<AsistenciaPestana> createState() => _AsistenciaPestanaState();
}

class _AsistenciaPestanaState extends State<AsistenciaPestana> with RefrescoEnVivo<AsistenciaPestana> {
  Asamblea? _asamblea;
  List<Asistencia> _lista = [];
  String _filtro = '';
  bool _cargado = false;
  String? _error;

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
      final r = await Api.i.get('/api/admin/asistencias');
      if (!mounted) return;
      setState(() {
        _asamblea = Asamblea.desde(r['asamblea']);
        _lista = (r['asistencias'] as List? ?? const []).map((e) => Asistencia.desde(e)).whereType<Asistencia>().toList();
        _cargado = true;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _registrar() async {
    final ok = await mostrarRegistrarAsistencia(context);
    if (ok) _cargar();
  }

  Future<void> _borrar(Asistencia a) async {
    final ok = await confirmar(
      context,
      titulo: 'Quitar asistencia',
      mensaje: '¿Quitar la asistencia del local ${a.numero} (${a.nombre})? El quórum bajará.',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/admin/asistencias/${a.id}');
      if (mounted) mostrarMensaje(context, 'Asistencia quitada.');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (!_cargado) return const Cargando();
    final asamblea = _asamblea;
    if (asamblea == null) {
      return const MensajeEstado(
        icono: Icons.event_outlined,
        titulo: 'Todavía no hay asambleas',
        detalle: 'Crea una en la pestaña Asambleas.',
      );
    }
    final colores = Theme.of(context).colorScheme;
    final f = _filtro.toLowerCase();
    final visibles = f.isEmpty
        ? _lista
        : _lista
            .where((a) =>
                (a.numero ?? '').toLowerCase().contains(f) ||
                a.nombre.toLowerCase().contains(f) ||
                a.cedula.contains(f))
            .toList();
    final coeficiente = _lista.fold<double>(0, (s, a) => s + a.coeficiente);

    return Scaffold(
      floatingActionButton: asamblea.abierta
          ? FloatingActionButton.extended(
              onPressed: _registrar,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Registrar'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Contenedor(
              anchoMaximo: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(asamblea.nombre, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '${fechaBonita(asamblea.fecha)} · ${asamblea.estadoTexto} · '
                    '${_lista.length} locales · ${decimal(coeficiente)} % del coeficiente',
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => abrirEnlace(
                          context,
                          Api.i.informe('/api/admin/informes/asistencia.csv', asambleaId: asamblea.id),
                        ),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Descargar Excel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => abrirEnlace(
                          context,
                          Api.i.informe('/api/admin/informes/acta', asambleaId: asamblea.id),
                        ),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Acta para imprimir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por local, nombre o cédula',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _filtro = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                  if (visibles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _lista.isEmpty ? 'Nadie ha registrado asistencia todavía.' : 'Sin resultados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colores.onSurfaceVariant),
                      ),
                    ),
                  ...visibles.map(
                    (a) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: a.esApoderado ? colores.tertiaryContainer : colores.primaryContainer,
                          child: Text(a.numero ?? '', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(a.nombre),
                        subtitle: Text(
                          '${a.tipoTexto} · C.C. ${a.cedula}\n'
                          'Local ${a.numero} · Coef. ${decimal(a.coeficiente)} % · ${a.hora} · ${a.origenTexto}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _borrar(a),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
