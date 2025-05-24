// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comunidad_en_movimiento/main.dart'; // Asegúrate de que la ruta es correcta

void main() {
  testWidgets('Pantalla de Inicio de Sesión se muestra correctamente', (WidgetTester tester) async {
    // Construir la aplicación
    await tester.pumpWidget(const MiApp());

    // Esperar a que se construya la UI
    await tester.pumpAndSettle();

    // Verificar que la pantalla de inicio de sesión está presente
    expect(find.text('Inicio de Sesión'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2)); // Correo y contraseña
    expect(find.text('Registrarse'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });
}
