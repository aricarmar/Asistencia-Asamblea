import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final String mensaje;
  final int? estado;
  ApiError(this.mensaje, [this.estado]);

  @override
  String toString() => mensaje;
}

/// Conexión con la API (Render) y datos de la sesión guardados en el teléfono o navegador.
class Api {
  Api._();
  static final Api i = Api._();

  /// Se puede cambiar al compilar: flutter build apk --dart-define=API_URL=https://...
  static const String urlPorDefecto = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://asistencia-asamblea-api.onrender.com',
  );

  String baseUrl = urlPorDefecto;
  String? token;
  String? rol;
  String? nombre;

  /// Se llama cuando el servidor dice que la sesión ya no sirve.
  void Function()? alVencerSesion;

  bool get esAdmin => rol == 'administradora';
  bool get haySesion => token != null && token!.isNotEmpty;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('servidor') ?? urlPorDefecto;
    token = p.getString('token');
    rol = p.getString('rol');
    nombre = p.getString('nombre');
  }

  Future<void> guardarSesion(Map<String, dynamic> datos) async {
    token = datos['token'] as String?;
    rol = datos['rol'] as String?;
    nombre = datos['nombre'] as String?;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token ?? '');
    await p.setString('rol', rol ?? '');
    await p.setString('nombre', nombre ?? '');
  }

  Future<void> cerrarSesion() async {
    token = null;
    rol = null;
    nombre = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('rol');
    await p.remove('nombre');
  }

  Future<void> cambiarServidor(String url) async {
    var limpio = url.trim();
    while (limpio.endsWith('/')) {
      limpio = limpio.substring(0, limpio.length - 1);
    }
    baseUrl = limpio.isEmpty ? urlPorDefecto : limpio;
    final p = await SharedPreferences.getInstance();
    await p.setString('servidor', baseUrl);
  }

  Uri uri(String ruta, [Map<String, String>? consulta]) {
    var base = baseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final u = Uri.parse('$base$ruta');
    if (consulta == null || consulta.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...consulta});
  }

  /// Enlace para abrir en el navegador (Excel o acta) con la sesión incluida.
  Uri informe(String ruta, {int? asambleaId}) => uri(ruta, {
        'token': token ?? '',
        if (asambleaId != null) 'asamblea_id': '$asambleaId',
      });

  Future<Map<String, dynamic>> get(String ruta, [Map<String, String>? consulta]) =>
      _enviar('GET', ruta, consulta: consulta);

  Future<Map<String, dynamic>> post(String ruta, [Object? cuerpo]) => _enviar('POST', ruta, cuerpo: cuerpo ?? {});

  Future<Map<String, dynamic>> put(String ruta, Object cuerpo) => _enviar('PUT', ruta, cuerpo: cuerpo);

  Future<Map<String, dynamic>> delete(String ruta) => _enviar('DELETE', ruta);

  Future<Map<String, dynamic>> _enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
    Map<String, String>? consulta,
  }) async {
    final peticion = http.Request(metodo, uri(ruta, consulta));
    peticion.headers['Content-Type'] = 'application/json';
    if (haySesion) peticion.headers['Authorization'] = 'Bearer $token';
    if (cuerpo != null) peticion.body = jsonEncode(cuerpo);

    http.Response respuesta;
    try {
      final enviada = await peticion.send().timeout(const Duration(seconds: 75));
      respuesta = await http.Response.fromStream(enviada);
    } on TimeoutException {
      throw ApiError(
        'El servidor tardó demasiado en responder. Si es el primer ingreso del día, espera un minuto e intenta otra vez.',
      );
    } catch (_) {
      throw ApiError('No hay conexión con el servidor. Revisa tu internet e intenta otra vez.');
    }

    Map<String, dynamic> datos = {};
    try {
      final d = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (d is Map<String, dynamic>) datos = d;
    } catch (_) {}

    if (respuesta.statusCode >= 400) {
      if (respuesta.statusCode == 401 && haySesion) alVencerSesion?.call();
      throw ApiError(datos['error']?.toString() ?? 'Error ${respuesta.statusCode}', respuesta.statusCode);
    }
    return datos;
  }
}
