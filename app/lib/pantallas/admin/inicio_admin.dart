import 'package:flutter/material.dart';

import '../../servicios/api.dart';
import '../../servicios/tiempo_real.dart';
import '../../tema.dart';
import '../../util.dart';
import '../consulta_local.dart';
import '../salir.dart';
import 'asambleas_tab.dart';
import 'asistencia_tab.dart';
import 'locales_tab.dart';
import 'quorum_tab.dart';

/// Panel de la administradora.
class InicioAdminPantalla extends StatefulWidget {
  const InicioAdminPantalla({super.key});

  @override
  State<InicioAdminPantalla> createState() => _InicioAdminPantallaState();
}

class _Destino {
  final String titulo;
  final IconData icono;
  final IconData iconoActivo;
  const _Destino(this.titulo, this.icono, this.iconoActivo);
}

const _destinos = [
  _Destino('Quórum', Icons.pie_chart_outline, Icons.pie_chart),
  _Destino('Consultar', Icons.search, Icons.manage_search),
  _Destino('Asistencia', Icons.fact_check_outlined, Icons.fact_check),
  _Destino('Locales', Icons.storefront_outlined, Icons.storefront),
  _Destino('Asambleas', Icons.event_outlined, Icons.event),
];

class _InicioAdminPantallaState extends State<InicioAdminPantalla> {
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    TiempoReal.i.iniciar();
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

  @override
  Widget build(BuildContext context) {
    final paginas = [
      QuorumPestana(irAAsambleas: () => setState(() => _pestana = 4)),
      const ConsultaLocalPestana(),
      const AsistenciaPestana(),
      const LocalesPestana(),
      const AsambleasPestana(),
    ];
    final cuerpo = IndexedStack(index: _pestana, children: paginas);
    final ancho = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
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
            onSelected: (v) {
              if (v == 'clave') _cambiarClave();
              if (v == 'salir') cerrarSesion(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(Api.i.nombre ?? 'Administradora', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const PopupMenuItem(value: 'clave', child: Text('Cambiar contraseña')),
              const PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
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
      bottomNavigationBar: ancho
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
