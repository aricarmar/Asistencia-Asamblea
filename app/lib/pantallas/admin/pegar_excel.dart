import 'package:flutter/material.dart';

import '../../servicios/api.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

/// Cargar muchos locales de una vez copiando las columnas desde Excel.
class PegarExcelPantalla extends StatefulWidget {
  const PegarExcelPantalla({super.key});

  @override
  State<PegarExcelPantalla> createState() => _PegarExcelPantallaState();
}

class _PegarExcelPantallaState extends State<PegarExcelPantalla> {
  final _texto = TextEditingController();
  bool _reemplazar = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _importar() async {
    if (_texto.text.trim().isEmpty) {
      setState(() => _error = 'Pega primero las filas copiadas de Excel.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/api/admin/locales/importar', {'texto': _texto.text, 'reemplazar': _reemplazar});
      if (!mounted) return;
      final errores = (r['errores'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Locales cargados'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nuevos: ${r['creados']}'),
                Text('Actualizados: ${r['actualizados']}'),
                if (_reemplazar) Text('Quitados (no estaban en la lista): ${r['desactivados']}'),
                Text('Suma de coeficientes pegados: ${decimal(r['suma_coeficientes'] as num?)} %'),
                if (errores.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Filas que no se cargaron:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...errores.map((e) => Text('• $e')),
                ],
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(contexto), child: const Text('Aceptar'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pegar locales desde Excel')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Contenedor(
              anchoMaximo: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cómo hacerlo', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text('1. En Excel, organiza las columnas en este orden:'),
                          const Text('   Local | Coeficiente | Propietario | Cédula | Apoderado | Cédula apoderado'),
                          const Text('   (las dos últimas son opcionales)'),
                          const Text('2. Selecciona las filas, cópialas (Ctrl + C) y pégalas abajo (Ctrl + V).'),
                          const Text('3. Si copiaste la fila de títulos no pasa nada: se ignora.'),
                          const SizedBox(height: 8),
                          Text(
                            'Si un local ya existe, se actualizan sus datos.',
                            style: TextStyle(color: colores.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _texto,
                    minLines: 10,
                    maxLines: 20,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '101\t0,8523\tMaría López\t52123456\n102\t1,1250\tCarlos Gómez\t79123456',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _reemplazar,
                    onChanged: (v) => setState(() => _reemplazar = v == true),
                    title: const Text('Esta es la lista completa'),
                    subtitle: const Text('Quita los locales que no estén en la lista pegada.'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Aviso(icono: Icons.error_outline, color: colores.error, texto: _error!),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _enviando ? null : _importar,
                    icon: const Icon(Icons.upload),
                    label: Text(_enviando ? 'Cargando...' : 'Cargar locales'),
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
