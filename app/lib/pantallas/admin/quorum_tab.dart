import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../widgets/comunes.dart';

/// Quórum en vivo y últimos en llegar.
class QuorumPestana extends StatefulWidget {
  final VoidCallback irAAsambleas;
  const QuorumPestana({super.key, required this.irAAsambleas});

  @override
  State<QuorumPestana> createState() => _QuorumPestanaState();
}

class _QuorumPestanaState extends State<QuorumPestana> with RefrescoEnVivo<QuorumPestana> {
  Quorum? _quorum;
  List<Asistencia> _ultimos = [];
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
      final r = await Future.wait([Api.i.get('/api/quorum'), Api.i.get('/api/admin/asistencias')]);
      if (!mounted) return;
      final lista = (r[1]['asistencias'] as List? ?? const [])
          .map((e) => Asistencia.desde(e))
          .whereType<Asistencia>()
          .take(10)
          .toList();
      setState(() {
        _quorum = Quorum.desde(r[0]);
        _ultimos = lista;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quorum;
    if (q == null && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (q == null) return const Cargando();
    if (q.asamblea == null) {
      return MensajeEstado(
        icono: Icons.event_outlined,
        titulo: 'Todavía no hay asambleas',
        detalle: 'Crea la asamblea y ábrela para que los propietarios y apoderados registren su asistencia.',
        textoBoton: 'Ir a Asambleas',
        alPresionar: widget.irAAsambleas,
      );
    }
    final colores = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenedor(
            anchoMaximo: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!q.asamblea!.abierta) ...[
                  Aviso(
                    icono: Icons.info_outline,
                    color: ambar,
                    texto: q.asamblea!.cerrada ? 'Esta asamblea ya se cerró' : 'Esta asamblea todavía no está abierta',
                    detalle: 'Mientras no esté abierta, nadie queda registrado al ingresar.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: widget.irAAsambleas, child: const Text('Ir a Asambleas')),
                  ),
                ],
                if (_error != null) ...[
                  Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                  const SizedBox(height: 8),
                ],
                TarjetaQuorum(quorum: q),
                const SizedBox(height: 16),
                Text('Últimos en llegar', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (_ultimos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Nadie ha registrado asistencia todavía.', style: TextStyle(color: colores.onSurfaceVariant)),
                  ),
                ..._ultimos.map(
                  (a) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(a.numero ?? '', style: const TextStyle(fontSize: 12))),
                      title: Text(a.nombre),
                      subtitle: Text('${a.tipoTexto} · Local ${a.numero ?? ''}'),
                      trailing: Text(a.hora, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
