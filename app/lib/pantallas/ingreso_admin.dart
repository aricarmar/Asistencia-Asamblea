import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../tema.dart';
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

  Widget _etiqueta(String texto) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: fondoDegradado(context),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          const LogoTrebolis(ancho: 170),
                          const SizedBox(height: 16),
                          const Text(
                            'ADMINISTRACIÓN',
                            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Administradora o logística · $nombreCopropiedad',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 24),
                          _etiqueta('USUARIO'),
                          TextField(
                            controller: _usuario,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(hintText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                          ),
                          const SizedBox(height: 14),
                          _etiqueta('CONTRASEÑA'),
                          TextField(
                            controller: _clave,
                            obscureText: !_verClave,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) {
                              if (!_cargando) _ingresar();
                            },
                            decoration: InputDecoration(
                              hintText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _verClave = !_verClave),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colores.rojoSuave,
                                borderRadius: BorderRadius.circular(Radios.fila),
                              ),
                              child: Text(_error!, style: const TextStyle(color: Colores.rojo)),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: oscuro ? ColoresOscuros.primario : Colors.black,
                                foregroundColor: oscuro ? ColoresOscuros.pagina : Colors.white,
                              ),
                              onPressed: _cargando ? null : _ingresar,
                              child: _cargando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('INGRESAR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
              const Positioned(top: 4, right: 4, child: BotonTema(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
