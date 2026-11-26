import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../tema.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

const _opcionesPorDefecto = ['Sí', 'No', 'Abstención'];

/// Votaciones (logística y administradora): crear preguntas, abrirlas, ver resultados en vivo y cerrarlas.
class VotacionesPestana extends StatefulWidget {
  const VotacionesPestana({super.key});

  @override
  State<VotacionesPestana> createState() => _VotacionesPestanaState();
}

class _VotacionesPestanaState extends State<VotacionesPestana> with RefrescoEnVivo<VotacionesPestana> {
  Asamblea? _asamblea;
  List<Pregunta> _preguntas = [];
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
      final r = await Api.i.get('/api/gestion/preguntas');
      if (!mounted) return;
      setState(() {
        _asamblea = Asamblea.desde(r['asamblea']);
        _preguntas = (r['preguntas'] as List? ?? const []).map((e) => Pregunta.desde(e)).whereType<Pregunta>().toList();
        _cargado = true;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _accion(Future<Object?> Function() fn, String exito) async {
    try {
      await fn();
      if (mounted) mostrarMensaje(context, exito);
      await _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _nueva({Pregunta? editar}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FormularioPreguntaPantalla(pregunta: editar)),
    );
    if (ok == true) _cargar();
  }

  Future<void> _abrir(Pregunta p) async {
    final ok = await confirmar(
      context,
      titulo: 'Abrir votación',
      mensaje: 'La pregunta ${p.numero} aparecerá de inmediato en el celular de todos los asistentes para que voten.',
      accion: 'Abrir votación',
    );
    if (ok) await _accion(() => Api.i.post('/api/gestion/preguntas/${p.id}/abrir'), 'Votación abierta. Ya la ven todos.');
  }

  Future<void> _cerrar(Pregunta p) async {
    final r = p.resultados;
    final ok = await confirmar(
      context,
      titulo: 'Cerrar votación',
      mensaje: (r != null && r.faltanLocales > 0)
          ? 'Todavía faltan ${r.faltanLocales} locales por votar (${decimal(r.faltanCoeficiente)} % de coeficiente). '
              '¿Cerrar de todas formas? Los asistentes verán el resultado.'
          : 'Ya no se recibirán más votos y los asistentes verán el resultado.',
      accion: 'Cerrar votación',
      peligrosa: true,
    );
    if (ok) await _accion(() => Api.i.post('/api/gestion/preguntas/${p.id}/cerrar'), 'Votación cerrada.');
  }

  Future<void> _borrar(Pregunta p) async {
    final votos = p.resultados?.votaronLocales ?? 0;
    if (votos == 0) {
      final ok = await confirmar(
        context,
        titulo: 'Borrar pregunta ${p.numero}',
        mensaje: '¿Borrar «${p.texto}»?',
        accion: 'Borrar',
        peligrosa: true,
      );
      if (ok) await _accion(() => Api.i.delete('/api/gestion/preguntas/${p.id}'), 'Pregunta borrada.');
      return;
    }
    final ok = await confirmarEscribiendo(
      context,
      titulo: 'Borrar pregunta ${p.numero}',
      mensaje: 'Esta pregunta tiene $votos votos. Si la borras, se pierden los votos y no saldrá en el acta.',
    );
    if (ok) await _accion(() => Api.i.delete('/api/gestion/preguntas/${p.id}?forzar=si'), 'Pregunta borrada.');
  }

  Future<void> _votoManual(Pregunta p) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _DialogoVotoManual(pregunta: p));
    if (ok == true) _cargar();
  }

