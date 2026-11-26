import 'package:flutter/material.dart';

import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../tema.dart';
import '../../util.dart';
import '../consulta_local.dart';
import '../salir.dart';
import 'asambleas_tab.dart';
import 'asistencia_tab.dart';
import 'compartir.dart';
import 'locales_tab.dart';
import 'quorum_tab.dart';
import 'votaciones_tab.dart';

/// Panel de la administradora y de logística.
class InicioAdminPantalla extends StatefulWidget {
  const InicioAdminPantalla({super.key});

  @override
  State<InicioAdminPantalla> createState() => _InicioAdminPantallaState();
}

class _Destino {
  final String clave;
  final String titulo;
  final IconData icono;
  final IconData iconoActivo;
  const _Destino(this.clave, this.titulo, this.icono, this.iconoActivo);
}

const _quorum = _Destino('quorum', 'Quórum', Icons.pie_chart_outline, Icons.pie_chart);
const _consultar = _Destino('consultar', 'Consultar', Icons.search, Icons.manage_search);
const _asistencia = _Destino('asistencia', 'Asistencia', Icons.fact_check_outlined, Icons.fact_check);
const _votaciones = _Destino('votaciones', 'Votaciones', Icons.how_to_vote_outlined, Icons.how_to_vote);
const _locales = _Destino('locales', 'Locales', Icons.storefront_outlined, Icons.storefront);
const _asambleas = _Destino('asambleas', 'Asambleas', Icons.event_outlined, Icons.event);

