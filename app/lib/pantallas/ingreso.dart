import 'dart:async';

import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../tema.dart';
import '../util.dart';
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
  bool _lento = false;
  Timer? _temporizador;
  String? _error;

  @override
  void dispose() {
    _temporizador?.cancel();
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
      _lento = false;
      _error = null;
    });
    // Si en 4 segundos no responde, se avisa que el servidor está despertando.
    _temporizador = Timer(const Duration(seconds: 4), () {
      if (mounted && _cargando) setState(() => _lento = true);
    });
    try {
      final datos = await Api.i.get('/api/publico/local/${Uri.encodeComponent(numero)}');
      if (!mounted) return;
      _temporizador?.cancel();
      setState(() {
        _cargando = false;
        _lento = false;
      });
      await Navigator.push(context, MaterialPageRoute(builder: (_) => IdentificacionPantalla(datos: datos)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      _temporizador?.cancel();
      if (mounted) {
        setState(() {
          _cargando = false;
          _lento = false;
        });
      }
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
            const Text(
              'Dirección del servidor. Normalmente no hay que cambiarla.\n\n'
              'Asamblea sin internet: conéctate al Wi-Fi de la asamblea y escribe la dirección que muestra '
              'el computador, por ejemplo http://192.168.1.10:3000',
            ),
            const SizedBox(height: 12),
            TextField(controller: campo, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => campo.text = Api.urlPorDefecto.isEmpty ? Api.i.porDefecto : Api.urlPorDefecto, child: const Text('Restablecer')),
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
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final alto = MediaQuery.sizeOf(context).height;
    final anchoLogo = (alto * 0.30).clamp(170.0, 260.0);
    final compacto = alto < 720;

    return Scaffold(
      body: Container(
        decoration: fondoDegradado(context),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: compacto ? 12 : 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          LogoTrebolis(ancho: anchoLogo),
                          SizedBox(height: compacto ? 12 : 20),
                          const Text(
                            'BIENVENIDO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Asamblea · $nombreCopropiedad $tipoCopropiedad',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: compacto ? 18 : 26),
                          _etiqueta('NÚMERO DE LOCAL'),
                          TextField(
                            controller: _numero,
                            autofocus: true,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.go,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2),
                            decoration: const InputDecoration(
                              hintText: 'Ej: 12',
                              prefixIcon: Icon(Icons.storefront_outlined),
                            ),
                            onSubmitted: (_) {
                              if (!_cargando) _continuar();
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            _caja(_error!, Colores.rojoSuave, Colores.rojo),
                          ],
                          SizedBox(height: compacto ? 14 : 18),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                // En modo oscuro el botón es verde para que no se pierda en el fondo.
                                backgroundColor: oscuro ? ColoresOscuros.primario : Colors.black,
                                foregroundColor: oscuro ? ColoresOscuros.pagina : Colors.white,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _cargando ? null : _continuar,
                              child: _cargando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'INGRESAR',
                                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                                    ),
                            ),
                          ),
                          if (_lento) ...[
                            const SizedBox(height: 12),
                            _caja(
                              'Conectando con el servidor… Si estuvo inactivo, puede tardar hasta un minuto en despertar.',
                              Colores.ambarSuave,
                              Colores.texto,
                            ),
                          ],
                          SizedBox(height: compacto ? 18 : 28),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const IngresoAdminPantalla()),
                            ),
                            icon: const Icon(Icons.admin_panel_settings_outlined),
                            label: const Text(
                              'Ingreso de administración y logística',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
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
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BotonTema(color: Colors.white),
                    IconButton(
                      tooltip: 'Servidor',
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: _configurarServidor,
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

  Widget _etiqueta(String texto) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _caja(String texto, Color fondo, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(Radios.fila)),
        child: Text(texto, style: TextStyle(color: color)),
      );
}
