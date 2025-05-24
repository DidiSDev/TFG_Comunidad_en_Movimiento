import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PantallaCambiarContrasena extends StatefulWidget {
  const PantallaCambiarContrasena({super.key}); // Constructor const

  @override
  _PantallaCambiarContrasenaState createState() =>
      _PantallaCambiarContrasenaState();
}

class _PantallaCambiarContrasenaState
    extends State<PantallaCambiarContrasena> {
  final TextEditingController _contrasenaActualController =
      TextEditingController();
  final TextEditingController _nuevaContrasenaController =
      TextEditingController();
  final TextEditingController _confirmarContrasenaController =
      TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _cambiarContrasena() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null && user.email != null) {
        // Reautenticar al usuario
        String email = user.email!;
        String contrasenaActual = _contrasenaActualController.text.trim();
        String nuevaContrasena = _nuevaContrasenaController.text.trim();

        // Crear credenciales
        AuthCredential credential =
            EmailAuthProvider.credential(email: email, password: contrasenaActual);

        // Reautenticación
        await user.reauthenticateWithCredential(credential);

        // Cambiar contraseña
        await user.updatePassword(nuevaContrasena);

        // Mostrar mensaje de OK
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada exitosamente.')),
        );

        // Limpiar campos
        _contrasenaActualController.clear();
        _nuevaContrasenaController.clear();
        _confirmarContrasenaController.clear();

        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró al usuario.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String mensaje = 'Error al cambiar la contraseña.';
      if (e.code == 'wrong-password') {
        mensaje = 'Contraseña actual incorrecta.';
      } else if (e.code == 'weak-password') {
        mensaje = 'La nueva contraseña es demasiado débil.';
      } else if (e.code == 'requires-recent-login') {
        mensaje = 'Es necesario iniciar sesión nuevamente para cambiar la contraseña.';
        // Opcional: Redirigir al usuario a la pantalla de inicio de sesión
        // Navigator.pushReplacementNamed(context, '/inicio_sesion');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // Limpiar los controladores cuando el widget se elimine
    _contrasenaActualController.dispose();
    _nuevaContrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.purple[50], // fondo
      appBar: AppBar(
        title: const Text('Cambiar Contraseña'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Icono
            const SizedBox(height: 20),
            const Icon(
              Icons.lock,
              size: 100,
              color: Colors.purpleAccent,
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Campo de Contraseña act
                  TextFormField(
                    controller: _contrasenaActualController,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña Actual',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, ingresa tu contraseña actual.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Campo de Nueva Contraseña
                  TextFormField(
                    controller: _nuevaContrasenaController,
                    decoration: const InputDecoration(
                      labelText: 'Nueva Contraseña',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, ingresa tu nueva contraseña.';
                      }
                      if (value.length < 6) {
                        return 'La contraseña debe tener al menos 6 caracteres.'; // Pero libre
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Campo pa confirmar
                  TextFormField(
                    controller: _confirmarContrasenaController,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar Nueva Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, confirma tu nueva contraseña.';
                      }
                      if (value != _nuevaContrasenaController.text) {
                        return 'Las contraseñas no coinciden.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  // Botón de Cambiar Contraseña
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _cambiarContrasena,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.purpleAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2.0,
                              ),
                            )
                          : const Text(
                              'Cambiar Contraseña',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
