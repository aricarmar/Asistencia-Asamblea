import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

/// Crear o editar un local. Devuelve true si se guardó.
class FormularioLocalPantalla extends StatefulWidget {
  final Local? local;
  const FormularioLocalPantalla({super.key, this.local});

  @override
  State<FormularioLocalPantalla> createState() => _FormularioLocalPantallaState();
}

class _FormularioLocalPantallaState extends State<FormularioLocalPantalla> {
  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _numero;
  late final TextEditingController _coeficiente;
  late final TextEditingController _propNombre;
  late final TextEditingController _propCedula;
  late final TextEditingController _apoNombre;
  late final TextEditingController _apoCedula;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.local != null;

  @override
  void initState() {
    super.initState();
    final l = widget.local;
    _numero = TextEditingController(text: l?.numero ?? '');
    _coeficiente = TextEditingController(text: l == null ? '' : decimal(l.coeficiente, decimales: 6));
    _propNombre = TextEditingController(text: l?.propietario.nombre ?? '');
    _propCedula = TextEditingController(text: l?.propietario.cedula ?? '');
    _apoNombre = TextEditingController(text: l?.apoderado?.nombre ?? '');
    _apoCedula = TextEditingController(text: l?.apoderado?.cedula ?? '');
  }

  @override
  void dispose() {
    for (final c in [_numero, _coeficiente, _propNombre, _propCedula, _apoNombre, _apoCedula]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _obligatorio(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;
    final cuerpo = {
      'numero': _numero.text.trim(),
      'coeficiente': _coeficiente.text.trim(),
      'propietario_nombre': _propNombre.text.trim(),
      'propietario_cedula': _propCedula.text.trim(),
      'apoderado_nombre': _apoNombre.text.trim(),
      'apoderado_cedula': _apoCedula.text.trim(),
    };
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_editando) {
        await Api.i.put('/api/admin/locales/${widget.local!.id}', cuerpo);
      } else {
        await Api.i.post('/api/admin/locales', cuerpo);
      }
      if (!mounted) return;
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      mensajero.showSnackBar(SnackBar(
        content: Text('Local ${cuerpo['numero']} guardado.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _quitar() async {
    final ok = await confirmar(
      context,
      titulo: 'Quitar local ${widget.local!.numero}',
      mensaje: 'El local deja de aparecer y no cuenta para el quórum. Su historial de asistencia se conserva. '
          'Si lo vuelves a crear con el mismo número, se recupera.',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    try {
      await Api.i.delete('/api/admin/locales/${widget.local!.id}');
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar local ${widget.local!.numero}' : 'Nuevo local'),
        actions: [
          if (_editando)
            IconButton(tooltip: 'Quitar local', icon: const Icon(Icons.delete_outline), onPressed: _quitar),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Contenedor(
                anchoMaximo: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _numero,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'Número de local'),
                            validator: _obligatorio,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _coeficiente,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            decoration: const InputDecoration(labelText: 'Coeficiente (%)', hintText: '0,8523'),
                            validator: _obligatorio,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('Propietario', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _propNombre,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre completo'),
                      validator: _obligatorio,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _propCedula,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cédula o NIT'),
                      validator: _obligatorio,
                    ),
                    const SizedBox(height: 22),
                    Text('Apoderado (opcional)', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Si el propietario dio poder a alguien, escribe sus datos. Si no, déjalo vacío.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _apoNombre,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre del apoderado'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apoCedula,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cédula del apoderado'),
                      validator: (v) {
                        final hayNombre = _apoNombre.text.trim().isNotEmpty;
                        final hayCedula = (v ?? '').trim().isNotEmpty;
                        if (hayNombre != hayCedula) return 'Escribe el nombre y la cédula, o deja los dos vacíos';
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Aviso(icono: Icons.error_outline, color: Theme.of(context).colorScheme.error, texto: _error!),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
