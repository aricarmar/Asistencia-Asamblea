import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../util.dart';
import '../widgets/comunes.dart';
import 'identificacion.dart';
import 'ingreso_admin.dart';

/// Primera pantalla: solo se escribe el número del local.
class IngresoPantalla extends StatefulWidget {
  const IngresoPantalla({super.key});

  @override
  State<IngresoPantalla> createState() => _IngresoPantallaState();
}

class _IngresoPantallaState extends State<IngresoPantalla> {
  final _numero = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    final numero = _numero.text.trim();
    if (numero.isEmpty) {
      setState(() => _error = 'Escribe el número de tu local.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await Api.i.get('/api/publico/local/${Uri.encodeComponent(numero)}');
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => IdentificacionPantalla(datos: datos)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _configurarServidor() async {
    final campo = TextEditingController(text: Api.i.baseUrl);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Dirección de la API. Normalmente no hay que cambiarla.'),
            const SizedBox(height: 12),
            TextField(controller: campo, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              campo.text = Api.urlPorDefecto;
            },
            child: const Text('Restablecer'),
          ),
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar == true) {
      await Api.i.cambiarServidor(campo.text);
      if (mounted) mostrarMensaje(context, 'Servidor guardado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Servidor',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _configurarServidor,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Contenedor(
            anchoMaximo: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: colores.primary,
                    child: Icon(Icons.how_to_reg, size: 50, color: colores.onPrimary),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Asistencia a la asamblea',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Escribe el número de tu local para ingresar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colores.onSurfaceVariant, fontSize: 16),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _numero,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.go,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 2),
                  decoration: InputDecoration(
                    labelText: 'Número de local',
                    hintText: 'Ej: 101',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                  onSubmitted: (_) {
                    if (!_cargando) _continuar();
                  },
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _cargando ? null : _continuar,
                  icon: _cargando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(_cargando ? 'Buscando...' : 'Continuar'),
                ),
                if (_cargando) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Si es el primer ingreso del día puede tardar hasta un minuto.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colores.onSurfaceVariant, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const IngresoAdminPantalla()),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Ingreso de la administradora'),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => abrirEnlace(context, Uri.base.resolve('descargas/asistencia-asamblea.apk')),
                    icon: const Icon(Icons.android),
                    label: const Text('Descargar la app para Android'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