  Future<void> _verVotos(Pregunta p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VotosPantalla(pregunta: p)));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado && _error != null) return ErrorReintentar(mensaje: _error!, alReintentar: _cargar);
    if (!_cargado) return const Cargando();
    final colores = Theme.of(context).colorScheme;
    final asamblea = _asamblea;
    final abierta = asamblea != null && asamblea.abierta;
    final activa = _preguntas.where((p) => p.abierta).toList();
    final otras = _preguntas.where((p) => !p.abierta).toList();

    return Scaffold(
      floatingActionButton: abierta
          ? FloatingActionButton.extended(
              onPressed: () => _nueva(),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nueva pregunta'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Contenedor(
              anchoMaximo: 820,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (asamblea == null)
                    const MensajeEstado(
                      icono: Icons.event_outlined,
                      titulo: 'Todavía no hay asambleas',
                      detalle: 'La administradora debe crear y abrir la asamblea antes de las votaciones.',
                    )
                  else ...[
                    Text(asamblea.nombre, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${fechaBonita(asamblea.fecha)} · ${asamblea.estadoTexto} · ${_preguntas.length} preguntas',
                        style: TextStyle(color: colores.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => abrirEnlace(
                            context,
                            Api.i.informe('/api/gestion/informes/votaciones.csv', asambleaId: asamblea.id),
                          ),
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Excel de votaciones'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => abrirEnlace(context, Api.i.informe('/api/admin/informes/acta', asambleaId: asamblea.id)),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Acta'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!abierta)
                      const Aviso(
                        icono: Icons.info_outline,
                        color: ambar,
                        texto: 'La asamblea no está abierta',
                        detalle: 'Para hacer preguntas, la administradora debe abrir la asamblea.',
                      ),
                    if (_error != null) Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                    if (abierta && _preguntas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: MensajeEstado(
                          icono: Icons.how_to_vote_outlined,
                          titulo: 'Aún no hay preguntas',
                          detalle: 'Escribe la primera pregunta. Cuando la abras, a todos les saldrán las opciones.',
                          textoBoton: 'Nueva pregunta',
                          alPresionar: () => _nueva(),
                        ),
                      ),
                    for (final p in activa) _tarjetaActiva(p, colores),
                    for (final p in otras) _tarjeta(p, colores, abierta),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaActiva(Pregunta p, ColorScheme colores) {
    final r = p.resultados;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.tarjeta),
        side: const BorderSide(color: verdeOk, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colores.verde, Colores.lima])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.white, size: 12),
                    const SizedBox(width: 8),
                    Text(
                      'EN VIVO · Pregunta ${p.numero}${p.horaApertura != null ? ' · desde las ${p.horaApertura}' : ''}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(p.texto, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r != null) BarrasResultados(resultados: r),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: colores.error, foregroundColor: colores.onError),
                      onPressed: () => _cerrar(p),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Cerrar votación'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _votoManual(p),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Voto manual'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _verVotos(p),
                      icon: const Icon(Icons.list_alt),
                      label: const Text('Ver votos'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Pregunta p, ColorScheme colores, bool asambleaAbierta) {
    final r = p.resultados;
    final color = p.cerrada ? colores.outline : ambar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Pregunta ${p.numero}', style: TextStyle(color: colores.primary, fontWeight: FontWeight.w800)),
                ),
                Chip(
                  label: Text(p.cerrada ? 'Cerrada${p.horaCierre != null ? ' ${p.horaCierre}' : ''}' : 'Sin abrir'),
                  side: BorderSide(color: color),
                  avatar: Icon(Icons.circle, size: 12, color: color),
                ),
              ],
            ),
            Text(p.texto, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (p.sinAbrir)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < p.opciones.length; i++)
                    Chip(
                      avatar: Icon(Icons.circle, size: 12, color: colorOpcion(i)),
                      label: Text(p.opciones[i]),
                    ),
                ],
              )
            else if (r != null)
              BarrasResultados(resultados: r),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.sinAbrir && asambleaAbierta)
                  FilledButton.icon(
                    onPressed: () => _abrir(p),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Abrir votación'),
                  ),
                if (p.sinAbrir)
                  OutlinedButton.icon(
                    onPressed: () => _nueva(editar: p),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                if (p.cerrada)
                  OutlinedButton.icon(
                    onPressed: () => _verVotos(p),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Ver votos'),
                  ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colores.error),
                  onPressed: () => _borrar(p),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Borrar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Escribir o editar una pregunta con sus opciones.
class FormularioPreguntaPantalla extends StatefulWidget {
  final Pregunta? pregunta;
  const FormularioPreguntaPantalla({super.key, this.pregunta});

  @override
  State<FormularioPreguntaPantalla> createState() => _FormularioPreguntaPantallaState();
}

class _FormularioPreguntaPantallaState extends State<FormularioPreguntaPantalla> {
  late final TextEditingController _texto;
  final _nuevaOpcion = TextEditingController();
  late List<String> _opciones;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.pregunta != null;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.pregunta?.texto ?? '');
    _opciones = List<String>.from(widget.pregunta?.opciones ?? _opcionesPorDefecto);
  }

  @override
  void dispose() {
    _texto.dispose();
    _nuevaOpcion.dispose();
    super.dispose();
  }

  void _agregarOpcion() {
    final t = _nuevaOpcion.text.trim();
    if (t.isEmpty) return;
    if (_opciones.any((o) => o.toLowerCase() == t.toLowerCase())) {
      setState(() => _error = 'Esa opción ya está.');
      return;
    }
    if (_opciones.length >= 10) {
      setState(() => _error = 'Máximo 10 opciones.');
      return;
    }
    setState(() {
      _opciones.add(t);
      _nuevaOpcion.clear();
      _error = null;
    });
  }

  Future<void> _guardar({required bool abrir}) async {
    if (_texto.text.trim().length < 3) {
      setState(() => _error = 'Escribe la pregunta.');
      return;
    }
    if (_opciones.length < 2) {
      setState(() => _error = 'Pon al menos 2 opciones.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final cuerpo = {'texto': _texto.text.trim(), 'opciones': _opciones};
      if (_editando) {
        await Api.i.put('/api/gestion/preguntas/${widget.pregunta!.id}', cuerpo);
        if (abrir) await Api.i.post('/api/gestion/preguntas/${widget.pregunta!.id}/abrir');
      } else {
        await Api.i.post('/api/gestion/preguntas', {...cuerpo, 'abrir': abrir});
      }
      if (!mounted) return;
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      mensajero.showSnackBar(SnackBar(
        content: Text(abrir ? 'Votación abierta. Ya la ven todos.' : 'Pregunta guardada. Ábrela cuando quieras.'),
      ));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar pregunta ${widget.pregunta!.numero}' : 'Nueva pregunta'),
        actions: const [BotonTema()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Contenedor(
              anchoMaximo: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pregunta', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _texto,
                    autofocus: !_editando,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Ej: ¿Aprueba el presupuesto para el año 2027?',
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Opciones',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _opciones = List<String>.from(_opcionesPorDefecto)),
                        child: const Text('Sí / No / Abstención'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _opciones.length; i++)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorOpcion(i),
                          foregroundColor: Colors.white,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(_opciones[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: IconButton(
                          tooltip: 'Quitar opción',
                          icon: Icon(Icons.close, color: colores.error),
                          onPressed: () => setState(() => _opciones.removeAt(i)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nuevaOpcion,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Agregar opción (ej: nombre de un candidato)'),
                          onSubmitted: (_) => _agregarOpcion(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Agregar',
                        onPressed: _agregarOpcion,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Aviso(icono: Icons.error_outline, color: colores.error, texto: _error!),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _guardando ? null : () => _guardar(abrir: true),
                    icon: const Icon(Icons.how_to_vote),
                    label: const Text('Guardar y abrir votación'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _guardando ? null : () => _guardar(abrir: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Solo guardar (abrir después)'),
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

/// Logística registra el voto de alguien que no tiene celular.
class _DialogoVotoManual extends StatefulWidget {
  final Pregunta pregunta;
  const _DialogoVotoManual({required this.pregunta});

  @override
  State<_DialogoVotoManual> createState() => _DialogoVotoManualState();
}

class _DialogoVotoManualState extends State<_DialogoVotoManual> {
  final _numero = TextEditingController();
  int? _opcion;
  bool _reemplazar = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_numero.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el número del local.');
      return;
    }
    if (_opcion == null) {
      setState(() => _error = 'Elige la opción que votó.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/api/gestion/preguntas/${widget.pregunta.id}/votos', {
        'numero': _numero.text.trim(),
        'opcion': _opcion,
        'reemplazar': _reemplazar,
      });
      if (!mounted) return;
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      mensajero.showSnackBar(SnackBar(content: Text('Voto del local ${r['numero']}: ${r['texto']}')));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pregunta;
    return AlertDialog(
      title: const Text('Voto manual'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pregunta ${p.numero}: ${p.texto}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: _numero,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Número de local', prefixIcon: Icon(Icons.storefront_outlined)),
              ),
              const SizedBox(height: 14),
              const Text('Votó:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < p.opciones.length; i++)
                    ChoiceChip(
                      label: Text(p.opciones[i]),
                      selected: _opcion == i,
                      selectedColor: colorOpcion(i).withAlpha(70),
                      avatar: Icon(Icons.circle, size: 12, color: colorOpcion(i)),
                      onSelected: (_) => setState(() => _opcion = i),
                    ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _reemplazar,
                onChanged: (v) => setState(() => _reemplazar = v == true),
                title: const Text('Si ya votó, reemplazar su voto'),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Registrar voto')),
      ],
    );
  }
}

/// Lista de votos de una pregunta (quién votó qué), con opción de quitar un voto.
class VotosPantalla extends StatefulWidget {
  final Pregunta pregunta;
  const VotosPantalla({super.key, required this.pregunta});

  @override
  State<VotosPantalla> createState() => _VotosPantallaState();
}

class _VotosPantallaState extends State<VotosPantalla> with RefrescoEnVivo<VotosPantalla> {
  Pregunta? _pregunta;
  List<Map<String, dynamic>> _votos = [];
  String? _error;

  @override
  Set<String> get eventosQueEscucha => const {'voto', 'votacion', 'conectado'};

  @override
  void initState() {
    super.initState();
    _pregunta = widget.pregunta;
    escucharEnVivo();
    _cargar();
  }

  @override
  void alCambiar() => _cargar();

  Future<void> _cargar() async {
    try {
      final r = await Api.i.get('/api/gestion/preguntas/${widget.pregunta.id}/votos');
      if (!mounted) return;
      setState(() {
        _pregunta = Pregunta.desde(r['pregunta']) ?? _pregunta;
        _votos = (r['votos'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _quitar(Map<String, dynamic> v) async {
    final ok = await confirmar(
      context,
      titulo: 'Quitar voto del local ${v['numero']}',
      mensaje: '¿Quitar el voto «${v['opcion_texto']}»? El local podrá votar otra vez mientras la votación esté abierta.',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/gestion/votos/${v['id']}');
      if (mounted) mostrarMensaje(context, 'Voto quitado.');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pregunta!;
    final colores = Theme.of(context).colorScheme;
    String origen(dynamic r) => r == 'asistente' ? 'App' : (r == 'logistica' ? 'Logística' : 'Administradora');
    return Scaffold(
      appBar: AppBar(title: Text('Votos · Pregunta ${p.numero}'), actions: const [BotonTema()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenedor(
            anchoMaximo: 820,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(p.texto, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        if (p.resultados != null) BarrasResultados(resultados: p.resultados!),
                      ],
                    ),
                  ),
                ),
                if (_error != null) Aviso(icono: Icons.cloud_off, color: colores.error, texto: _error!),
                const SizedBox(height: 8),
                Text('${_votos.length} votos', style: TextStyle(color: colores.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final v in _votos)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorOpcion((v['opcion'] as num?)?.toInt() ?? 0),
                        foregroundColor: Colors.white,
                        child: Text('${v['numero']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      title: Text('${v['opcion_texto']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '${v['votante_nombre']} (${v['tipo'] == 'apoderado' ? 'Apoderado' : 'Propietario'}) · C.C. ${v['votante_cedula']}\n'
                        'Coef. ${decimal(v['coeficiente'] as num?)} % · ${v['hora']} · ${origen(v['registrado_por'])}',
                      ),
                      isThreeLine: true,
                      trailing: p.abierta
                          ? IconButton(
                              tooltip: 'Quitar voto',
                              icon: Icon(Icons.delete_outline, color: colores.error),
                              onPressed: () => _quitar(v),
                            )
                          : null,
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
