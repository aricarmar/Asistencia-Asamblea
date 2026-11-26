import 'package:flutter/material.dart';

import '../modelos.dart';
import '../tema.dart';
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

const Color verdeOk = Color(0xFF43A047);
const Color ambar = Colores.ambar;

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
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Colores.verde, Colores.lima]),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    local.numero,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local ${local.numero}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
            LayoutBuilder(
              builder: (context, restricciones) {
                final dos = restricciones.maxWidth < 560;
                final ancho = dos ? (restricciones.maxWidth - 10) / 2 : (restricciones.maxWidth - 30) / 4;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: ancho,
                      child: TarjetaEstadistica(
                        icono: Icons.storefront,
                        color: Colores.verde,
                        valor: '${q.localesPresentes} de ${q.totalLocales}',
                        etiqueta: 'Locales presentes',
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: TarjetaEstadistica(
                        icono: Icons.person,
                        color: const Color(0xFF1E88E5),
                        valor: '${q.propietarios}',
                        etiqueta: 'Propietarios',
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: TarjetaEstadistica(
                        icono: Icons.badge_outlined,
                        color: const Color(0xFF8E24AA),
                        valor: '${q.apoderados}',
                        etiqueta: 'Apoderados',
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: TarjetaEstadistica(
                        icono: Icons.pie_chart_outline,
                        color: Colores.ambar,
                        valor: '${decimal(q.coeficientePresente, decimales: 2)} %',
                        etiqueta: 'Coeficiente presente',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de cifra con efecto al pasar el mouse (igual que en la app del parqueadero).
class TarjetaEstadistica extends StatefulWidget {
  final IconData icono;
  final Color color;
  final String valor;
  final String etiqueta;
  final VoidCallback? alTocar;

  const TarjetaEstadistica({
    super.key,
    required this.icono,
    required this.color,
    required this.valor,
    required this.etiqueta,
    this.alTocar,
  });

  @override
  State<TarjetaEstadistica> createState() => _TarjetaEstadisticaState();
}

class _TarjetaEstadisticaState extends State<TarjetaEstadistica> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    const duracion = Duration(milliseconds: 180);
    final radio = BorderRadius.circular(Radios.fila);
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: AnimatedScale(
        scale: _encima ? 1.04 : 1,
        duration: duracion,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duracion,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: oscuro ? ColoresOscuros.superficie : Colores.pagina,
            borderRadius: radio,
            border: Border.all(color: _encima ? w.color : Colors.transparent, width: 2),
            boxShadow: _encima
                ? [BoxShadow(color: w.color.withAlpha(70), blurRadius: 16, offset: const Offset(0, 6))]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radio,
              onTap: w.alTocar,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: duracion,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: w.color.withAlpha(_encima ? 60 : 30), shape: BoxShape.circle),
                      child: Icon(w.icono, color: w.color, size: 22),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(w.valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    Text(
                      w.etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colores para las opciones de una votación.
const List<Color> coloresOpciones = [
  Color(0xFF43A047),
  Color(0xFFE53935),
  Color(0xFF757575),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFFFB8C00),
  Color(0xFF00897B),
  Color(0xFF6D4C41),
  Color(0xFF3949AB),
  Color(0xFFC0CA33),
];

Color colorOpcion(int indice) => coloresOpciones[indice % coloresOpciones.length];

/// Resultados de una votación: una barra por opción con votos y coeficiente.
class BarrasResultados extends StatelessWidget {
  final Resultados resultados;
  final bool mostrarFaltantes;
  const BarrasResultados({super.key, required this.resultados, this.mostrarFaltantes = true});

  @override
  Widget build(BuildContext context) {
    final r = resultados;
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in r.opciones) ...[
          Row(
            children: [
              Icon(
                r.ganadora == o.indice ? Icons.emoji_events : Icons.circle,
                size: r.ganadora == o.indice ? 20 : 12,
                color: r.ganadora == o.indice ? Colores.ambar : colorOpcion(o.indice),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  o.texto,
                  style: TextStyle(
                    fontWeight: r.ganadora == o.indice ? FontWeight.w900 : FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${decimal(o.porcentajePresentes, decimales: 2)} %',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (o.porcentajePresentes / 100).clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, valor, _) => LinearProgressIndicator(
                value: valor,
                minHeight: 14,
                color: colorOpcion(o.indice),
                backgroundColor: colores.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${o.votos} ${o.votos == 1 ? 'voto' : 'votos'} · coeficiente ${decimal(o.coeficiente)} % · '
            '${decimal(o.porcentajeTotal, decimales: 2)} % del total',
            style: TextStyle(color: colores.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
        ],
        if (mostrarFaltantes)
          Text(
            'Votaron ${r.votaronLocales} de ${r.presentesLocales} locales presentes'
            '${r.faltanLocales > 0 ? ' · faltan ${r.faltanLocales} (${decimal(r.faltanCoeficiente)} % de coeficiente)' : ''}',
            style: TextStyle(color: colores.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
