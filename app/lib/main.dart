import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pantallas/admin/inicio_admin.dart';
import 'pantallas/inicio_asistente.dart';
import 'pantallas/ingreso.dart';
import 'servicios/api.dart';
import 'servicios/tiempo_real.dart';

final GlobalKey<NavigatorState> navegador = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.cargar();
  Api.i.alVencerSesion = () async {
    await Api.i.cerrarSesion();
    TiempoReal.i.detener();
    navegador.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IngresoPantalla()),
      (_) => false,
    );
  };
  runApp(const AsistenciaApp());
}

ThemeData tema(Brightness brillo) {
  final colores = ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C81), brightness: brillo);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colores,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

class AsistenciaApp extends StatelessWidget {
  const AsistenciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final Widget inicio;
    if (!Api.i.haySesion) {
      inicio = const IngresoPantalla();
    } else if (Api.i.esAdmin) {
      inicio = const InicioAdminPantalla();
    } else {
      inicio = const InicioAsistentePantalla();
    }
    return MaterialApp(
      navigatorKey: navegador,
      title: 'Asistencia Asamblea',
      debugShowCheckedModeBanner: false,
      theme: tema(Brightness.light),
      darkTheme: tema(Brightness.dark),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: inicio,
    );
  }
}
