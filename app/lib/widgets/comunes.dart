import 'package:flutter/material.dart';

import '../modelos.dart';
import '../util.dart';

/// Centra el contenido y limita el ancho en pantallas grandes (web).
class Contenedor extends StatelessWidget {
  final Widget child;
  final double anchoMaximo;
  const Contenedor({super.key, required this.child, this.anchoMaximo = 640});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: anchoMaximo), child: child),
    );
  }
}

class Cargando extends StatelessWidget {
  final String texto;
  const Cargando({super.key, this.texto = 'Cargando...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(texto),
        ],
      ),
    );
  }
}

class MensajeEstado extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? detalle;
  final String? textoBoton;
  final VoidCallback? alPresionar;
  final bool error;

  const MensajeEstado({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle,
    this.textoBoton,
    this.alPresionar,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: error ? colores.error : colores.primary),
            const SizedBox(height: 12),
            Text(titulo, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (detalle != null) ...[
              const SizedBox(height: 6),
              Text(detalle!, textAlign: TextAlign.center, style: TextStyle(color: colores.onSurfaceVariant)),
            ],
            if (textoBoton != null && alPresionar != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: alPresionar, child: Text(textoBoton!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorReintentar extends StatelessWidget {
  final String mensaje;
  final VoidCallback alReintentar;
  const ErrorReintentar({super.key, required this.mensaje, required this.alReintentar});

  @override
  Widget build(BuildContext context) {
    return MensajeEstado(
      icono: Icons.cloud_off_outlined,
      titulo: 'No se pudo cargar',
      detalle: mensaje,
      textoBoton: 'Reintentar',
      alPresionar: alReintentar,
      error: true,
    );
  }
}

/// Aviso de color (verde = bien, ámbar = atención, rojo = error).
class Aviso extends StatelessWidget {
  final IconData icono;
  final String texto;
  final String? detalle;
  final Color color;
  const Aviso({super.key, required this.icono, required this.texto, this.detalle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detalle != null) ...[
                  const SizedBox(height: 4),
                  Text(detalle!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const Color verdeOk = Color(0xFF2E7D32);
const Color ambar = Color(0xFFB26A00);

/// Opción grande para tocar (en vez de botones de radio pequeños).
class OpcionSeleccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final bool seleccionada;
  final VoidCallback alTocar;

  const OpcionSeleccion({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    required this.seleccionada,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: seleccionada ? colores.primaryContainer : colores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: alTocar,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: seleccionada ? colores.primary : Colors.transparent, width: 2),
            ),
            child: Row(
              children: [
                Icon(icono, color: seleccionada ? colores.primary : colores.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      if (subtitulo != null) Text(subtitulo!, style: TextStyle(color: colores.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(
                  seleccionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: seleccionada ? colores.primary : colores.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila "Etiqueta: valor" dentro de las tarjetas.
class Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final IconData? icono;
  const Dato({super.key, required this.etiqueta, required this.valor, this.icono});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 20, color: colores.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant)),
                Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta con los datos de un local: coeficiente, propietario y apoderado con cédula.
class TarjetaLocal extends StatelessWidget {
  final Local local;
  final bool mostrarAsistencia;
  final List<Widget> acciones;

  const TarjetaLocal({super.key, required this.local, this.mostrarAsistencia = true, this.acciones = const []});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final a = local.asistencia;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colores.primary,
                  child: Icon(Icons.storefront, color: colores.onPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local ${local.numero}', style: Theme.of(context).textTheme.titleLarge),
                      Text('Coeficiente: ${decimal(local.coeficiente)} %',
                          style: TextStyle(color: colores.onSurfaceVariant, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Dato(
              icono: Icons.person,
              etiqueta: 'Propietario',
              valor: '${local.propietario.nombre}\nC.C. ${local.propietario.cedula}',
            ),
            if (local.apoderado != null)
              Dato(
                icono: Icons.badge_outlined,
                etiqueta: local.apoderado!.registradoPor == 'apoderado'
                    ? 'Apoderado (registrado desde la app)'
                    : 'Apoderado',
                valor: '${local.apoderado!.nombre}\nC.C. ${local.apoderado!.cedula}',
              ),
            if (mostrarAsistencia) ...[
              const SizedBox(height: 10),
              a != null
                  ? Aviso(
                      icono: Icons.check_circle,
                      color: verdeOk,
                      texto: 'Presente desde las ${a.hora}',
                      detalle: '${a.tipoTexto}: ${a.nombre} (C.C. ${a.cedula})',
                    )
                  : Aviso(
                      icono: Icons.schedule,
                      color: ambar,
                      texto: 'No ha registrado asistencia',
                    ),
            ],
            if (acciones.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: acciones),
            ],
          ],
        ),
      ),
    );
  }
}

/// Resumen del quórum por coeficiente.
class TarjetaQuorum extends StatelessWidget {
  final Quorum quorum;
  const TarjetaQuorum({super.key, required this.quorum});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final q = quorum;
    final color = q.hayQuorum ? verdeOk : ambar;
    final valor = (q.porcentaje / 100).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            if (q.asamblea != null) ...[
              Text(q.asamblea!.nombre, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('${fechaBonita(q.asamblea!.fecha)} · ${q.asamblea!.estadoTexto}',
                  style: TextStyle(color: colores.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: valor.toDouble(),
                    strokeWidth: 14,
                    backgroundColor: colores.surfaceContainerHighest,
                    color: color,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${decimal(q.porcentaje, decimales: 2)} %',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('del coeficiente', style: TextStyle(color: colores.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Chip(
              avatar: Icon(q.hayQuorum ? Icons.check_circle : Icons.hourglass_bottom, color: color),
              label: Text(q.hayQuorum ? 'Hay quórum' : 'Aún no hay quórum (se necesita más del 50 %)'),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                _Cifra(titulo: 'Locales presentes', valor: '${q.localesPresentes} de ${q.totalLocales}'),
                _Cifra(titulo: 'Propietarios', valor: '${q.propietarios}'),
                _Cifra(titulo: 'Apoderados', valor: '${q.apoderados}'),
                _Cifra(
                  titulo: 'Coeficiente presente',
                  valor: '${decimal(q.coeficientePresente)} de ${decimal(q.coeficienteTotal)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  final String titulo;
  final String valor;
  const _Cifra({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(valor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(titulo, style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant)),
        ],
      ),
    );
  }
}
