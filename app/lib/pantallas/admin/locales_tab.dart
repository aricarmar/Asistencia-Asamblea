import 'dart:async';

import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';
import 'formulario_local.dart';
import 'pegar_excel.dart';

/// Lista de locales con su coeficiente, propietario y apoderado.
class LocalesPestana extends StatefulWidget {
  const LocalesPestana({super.key});

  @override
  State<LocalesPestana> createState() => _LocalesPestanaState();
}

class _LocalesPestanaState extends State<LocalesPestana> with RefrescoEnVivo<LocalesPestana> {
  List<Local> _locales = [];
  bool _cargado = false;
  String? _error;
  String _buscar = '';
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    escucharEnVivo();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  @override
  void alCambiar() => _cargar();

  Future<void> _cargar() async {
    try {
      final r = await Api.i.get('/api/admin/locales', _buscar.isEmpty ? null : {'buscar': _buscar});
      if (!mounted) return;
      setState(() {
        _locales = (r['locales'] as List? ?? const [])
            .map((e) => Local.desde(Map<String, dynamic>.from(e as Map)))
            .toList();
        _cargado = true;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      _buscar = texto.trim();
      _cargar();
    });
  }

  Future<void> _abrir(Widget pantalla) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => pantalla));
    if (ok == true) _cargar();
  }

  Future<void> _cargarEjemplo() async {
    final ok = await confirmar(
      context,
      titulo: 'Datos de ejemplo',
      mensaje: 'Se crean 51 locales de prueba (del 1 al 51) con nombres inventados para ensayar la app. '
          'Después puedes quitarlos o reemplazarlos pegando tu lista de Excel.',
      accion: 'Cargar',
    );
    if (!ok) return;
    try {
      await Api.i.post('/api/admin/locales/ejemplo');
      if (mounted) mostrarMensaje(context, 'Se cargaron 51 locales de ejemplo.');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _eliminar(Local l) async {
    final ok = await confirmar(
      context,
      titulo: 'Eliminar local ${l.numero}',
      mensaje: '¿Eliminar el local ${l.numero} (${l.propietario.nombre})? Deja de contar para el quórum'
          '${l.presente ? ' y se quita su asistencia de la asamblea abierta' : ''}. '
          'Si lo vuelves a crear o pegar desde Excel con el mismo número, se recupera.',
      accion: 'Eliminar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/admin/locales/${l.id}');
      if (mounted) mostrarMensaje(context, 'Local ${l.numero} eliminado.');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _borrarTodos() async {
    final ok = await confirmarEscribiendo(
      context,
      titulo: 'Borrar todos los locales',
      mensaje: 'Se quitan los ${_locales.length} locales de la lista y sus asistencias en la asamblea abierta. '
          'Úsalo, por ejemplo, para quitar los datos de ejemplo antes de pegar los reales.',
      accion: 'Borrar todos',
    );
    if (!ok) return;
    try {
      final r = await Api.i.post('/api/admin/locales/borrar-todos', {'confirmacion': 'BORRAR'});
      if (mounted) mostrarMensaje(context, 'Se quitaron ${r['locales_quitados']} locales.');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (!_cargado) return const Cargando();
    final colores = Theme.of(context).colorScheme;
    final suma = _locales.fold<double>(0, (s, l) => s + l.coeficiente);
    final sinLocales = _locales.isEmpty && _buscar.isEmpty;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(const FormularioLocalPantalla()),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo local'),
      ),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _abrir(const PegarExcelPantalla()),
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Pegar desde Excel'),
                      ),
                      if (sinLocales)
                        OutlinedButton.icon(
                          onPressed: _cargarEjemplo,
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Cargar datos de ejemplo'),
                        ),
                      if (_locales.isNotEmpty && _buscar.isEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colores.error,
                            side: BorderSide(color: colores.error),
                          ),
                          onPressed: _borrarTodos,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Borrar todos'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por local, nombre o cédula',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _alEscribir,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _buscar.isEmpty
                        ? '${_locales.length} locales · Suma de coeficientes: ${decimal(suma)} %'
                        : '${_locales.length} resultados',
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                  if (_buscar.isEmpty && _locales.isNotEmpty && (suma - 100).abs() > 0.01) ...[
                    const SizedBox(height: 8),
                    const Aviso(
                      icono: Icons.warning_amber,
                      color: ambar,
                      texto: 'Los coeficientes no suman 100 %',
                      detalle: 'Revisa que estén todos los locales y que los coeficientes estén bien escritos.',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                  ],
                  const SizedBox(height: 8),
                  if (sinLocales)
                    const MensajeEstado(
                      icono: Icons.storefront_outlined,
                      titulo: 'Aún no hay locales',
                      detalle: 'Pega la lista desde Excel o crea los locales uno por uno.',
                    ),
                  ..._locales.map(
                    (l) => Card(
                      child: ListTile(
                        onTap: () => _abrir(FormularioLocalPantalla(local: l)),
                        leading: CircleAvatar(
                          backgroundColor: l.presente ? verdeOk : colores.surfaceContainerHighest,
                          foregroundColor: l.presente ? Colors.white : colores.onSurface,
                          child: Text(l.numero, style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(l.propietario.nombre),
                        subtitle: Text(
                          'C.C. ${l.propietario.cedula} · Coef. ${decimal(l.coeficiente)} %'
                          '${l.apoderado != null ? '\nApoderado: ${l.apoderado!.nombre} (C.C. ${l.apoderado!.cedula})' : ''}',
                        ),
                        isThreeLine: l.apoderado != null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (l.presente)
                              const Tooltip(message: 'Presente', child: Icon(Icons.check_circle, color: verdeOk)),
                            IconButton(
                              tooltip: 'Eliminar local',
                              icon: Icon(Icons.delete_outline, color: colores.error),
                              onPressed: () => _eliminar(l),
                            ),
                          ],
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
