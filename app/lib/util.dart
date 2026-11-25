import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 0.8523 -> "0,8523"; 3.5 -> "3,5"; 12.0 -> "12"
String decimal(num? valor, {int decimales = 4}) {
  if (valor == null) return '';
  var t = valor.toStringAsFixed(decimales);
  if (t.contains('.')) {
    t = t.replaceAll(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  }
  return t.replaceAll('.', ',');
}

/// "2026-11-28" -> "28/11/2026"
String fechaBonita(String fecha) {
  final p = fecha.split('-');
  if (p.length != 3) return fecha;
  return '${p[2]}/${p[1]}/${p[0]}';
}

void mostrarMensaje(BuildContext context, String mensaje, {bool error = false}) {
  final colores = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: error ? colores.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Aceptar',
  bool peligrosa = false,
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
        FilledButton(
          style: peligrosa ? FilledButton.styleFrom(backgroundColor: Theme.of(contexto).colorScheme.error) : null,
          onPressed: () => Navigator.pop(contexto, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return respuesta == true;
}

Future<void> abrirEnlace(BuildContext context, Uri enlace) async {
  final ok = await launchUrl(enlace, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    mostrarMensaje(context, 'No se pudo abrir el enlace.', error: true);
  }
}
