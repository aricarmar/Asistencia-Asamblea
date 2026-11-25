import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../widgets/comunes.dart';
import 'admin/inicio_admin.dart';

class IngresoAdminPantalla extends StatefulWidget {
  const IngresoAdminPantalla({super.key});

  @override
  State<IngresoAdminPantalla> createState() => _IngresoAdminPantallaState();
}

class _IngresoAdminPantallaState extends State<IngresoAdminPantalla> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (_usuario.text.trim().isEmpty || _clave.text.isEmpty) {
      setState(() => _error = 'Escribe el usuario y la contraseña.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/api/admin/ingreso', {'usuario': _usuario.text.trim(), 'clave': _clave.text});
      await Api.i.guardarSesion(r);
      TiempoReal.i.iniciar();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioAdminPantalla()),
        (_) => false,
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administradora')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Contenedor(
            anchoMaximo: 420,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings, size: 64),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _clave,
                    obscureText: !_verClave,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) {
                      if (!_cargando) _ingresar();
                    },
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _verClave = !_verClave),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Aviso(icono: Icons.error_outline, color: Theme.of(context).colorScheme.error, texto: _error!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _cargando ? null : _ingresar,
                    icon: _cargando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
