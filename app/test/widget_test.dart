import 'package:flutter_test/flutter_test.dart';

import 'package:asistencia_asamblea/util.dart';

void main() {
  test('formato de decimales con coma', () {
    expect(decimal(0.8523), '0,8523');
    expect(decimal(3.5), '3,5');
    expect(decimal(12), '12');
    expect(decimal(51.234, decimales: 2), '51,23');
  });

  test('fecha en formato colombiano', () {
    expect(fechaBonita('2026-11-28'), '28/11/2026');
  });
}
