import 'package:flutter/material.dart';

import '../modelos.dart';
import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../tema.dart';
import '../util.dart';
import '../widgets/comunes.dart';

/// Pestaña "Votación" del propietario o apoderado: aparece la pregunta con sus opciones.
class VotacionPestana extends StatefulWidget {
  const VotacionPestana({super.key});

  @override
  State<VotacionPestana> createState() => _VotacionPestanaState();
}

class _VotacionPestanaState extends State<VotacionPestana> with RefrescoEnVivo<VotacionPestana> {
  VotacionActual? _actual;
  String? _error;
  bool _enviando = false;

  @override
  Set<String> get eventosQueEscucha => const {'votacion', 'asistencia', 'asamblea', 'conectado'};

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
      final r = await Api.i.get('/api/votacion/actual');
      if (!mounted) return;
      setState(() {
        _actual = VotacionActual.desde(r);
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _votar(Pregunta p, int opcion) async {
    final a = _actual!;
    final ok = await confirmar(
      context,
      titulo: 'Confirmar voto',
      mensaje: 'Vas a votar «${p.opciones[opcion]}» por el local ${a.localNumero ?? ''} '
          'con un coeficiente de ${decimal(a.coeficiente)} %.\n\nUna vez enviado, el voto no se puede cambiar.',
      accion: 'Votar',
    );
    if (!ok) return;
    setState(() => _enviando = true);
    try {
      await Api.i.post('/api/votacion/votar', {'pregunta_id': p.id, 'opcion': opcion});
      if (mounted) mostrarMensaje(context, '¡Voto registrado: ${p.opciones[opcion]}!');
      await _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      await _cargar();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _actual;
    if (a == null && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (a == null) return const Cargando();
    final colores = Theme.of(context).colorScheme;
    final p = a.pregunta;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenedor(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                      child: MensajeEstado(
                        icono: Icons.how_to_vote_outlined,
                        titulo: 'No hay una votación abierta',
                        detalle: a.asamblea == null
                            ? 'Cuando empiece la asamblea, aquí aparecerán las preguntas.'
                            : 'Cuando logística abra una pregunta, aparecerá aquí sola.',
                      ),
                    ),
                  )
                else
                  _tarjetaPregunta(p, a, colores),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                ],
                if (a.ultima != null && a.ultima!.resultados != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Resultado de la pregunta ${a.ultima!.numero}',
                              style: TextStyle(color: colores.primary, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(a.ultima!.texto, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          BarrasResultados(resultados: a.ultima!.resultados!),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPregunta(Pregunta p, VotacionActual a, ColorScheme colores) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colores.verde, Colores.lima]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_vote, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Pregunta ${p.numero}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p.texto,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (a.localNumero != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(Radios.campo),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.pie_chart, color: colores.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tu voto vale ${decimal(a.coeficiente)} % · Local ${a.localNumero}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: colores.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (a.miVoto != null && a.miVoto! < p.opciones.length)
                  Aviso(
                    icono: Icons.check_circle,
                    color: verdeOk,
                    texto: 'Tu local votó «${p.opciones[a.miVoto!]}»${a.horaMiVoto != null ? ' a las ${a.horaMiVoto}' : ''}',
                    detalle: 'Los resultados aparecen cuando se cierre la votación.',
                  )
                else if (!a.puedeVotar)
                  Aviso(icono: Icons.info_outline, color: ambar, texto: a.motivo ?? 'No puedes votar en este momento.')
                else ...[
                  Text('Elige tu respuesta:', style: TextStyle(color: colores.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < p.opciones.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colorOpcion(i),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          onPressed: _enviando ? null : () => _votar(p, i),
                          icon: const Icon(Icons.how_to_vote_outlined),
                          label: Text(p.opciones[i], overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
