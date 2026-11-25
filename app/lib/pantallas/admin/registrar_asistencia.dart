import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

/// La administradora registra a mano la asistencia de un local.
Future<bool> mostrarRegistrarAsistencia(BuildContext context, {String? numero}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoRegistrar(numero: numero),
  );
  return r == true;
}

class _DialogoRegistrar extends StatefulWidget {
  final String? numero;
  const _DialogoRegistrar({this.numero});

  @override
  State<_DialogoRegistrar> createState() => _DialogoRegistrarState();
}

class _DialogoRegistrarState extends State<_DialogoRegistrar> {
  final _numero = TextEditingController();
  final _nombre = TextEditingController();
  final _cedula = TextEditingController();
  Local? _local;
  String _tipo = 'propietario';
  bool _reemplazar = false;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.numero != null) {
      _numero.text = widget.numero!;
      _buscar();
    }
  }

  @override
  void dispose() {
    _numero.dispose();
    _nombre.dispose();
    _cedula.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final n = _numero.text.trim();
    if (n.isEmpty) {
      setState(() => _error = 'Escribe el número del local.');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final r = await Api.i.get('/api/locales/${Uri.encodeComponent(n)}');
      final local = Local.desde(Map<String, dynamic>.from(r['local'] as Map));
      if (!mounted) return;
      setState(() {
        _local = local;
        _reemplazar = false;
        _nombre.text = local.apoderado?.nombre ?? '';
        _cedula.text = local.apoderado?.cedula ?? '';
        if (local.apoderado != null) _tipo = 'apoderado';
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _local = null;
          _error = e.mensaje;
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _guardar() async {
    final local = _local;
    if (local == null) {
      await _buscar();
      return;
    }
    if (local.presente && !_reemplazar) {
      setState(() => _error = 'Este local ya está registrado. Marca «Reemplazar el registro» para corregirlo.');
      return;
    }
    final cuerpo = <String, dynamic>{'numero': local.numero, 'tipo': _tipo, 'reemplazar': _reemplazar};
    if (_tipo == 'apoderado') {
      cuerpo['nombre'] = _nombre.text.trim();
      cuerpo['cedula'] = _cedula.text.trim();
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await Api.i.post('/api/admin/asistencias', cuerpo);
      if (!mounted) return;
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      mensajero.showSnackBar(SnackBar(
        content: Text('Asistencia del local ${local.numero} registrada.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _local;
    final colores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Registrar asistencia'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _numero,
                      autofocus: widget.numero == null,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Número de local'),
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Buscar',
                    onPressed: _ocupado ? null : _buscar,
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
              if (local != null) ...[
                const SizedBox(height: 12),
                Text('Coeficiente: ${decimal(local.coeficiente)} %'),
                Text('Propietario: ${local.propietario.nombre} (C.C. ${local.propietario.cedula})'),
                if (local.asistencia != null) ...[
                  const SizedBox(height: 10),
                  Aviso(
                    icono: Icons.info_outline,
                    color: ambar,
                    texto: 'Ya está registrado a las ${local.asistencia!.hora}',
                    detalle: '${local.asistencia!.tipoTexto}: ${local.asistencia!.nombre}',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _reemplazar,
                    onChanged: (v) => setState(() => _reemplazar = v == true),
                    title: const Text('Reemplazar el registro'),
                  ),
                ],
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'propietario', label: Text('Propietario'), icon: Icon(Icons.person)),
                    ButtonSegment(value: 'apoderado', label: Text('Apoderado'), icon: Icon(Icons.badge_outlined)),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (s) => setState(() => _tipo = s.first),
                ),
                if (_tipo == 'apoderado') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre del apoderado'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cedula,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]'))],
                    decoration: const InputDecoration(labelText: 'Cédula del apoderado'),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colores.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _ocupado ? null : _guardar,
          child: Text(local == null ? 'Buscar local' : 'Registrar'),
        ),
      ],
    );
  }
}
