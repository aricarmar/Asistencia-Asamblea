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
