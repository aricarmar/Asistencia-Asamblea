import 'package:flutter/material.dart';

import '../servicios/api.dart';
import '../servicios/tiempo_real.dart';
import '../util.dart';
import 'ingreso.dart';

Future<void> cerrarSesion(BuildContext context, {bool preguntar = true}) async {
  if (preguntar) {
    final ok = await confirmar(
      context,
      titulo: 'Cerrar sesión',
      mensaje: '¿Quieres salir? Tu asistencia sigue registrada.',
      accion: 'Salir',
    );
    if (!ok) return;
  }
  await Api.i.cerrarSesion();
  TiempoReal.i.detener();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const IngresoPantalla()),
    (_) => false,
  );
}
