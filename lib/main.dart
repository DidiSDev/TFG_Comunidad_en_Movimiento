import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart'; 
import 'auth/inicio_sesion.dart'; 
import 'home/pantalla_principal.dart'; 
import 'auth/registro.dart'; 
import 'auth/cambiar_contrasena.dart'; 
import 'auth/recuperar_contrasena.dart';
import 'package:intl/date_symbol_data_local.dart';


// IMPORTA la pantalla de StreetView y sus argumentos
import 'home/streetview_google.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Inicializar los datos de localización para las fechas
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');
  await initializeDateFormatting('fr');
  await initializeDateFormatting('de');
  
  runApp(const MiApp());
}

class MiApp extends StatelessWidget {
  const MiApp({super.key}); 

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comunidad en movimiento',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/pantalla_principal': (context) => const PantallaPrincipal(),
        '/registro': (context) => const PantallaRegistro(),
        '/recuperar_contrasena': (context) => const PantallaRecuperarContrasena(),
        '/cambiar_contrasena': (context) => const PantallaCambiarContrasena(),
        
        // Ruta extra para Street View
        '/streetview_google': (context) {
          // Para leer los argumentos al navegar:
          final args = ModalRoute.of(context)!.settings.arguments as StreetViewArguments;
          return StreetViewGoogle(args: args);
        },
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key}); 

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          return const PantallaPrincipal();
        } else {
          return const PantallaInicioSesion();
        }
      },
    );
  }
}
