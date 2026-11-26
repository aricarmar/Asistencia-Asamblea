import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nombre que aparece en la app.
const String nombreCopropiedad = 'Trebolis Capellanía';
const String tipoCopropiedad = 'Centro Comercial';

/// Colores tomados del logo de Trebolis Capellanía.
class Colores {
  static const lima = Color(0xFF8DC53C); // fondo del logo
  static const hoja = Color(0xFF6B8845); // hojas del trébol
  static const verde = Color(0xFF2F7D32); // botones y barra superior
  static const verdeOscuro = Color(0xFF0E462B); // texto "CAPELLANIA"
  static const verdeSuave = Color(0xFFE6F4D7);
  static const ambar = Color(0xFFE09B12);
  static const ambarSuave = Color(0xFFFFF1D6);
  static const rojo = Color(0xFFD93A3A);
  static const rojoSuave = Color(0xFFFDE2E2);
  static const pagina = Color(0xFFF3F6EF);
  static const texto = Color(0xFF1C2620);
  static const tenue = Color(0xFF6B776F);
}

/// Colores del modo oscuro.
class ColoresOscuros {
  static const pagina = Color(0xFF0E1511);
  static const superficie = Color(0xFF141E17);
  static const tarjeta = Color(0xFF1A2720);
  static const borde = Color(0xFF2C3D32);
  static const primario = Color(0xFF8DC53C);
}

/// Esquinas redondeadas (mismo estilo de la app del parqueadero).
class Radios {
  static const tarjeta = 24.0;
  static const fila = 20.0;
  static const campo = 30.0;
}

ThemeData construirTema(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final esquema = oscuro
      ? ColorScheme.fromSeed(
          seedColor: Colores.verde,
          brightness: Brightness.dark,
          primary: ColoresOscuros.primario,
          onPrimary: const Color(0xFF0E1511),
          secondary: Colores.lima,
          error: Colores.rojo,
          surface: ColoresOscuros.superficie,
        )
      : ColorScheme.fromSeed(
          seedColor: Colores.verde,
          brightness: Brightness.light,
          primary: Colores.verde,
          secondary: Colores.lima,
          error: Colores.rojo,
        );
  final colorTarjeta = oscuro ? ColoresOscuros.tarjeta : Colors.white;
  final colorBorde = oscuro ? ColoresOscuros.borde : const Color(0xFFD6DDD0);

  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: esquema,
    scaffoldBackgroundColor: oscuro ? ColoresOscuros.pagina : Colores.pagina,
    cardColor: colorTarjeta,
    canvasColor: oscuro ? ColoresOscuros.superficie : null,
    dividerColor: colorBorde,
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorTarjeta,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.tarjeta)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: oscuro ? const Color(0xFF132A1B) : Colores.verde,
      foregroundColor: Colors.white,
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const StadiumBorder())),
    segmentedButtonTheme: SegmentedButtonThemeData(style: SegmentedButton.styleFrom(shape: const StadiumBorder())),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: StadiumBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorTarjeta,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radios.campo)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.campo),
        borderSide: BorderSide(color: colorBorde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.campo),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.fila)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorTarjeta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.fila)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.fila)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: oscuro ? ColoresOscuros.superficie : Colors.white,
      indicatorShape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: oscuro ? ColoresOscuros.superficie : Colors.white,
      indicatorColor: oscuro ? const Color(0xFF2E4A25) : Colores.verdeSuave,
    ),
  );
}

/// Modo claro / oscuro. Se guarda en el teléfono o navegador.
class ControladorTema extends ValueNotifier<ThemeMode> {
  ControladorTema() : super(ThemeMode.light);

  static const _clave = 'modo_tema';

  bool get esOscuro => value == ThemeMode.dark;

  Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      value = p.getString(_clave) == 'oscuro' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      value = ThemeMode.light;
    }
  }

  Future<void> alternar() async {
    value = esOscuro ? ThemeMode.light : ThemeMode.dark;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_clave, esOscuro ? 'oscuro' : 'claro');
    } catch (_) {}
  }
}

final controladorTema = ControladorTema();

/// Botón de sol / luna para cambiar entre modo claro y oscuro.
class BotonTema extends StatelessWidget {
  final Color? color;
  const BotonTema({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controladorTema,
      builder: (context, modo, _) {
        final oscuro = modo == ThemeMode.dark;
        return IconButton(
          tooltip: oscuro ? 'Modo claro' : 'Modo oscuro',
          color: color,
          onPressed: controladorTema.alternar,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (hijo, animacion) => RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1).animate(animacion),
              child: FadeTransition(opacity: animacion, child: hijo),
            ),
            child: Icon(
              oscuro ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              key: ValueKey(oscuro),
            ),
          ),
        );
      },
    );
  }
}

/// Logo de Trebolis Capellanía.
class LogoTrebolis extends StatelessWidget {
  final double ancho;
  const LogoTrebolis({super.key, this.ancho = 200});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: ancho,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Fondo con degradado verde (pantallas de ingreso).
BoxDecoration fondoDegradado(BuildContext context) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: oscuro
          ? const [Color(0xFF0A140D), Color(0xFF1F4A26)]
          : const [Colores.verde, Colores.lima],
    ),
  );
}
