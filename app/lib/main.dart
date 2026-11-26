import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pantallas/admin/inicio_admin.dart';
import 'pantallas/inicio_asistente.dart';
import 'pantallas/ingreso.dart';
import 'servicios/api.dart';
import 'servicios/tiempo_real.dart';
import 'tema.dart';

final GlobalKey<NavigatorState> navegador = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.cargar();
  await controladorTema.cargar();
  Api.i.alVencerSesion = () async {
    await Api.i.cerrarSesion();
    TiempoReal.i.detener();
    navegador.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IngresoPantalla()),
      (_) => false,
    );
  };
  final Widget inicio;
  if (!Api.i.haySesion) {
    inicio = const IngresoPantalla();
  } else if (Api.i.esGestion) {
    inicio = const InicioAdminPantalla();
  } else {
    inicio = const InicioAsistentePantalla();
  }
  runApp(AsistenciaApp(inicio: inicio));
}

class AsistenciaApp extends StatelessWidget {
  /// Primera pantalla (se decide una sola vez al abrir la app).
  final Widget inicio;
  const AsistenciaApp({super.key, required this.inicio});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controladorTema,
      builder: (context, modo, _) => MaterialApp(
        navigatorKey: navegador,
        title: 'Asamblea Trebolis Capellanía',
        debugShowCheckedModeBanner: false,
        theme: construirTema(Brightness.light),
        darkTheme: construirTema(Brightness.dark),
        themeMode: modo,
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: inicio,
      ),
    );
  }
}