class _InicioAdminPantallaState extends State<InicioAdminPantalla> {
  int _pestana = 0;
  late final List<_Destino> _destinos;
  final _andamio = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    TiempoReal.i.iniciar();
    _destinos = Api.i.esAdmin
        ? const [_quorum, _consultar, _asistencia, _votaciones, _locales, _asambleas]
        : const [_quorum, _consultar, _asistencia, _votaciones];
  }

  void _ir(String clave) {
    final i = _destinos.indexWhere((d) => d.clave == clave);
    if (i >= 0) setState(() => _pestana = i);
  }

  Widget _pagina(_Destino d) {
    switch (d.clave) {
      case 'quorum':
        return QuorumPestana(irAAsambleas: Api.i.esAdmin ? () => _ir('asambleas') : null);
      case 'consultar':
        return const ConsultaLocalPestana();
      case 'asistencia':
        return const AsistenciaPestana();
      case 'votaciones':
        return const VotacionesPestana();
      case 'locales':
        return const LocalesPestana();
      default:
        return const AsambleasPestana();
    }
  }

  Future<void> _cambiarClave() async {
    final actual = TextEditingController();
    final nueva = TextEditingController();
    final guardar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: actual, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
            const SizedBox(height: 12),
            TextField(
              controller: nueva,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña (mínimo 6)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    try {
      await Api.i.put('/api/admin/clave', {'actual': actual.text, 'nueva': nueva.text});
      if (mounted) mostrarMensaje(context, 'Contraseña cambiada.');
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  /// La administradora crea la cuenta de logística o le cambia la contraseña.
  Future<void> _usuarioLogistica() async {
    Map<String, dynamic> datos;
    try {
      datos = await Api.i.get('/api/admin/logistica');
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    if (!mounted) return;
    final existe = datos['existe'] == true;
    final nombre = TextEditingController(text: '${datos['nombre'] ?? ''}'.isEmpty ? 'Logística' : '${datos['nombre']}');
    final clave = TextEditingController();
    final guardar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Usuario de logística'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existe
                    ? 'La persona de logística entra con el usuario «logistica». Escribe una contraseña nueva solo si quieres cambiarla.'
                    : 'Crea la cuenta para la persona de logística. Entrará por «Ingreso de administración y logística» con el usuario «logistica».',
              ),
              const SizedBox(height: 14),
              TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre de quien hace la logística')),
              const SizedBox(height: 12),
              TextField(
                controller: clave,
                decoration: InputDecoration(labelText: existe ? 'Contraseña nueva (opcional)' : 'Contraseña (mínimo 6)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    try {
      await Api.i.put('/api/admin/logistica', {'nombre': nombre.text.trim(), 'clave': clave.text});
      if (mounted) {
        mostrarMensaje(
          context,
          clave.text.isEmpty ? 'Datos de logística guardados.' : 'Listo. Usuario: logistica · Contraseña: ${clave.text}',
        );
      }
    } on ApiError catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _cargarRespaldo() async {
    final ok = await confirmar(
      context,
      titulo: 'Cargar respaldo',
      mensaje: 'Se abrirá una página para escoger el archivo de respaldo (.json). '
          'Al cargarlo se reemplazan todos los locales, asambleas, asistencia y votaciones de este servidor.\n\n'
          'Úsalo para pasar los datos de la nube al computador antes de una asamblea sin internet, '
          'o para devolver los resultados a la nube después.',
      accion: 'Continuar',
    );
    if (ok && mounted) abrirEnlace(context, Api.i.informe('/api/admin/respaldo/importar'));
  }

  void _opcion(String v) {
    switch (v) {
      case 'compartir':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CompartirPantalla()));
        break;
      case 'respaldo':
        abrirEnlace(context, Api.i.informe('/api/admin/respaldo'));
        break;
      case 'cargar':
        _cargarRespaldo();
        break;
      case 'logistica':
        _usuarioLogistica();
        break;
      case 'clave':
        _cambiarClave();
        break;
      case 'salir':
        cerrarSesion(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    final usarMenuLateral = !ancho && _destinos.length > 5;
    final cuerpo = IndexedStack(index: _pestana, children: [for (final d in _destinos) _pagina(d)]);
    final rolTexto = Api.i.esAdmin ? 'Administradora' : 'Logística';

    return Scaffold(
      key: _andamio,
      appBar: AppBar(
        titleSpacing: ancho ? 16 : null,
        title: Row(
          children: [
            if (ancho) ...[
              const LogoTrebolis(ancho: 52),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                ancho ? '$nombreCopropiedad · ${_destinos[_pestana].titulo}' : _destinos[_pestana].titulo,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const BotonTema(),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.account_circle),
            onSelected: _opcion,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Api.i.nombre ?? rolTexto, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(rolTexto, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'compartir',
                child: ListTile(leading: Icon(Icons.qr_code_2), title: Text('Compartir la app'), contentPadding: EdgeInsets.zero),
              ),
              if (Api.i.esAdmin)
                const PopupMenuItem(
                  value: 'logistica',
                  child: ListTile(leading: Icon(Icons.badge_outlined), title: Text('Usuario de logística'), contentPadding: EdgeInsets.zero),
                ),
              if (Api.i.esAdmin)
                const PopupMenuItem(
                  value: 'respaldo',
                  child: ListTile(leading: Icon(Icons.download), title: Text('Descargar respaldo'), contentPadding: EdgeInsets.zero),
                ),
              if (Api.i.esAdmin)
                const PopupMenuItem(
                  value: 'cargar',
                  child: ListTile(leading: Icon(Icons.upload), title: Text('Cargar respaldo'), contentPadding: EdgeInsets.zero),
                ),
              const PopupMenuItem(
                value: 'clave',
                child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Cambiar contraseña'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'salir',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      drawer: usarMenuLateral
          ? NavigationDrawer(
              selectedIndex: _pestana,
              onDestinationSelected: (i) {
                setState(() => _pestana = i);
                _andamio.currentState?.closeDrawer();
              },
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LogoTrebolis(ancho: 130),
                      const SizedBox(height: 12),
                      Text(Api.i.nombre ?? rolTexto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(rolTexto),
                    ],
                  ),
                ),
                const Divider(indent: 20, endIndent: 20),
                for (final d in _destinos)
                  NavigationDrawerDestination(
                    icon: Icon(d.icono),
                    selectedIcon: Icon(d.iconoActivo),
                    label: Text(d.titulo),
                  ),
              ],
            )
          : null,
      body: ancho
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _pestana,
                  onDestinationSelected: (i) => setState(() => _pestana = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinos)
                      NavigationRailDestination(icon: Icon(d.icono), selectedIcon: Icon(d.iconoActivo), label: Text(d.titulo)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: cuerpo),
              ],
            )
          : cuerpo,
      bottomNavigationBar: ancho || usarMenuLateral
          ? null
          : NavigationBar(
              selectedIndex: _pestana,
              onDestinationSelected: (i) => setState(() => _pestana = i),
              destinations: [
                for (final d in _destinos)
                  NavigationDestination(icon: Icon(d.icono), selectedIcon: Icon(d.iconoActivo), label: d.titulo),
              ],
            ),
    );
  }
}
