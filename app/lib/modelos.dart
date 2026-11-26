double _decimal(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _entero(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _texto(dynamic v) => v?.toString();

class Persona {
  final String nombre;
  final String cedula;
  final String? registradoPor;

  Persona({required this.nombre, required this.cedula, this.registradoPor});

  static Persona? desde(dynamic j) {
    if (j is! Map) return null;
    return Persona(
      nombre: _texto(j['nombre']) ?? '',
      cedula: _texto(j['cedula']) ?? '',
      registradoPor: _texto(j['registrado_por']),
    );
  }
}

class Asistencia {
  final int id;
  final String tipo;
  final String nombre;
  final String cedula;
  final double coeficiente;
  final String hora;
  final String registradoPor;
  final String? numero;

  Asistencia({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.cedula,
    required this.coeficiente,
    required this.hora,
    required this.registradoPor,
    this.numero,
  });

  bool get esApoderado => tipo == 'apoderado';
  String get tipoTexto => esApoderado ? 'Apoderado' : 'Propietario';
  String get origenTexto => registradoPor == 'administradora' ? 'Administradora' : 'App';

  static Asistencia? desde(dynamic j) {
    if (j is! Map) return null;
    return Asistencia(
      id: _entero(j['id']),
      tipo: _texto(j['tipo']) ?? 'propietario',
      nombre: _texto(j['nombre']) ?? '',
      cedula: _texto(j['cedula']) ?? '',
      coeficiente: _decimal(j['coeficiente']),
      hora: _texto(j['hora']) ?? '',
      registradoPor: _texto(j['registrado_por']) ?? 'asistente',
      numero: _texto(j['numero']),
    );
  }
}

class Local {
  final int id;
  final String numero;
  final double coeficiente;
  final Persona propietario;
  final Persona? apoderado;
  final bool activo;
  final Asistencia? asistencia;

  Local({
    required this.id,
    required this.numero,
    required this.coeficiente,
    required this.propietario,
    required this.apoderado,
    required this.activo,
    required this.asistencia,
  });

  bool get presente => asistencia != null;

  factory Local.desde(Map<String, dynamic> j) => Local(
        id: _entero(j['id']),
        numero: _texto(j['numero']) ?? '',
        coeficiente: _decimal(j['coeficiente']),
        propietario: Persona.desde(j['propietario']) ?? Persona(nombre: '', cedula: ''),
        apoderado: Persona.desde(j['apoderado']),
        activo: j['activo'] != false,
        asistencia: Asistencia.desde(j['asistencia']),
      );
}

class Asamblea {
  final int id;
  final String nombre;
  final String fecha;
  final String estado;
  final String? horaApertura;
  final String? horaCierre;
  final int asistentes;

  Asamblea({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.estado,
    this.horaApertura,
    this.horaCierre,
    this.asistentes = 0,
  });

  bool get abierta => estado == 'abierta';
  bool get cerrada => estado == 'cerrada';
  String get estadoTexto => abierta ? 'Abierta' : (cerrada ? 'Cerrada' : 'Sin abrir');

  static Asamblea? desde(dynamic j) {
    if (j is! Map) return null;
    return Asamblea(
      id: _entero(j['id']),
      nombre: _texto(j['nombre']) ?? '',
      fecha: _texto(j['fecha']) ?? '',
      estado: _texto(j['estado']) ?? 'creada',
      horaApertura: _texto(j['hora_apertura']),
      horaCierre: _texto(j['hora_cierre']),
      asistentes: _entero(j['asistentes']),
    );
  }
}

class Quorum {
  final Asamblea? asamblea;
  final int totalLocales;
  final double coeficienteTotal;
  final int localesPresentes;
  final int propietarios;
  final int apoderados;
  final double coeficientePresente;
  final double porcentaje;
  final bool hayQuorum;

  Quorum({
    required this.asamblea,
    required this.totalLocales,
    required this.coeficienteTotal,
    required this.localesPresentes,
    required this.propietarios,
    required this.apoderados,
    required this.coeficientePresente,
    required this.porcentaje,
    required this.hayQuorum,
  });

  factory Quorum.desde(Map<String, dynamic> j) => Quorum(
        asamblea: Asamblea.desde(j['asamblea']),
        totalLocales: _entero(j['total_locales']),
        coeficienteTotal: _decimal(j['coeficiente_total']),
        localesPresentes: _entero(j['locales_presentes']),
        propietarios: _entero(j['propietarios']),
        apoderados: _entero(j['apoderados']),
        coeficientePresente: _decimal(j['coeficiente_presente']),
        porcentaje: _decimal(j['porcentaje']),
        hayQuorum: j['hay_quorum'] == true,
      );
}

class ResultadoOpcion {
  final int indice;
  final String texto;
  final int votos;
  final double coeficiente;
  final double porcentajePresentes;
  final double porcentajeVotos;
  final double porcentajeTotal;

  ResultadoOpcion({
    required this.indice,
    required this.texto,
    required this.votos,
    required this.coeficiente,
    required this.porcentajePresentes,
    required this.porcentajeVotos,
    required this.porcentajeTotal,
  });

  factory ResultadoOpcion.desde(Map j) => ResultadoOpcion(
        indice: _entero(j['indice']),
        texto: _texto(j['texto']) ?? '',
        votos: _entero(j['votos']),
        coeficiente: _decimal(j['coeficiente']),
        porcentajePresentes: _decimal(j['porcentaje_presentes']),
        porcentajeVotos: _decimal(j['porcentaje_votos']),
        porcentajeTotal: _decimal(j['porcentaje_total']),
      );
}

class Resultados {
  final List<ResultadoOpcion> opciones;
  final int votaronLocales;
  final double votaronCoeficiente;
  final int presentesLocales;
  final double presentesCoeficiente;
  final int faltanLocales;
  final double faltanCoeficiente;
  final int? ganadora;

  Resultados({
    required this.opciones,
    required this.votaronLocales,
    required this.votaronCoeficiente,
    required this.presentesLocales,
    required this.presentesCoeficiente,
    required this.faltanLocales,
    required this.faltanCoeficiente,
    required this.ganadora,
  });

  static Resultados? desde(dynamic j) {
    if (j is! Map) return null;
    return Resultados(
      opciones: (j['opciones'] as List? ?? const []).whereType<Map>().map(ResultadoOpcion.desde).toList(),
      votaronLocales: _entero(j['votaron_locales']),
      votaronCoeficiente: _decimal(j['votaron_coeficiente']),
      presentesLocales: _entero(j['presentes_locales']),
      presentesCoeficiente: _decimal(j['presentes_coeficiente']),
      faltanLocales: _entero(j['faltan_locales']),
      faltanCoeficiente: _decimal(j['faltan_coeficiente']),
      ganadora: j['ganadora'] == null ? null : _entero(j['ganadora']),
    );
  }
}

class Pregunta {
  final int id;
  final int numero;
  final String texto;
  final List<String> opciones;
  final String estado;
  final String? horaApertura;
  final String? horaCierre;
  final Resultados? resultados;

  Pregunta({
    required this.id,
    required this.numero,
    required this.texto,
    required this.opciones,
    required this.estado,
    this.horaApertura,
    this.horaCierre,
    this.resultados,
  });

  bool get abierta => estado == 'abierta';
  bool get cerrada => estado == 'cerrada';
  bool get sinAbrir => estado == 'creada';
  String get estadoTexto => abierta ? 'Votación abierta' : (cerrada ? 'Cerrada' : 'Sin abrir');

  static Pregunta? desde(dynamic j) {
    if (j is! Map) return null;
    return Pregunta(
      id: _entero(j['id']),
      numero: _entero(j['numero']),
      texto: _texto(j['texto']) ?? '',
      opciones: (j['opciones'] as List? ?? const []).map((e) => '$e').toList(),
      estado: _texto(j['estado']) ?? 'creada',
      horaApertura: _texto(j['hora_apertura']),
      horaCierre: _texto(j['hora_cierre']),
      resultados: Resultados.desde(j['resultados']),
    );
  }
}

/// Lo que ve un propietario o apoderado en la pestaña Votación.
class VotacionActual {
  final Asamblea? asamblea;
  final Pregunta? pregunta;
  final Pregunta? ultima;
  final bool puedeVotar;
  final String? motivo;
  final int? miVoto;
  final String? horaMiVoto;
  final String? localNumero;
  final double coeficiente;

  VotacionActual({
    required this.asamblea,
    required this.pregunta,
    required this.ultima,
    required this.puedeVotar,
    required this.motivo,
    required this.miVoto,
    required this.horaMiVoto,
    required this.localNumero,
    required this.coeficiente,
  });

  factory VotacionActual.desde(Map<String, dynamic> j) {
    final voto = j['mi_voto'];
    return VotacionActual(
      asamblea: Asamblea.desde(j['asamblea']),
      pregunta: Pregunta.desde(j['pregunta']),
      ultima: Pregunta.desde(j['ultima']),
      puedeVotar: j['puede_votar'] == true,
      motivo: _texto(j['motivo']),
      miVoto: voto is Map ? _entero(voto['opcion']) : null,
      horaMiVoto: voto is Map ? _texto(voto['hora']) : null,
      localNumero: _texto(j['local_numero']),
      coeficiente: _decimal(j['coeficiente']),
    );
  }
}
