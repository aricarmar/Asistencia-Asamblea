import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../servicios/api.dart';
import '../../tema.dart';
import '../../util.dart';
import '../../widgets/comunes.dart';

/// Pantalla para compartir la app: código QR para escanear y enlaces para enviar por WhatsApp.
class CompartirPantalla extends StatefulWidget {
  const CompartirPantalla({super.key});

  @override
  State<CompartirPantalla> createState() => _CompartirPantallaState();
}

class _CompartirPantallaState extends State<CompartirPantalla> {
  bool _cargando = true;
  bool _modoLocal = false;
  List<String> _direcciones = [];
  String? _elegida;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Api.i.get('/api/red');
      final lista = (r['direcciones'] as List? ?? const []).map((e) => '$e').toList();
      if (!mounted) return;
      setState(() {
        _modoLocal = r['modo_local'] == true;
        _direcciones = lista;
        _elegida = lista.isNotEmpty ? lista.first : null;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String get _enlaceWeb {
    if (_modoLocal) return _elegida ?? (kIsWeb ? '${Uri.base.origin}/' : Api.i.baseUrl);
    return Api.urlWeb;
  }

  String get _enlaceApk => '${Api.urlWeb}descargas/asamblea-trebolis.apk';

  Future<void> _copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) mostrarMensaje(context, aviso);
  }

  String get _mensajeWhatsApp => _modoLocal
      ? 'Asamblea $nombreCopropiedad $tipoCopropiedad\n\n'
          '1. Conéctate al Wi-Fi de la asamblea.\n'
          '2. Abre este enlace: $_enlaceWeb\n'
          '3. Escribe el número de tu local y toca INGRESAR.'
      : 'Asamblea $nombreCopropiedad $tipoCopropiedad\n\n'
          'Para registrar tu asistencia y votar, abre: $_enlaceWeb\n\n'
          'O instala la app en Android: $_enlaceApk\n\n'
          'Solo necesitas el número de tu local.';

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Compartir la app'), actions: const [BotonTema()]),
      body: _cargando
          ? const Cargando()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Contenedor(
                  anchoMaximo: 560,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const LogoTrebolis(ancho: 150),
                              const SizedBox(height: 10),
                              Text(
                                _modoLocal ? 'Asamblea sin internet' : 'Escanea para entrar',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _modoLocal
                                    ? 'Primero conéctate al Wi-Fi de la asamblea y luego escanea el código.'
                                    : 'Apunta la cámara del celular al código. Solo necesitas el número de tu local.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colores.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(Radios.fila),
                                ),
                                child: QrImageView(
                                  data: _enlaceWeb,
                                  version: QrVersions.auto,
                                  size: 240,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Colores.verdeOscuro),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colores.verdeOscuro,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                _enlaceWeb,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              if (_modoLocal && _direcciones.length > 1) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Este computador tiene varias redes. Elige la del Wi-Fi de la asamblea:',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colores.onSurfaceVariant),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final d in _direcciones)
                                      ChoiceChip(
                                        label: Text(d),
                                        selected: d == _elegida,
                                        onSelected: (_) => setState(() => _elegida = d),
                                      ),
                                  ],
                                ),
                              ],
                              if (_modoLocal && _direcciones.isEmpty) ...[
                                const SizedBox(height: 10),
                                const Aviso(
                                  icono: Icons.wifi_off,
                                  color: ambar,
                                  texto: 'Este computador no está conectado a ninguna red Wi-Fi',
                                  detalle: 'Conéctalo al router o al celular que comparte la red, y vuelve a abrir esta pantalla.',
                                ),
                              ],
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _copiar(_enlaceWeb, 'Enlace copiado.'),
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copiar enlace'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _copiar(_mensajeWhatsApp, 'Mensaje copiado. Pégalo en WhatsApp.'),
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('Copiar mensaje para WhatsApp'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_modoLocal) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.android, color: Colores.verde),
                                    SizedBox(width: 8),
                                    Text('App para Android (APK)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Envía el archivo del APK por WhatsApp como «Documento», o comparte este enlace. '
                                  'Al instalarlo, Android puede pedir permitir «instalar apps desconocidas».',
                                  style: TextStyle(color: colores.onSurfaceVariant),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(_enlaceApk, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _copiar(_enlaceApk, 'Enlace del APK copiado.'),
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copiar enlace del APK'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Aviso(
                        icono: Icons.person_pin_circle_outlined,
                        color: verdeOk,
                        texto: '¿Alguien no tiene celular o internet?',
                        detalle: 'Logística puede registrar su asistencia (pestaña Asistencia) y su voto (Votaciones → Voto manual).',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
