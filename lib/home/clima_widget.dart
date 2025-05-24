import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'colores_personalizados.dart';
import 'traducciones.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/clima_notificaciones.dart';

class ClimaWidget extends StatefulWidget {
  final String modoDaltonismo;
  final String idiomaSeleccionado;
  final double? latitud;
  final double? longitud;

  const ClimaWidget({
    Key? key,
    required this.modoDaltonismo,
    required this.idiomaSeleccionado,
    this.latitud,
    this.longitud,
  }) : super(key: key);

  @override
  State<ClimaWidget> createState() => _ClimaWidgetState();
}

class _ClimaWidgetState extends State<ClimaWidget>
    with TickerProviderStateMixin {
  String _temperatura = '--';
  String _condicionClima = '--';
  String _velocidadViento = '--';
  String _ciudad = '--';
  String _fechaHora = '--';
  List<String> _horasLluvia = [];
  bool _cargando = true;
  bool _errorAlCargar = false;
  Timer? _timerReloj;

  // Datos para pronóstico extendido
  List<Map<String, dynamic>> _pronosticoExtendido = [];
  bool _mostrarPronosticoExtendido = false;

  /** VARIAS ANIMACIONES */
  // Animación para iconos
  late AnimationController _iconAnimationController;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;

  // Animación para transiciones
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Animación para el brillo en modo oscuro
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  // Historial de clima
  List<Map<String, dynamic>> _historialClima = [];
  bool _mostrarHistorial = false;

  // Notificaciones
  final ClimaNotificaciones _notificaciones = ClimaNotificaciones();

  // Modo oscuro
  bool _modoOscuro = false;
  Timer? _modoOscuroTimer;

  @override
  void initState() {
    super.initState();

    // Inicializar animaciones
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _iconScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: Curves.easeInOut,
    ));

    _iconRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.05,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: Curves.easeInOut,
    ));

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _shimmerAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_shimmerController);

    // Iniciar reloj y cargar datos
    _iniciarReloj();
    _cargarHistorial();
    _obtenerDatosClima();
    _verificarModoOscuro();

    // Iniciar notificaciones
    if (widget.latitud != null && widget.longitud != null) {
      _notificaciones.initialize(widget.idiomaSeleccionado).then((_) {
        _notificaciones.startMonitoring(
          widget.latitud!,
          widget.longitud!,
          widget.idiomaSeleccionado,
        );
      });
    }
  }

  @override
  void dispose() {
    _timerReloj?.cancel();
    _iconAnimationController.dispose();
    _slideController.dispose();
    _shimmerController.dispose();
    _modoOscuroTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ClimaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((widget.latitud != oldWidget.latitud ||
            widget.longitud != oldWidget.longitud) &&
        widget.latitud != null &&
        widget.longitud != null) {
      _obtenerDatosClima();

      // Actualizar monitoreo de notificaciones con nuevas coordenadas
      _notificaciones.startMonitoring(
        widget.latitud!,
        widget.longitud!,
        widget.idiomaSeleccionado,
      );
    }

    if (widget.idiomaSeleccionado != oldWidget.idiomaSeleccionado) {
      // Actualizar idioma de notificaciones
      _notificaciones.initialize(widget.idiomaSeleccionado);
    }
  }

  void _iniciarReloj() {
    // Actualiza la hora inmediatamente
    _actualizarHora();

    // timer para actualizar cada segundo
    _timerReloj = Timer.periodic(const Duration(seconds: 1), (timer) {
      _actualizarHora();
    });
  }

  void _actualizarHora() {
    final ahora = DateTime.now();
    final formato = DateFormat('dd/MM/yyyy HH:mm:ss');

    setState(() {
      _fechaHora = formato.format(ahora);
    });
  }

  void _verificarModoOscuro() {
    // Verificar la hora para activar/desactivar modo oscuro
    final hora = DateTime.now().hour;
    final esNoche =
        hora < 6 || hora >= 19; // Consideramos noche de 19:00 a 6:00 de forma fija de momento

    setState(() {
      _modoOscuro = esNoche;
    });

    // Configurar un timer para verificar cada 15 minutos
    _modoOscuroTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      final currentHour = DateTime.now().hour;
      final isNighttime = currentHour < 6 || currentHour >= 19;

      if (_modoOscuro != isNighttime) {
        setState(() {
          _modoOscuro = isNighttime;
        });
      }
    });
  }

  Future<void> _cargarHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historialJson = prefs.getString('historial_clima');

      if (historialJson != null) {
        final List<dynamic> decodedData = json.decode(historialJson);
        _historialClima = List<Map<String, dynamic>>.from(
            decodedData.map((item) => Map<String, dynamic>.from(item)));
      }
    } catch (e) {
      print('Error al cargar historial: $e');
    }
  }

  Future<void> _guardarEnHistorial(Map<String, dynamic> datosClima) async {
    try {
      // Añadir fecha actual
      datosClima['fecha'] = DateTime.now().toIso8601String();

      // Añadir al historial
      _historialClima.insert(0, datosClima);

      // Limitar a los últimos 30 días
      if (_historialClima.length > 30) {
        _historialClima = _historialClima.sublist(0, 30);
      }

      // Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('historial_clima', json.encode(_historialClima));
    } catch (e) {
      print('Error al guardar historial: $e');
    }
  }

  Future<void> _obtenerDatosClima() async {
    setState(() {
      _cargando = true;
      _errorAlCargar = false;
    });

    try {
      // Obtener ubicación actual si no se proporciona latitud/longitud
      double lat;
      double lng;

      if (widget.latitud != null && widget.longitud != null) {
        lat = widget.latitud!;
        lng = widget.longitud!;
      } else {
        // Obtener ubicación actual
        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = position.latitude;
        lng = position.longitude;
      }

      // Llamo a la función de nombre de la ciudad
      await _obtenerCiudad(lat, lng);

      // Datos del clima de la API Open-Meteo
      await _obtenerClimaDeOpenMeteo(lat, lng);

      // Animación de entrada
      _slideController.forward();

      setState(() {
        _cargando = false;
      });
    } catch (e) {
      print('Error al obtener clima: $e');
      setState(() {
        _cargando = false;
        _errorAlCargar = true;
      });
    }
  }

  Future<void> _obtenerCiudad(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark lugar = placemarks.first;
        String ciudad = lugar.locality ??
            lugar.subAdministrativeArea ??
            lugar.administrativeArea ??
            traducir('Ciudad no disponible', widget.idiomaSeleccionado);

        setState(() {
          _ciudad = ciudad;
        });
      }
    } catch (e) {
      print('Error al obtener ciudad: $e');
      setState(() {
        _ciudad = traducir('Ciudad no disponible', widget.idiomaSeleccionado);
      });
    }
  }

  // Según la documentación cambió a current_weather
  Future<void> _obtenerClimaDeOpenMeteo(double lat, double lng) async {
    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?'
          'latitude=$lat&longitude=$lng&'
          'current_weather=true&'
          'hourly=weathercode,temperature_2m,windspeed_10m,precipitation_probability&'
          'daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum&'
          'timezone=auto&'
          'forecast_days=7');

      final respuesta = await http.get(url);

      if (respuesta.statusCode == 200) {
        final data = json.decode(respuesta.body);

        // Obtener datos del clima actual
        final climaActual = data['current_weather'];
        final temperatura =
            climaActual['temperature']?.toStringAsFixed(1) ?? '--';
        final velocidadViento =
            climaActual['windspeed']?.toStringAsFixed(1) ?? '--';
        final codigoClima = climaActual['weathercode'] ?? 0;

        // Obtener datos horarios para pronóstico
        final datosHorarios = data['hourly'];
        final tiemposHorarios = datosHorarios['time'] as List;
        final codigosClimaHorarios = datosHorarios['weathercode'] as List;

        // Saco horas con lluvia para las próximas 24 horas
        _horasLluvia = _procesarHorasLluvia(
            tiemposHorarios.cast<String>(), codigosClimaHorarios.cast<num>());

        // Saco pronóstico extendido
        _procesarPronosticoExtendido(data['daily']);

        // Lo guardo en historial
        final datosParaHistorial = {
          'temperatura': temperatura,
          'velocidadViento': velocidadViento,
          'codigoClima': codigoClima,
          'ciudad': _ciudad,
        };

        await _guardarEnHistorial(datosParaHistorial);

        setState(() {
          _temperatura = temperatura;
          _velocidadViento = velocidadViento;
          _condicionClima = _traducirCodigoClima(codigoClima);
        });
      } else {
        print('Error en la API del clima: ${respuesta.statusCode}');
        throw Exception('Error en la API del clima');
      }
    } catch (e) {
      print('Error al obtener clima de Open-Meteo: $e');
      throw e;
    }
  }

  void _procesarPronosticoExtendido(Map<String, dynamic> datosPronostico) {
    final dias = datosPronostico['time'] as List;
    final codigosClima = datosPronostico['weathercode'] as List;
    final temperaturasMax = datosPronostico['temperature_2m_max'] as List;
    final temperaturasMin = datosPronostico['temperature_2m_min'] as List;
    final precipitacion = datosPronostico['precipitation_sum'] as List;

    List<Map<String, dynamic>> pronostico = [];

    for (int i = 0; i < dias.length; i++) {
      pronostico.add({
        'fecha': dias[i],
        'codigoClima': codigosClima[i],
        'temperaturaMax': temperaturasMax[i],
        'temperaturaMin': temperaturasMin[i],
        'precipitacion': precipitacion[i],
      });
    }

    setState(() {
      _pronosticoExtendido = pronostico;
    });
  }

  List<String> _procesarHorasLluvia(
      List<String> tiemposHorarios, List<num> codigosClimaHorarios) {
    final horasLluvia = <String>[];
    final ahora = DateTime.now();
    final limite = ahora.add(const Duration(hours: 24));

    for (int i = 0; i < tiemposHorarios.length; i++) {
      try {
        final tiempo = DateTime.parse(tiemposHorarios[i]);
        if (tiempo.isAfter(ahora) && tiempo.isBefore(limite)) {
          final codigoClima = codigosClimaHorarios[i].toInt();
          if (_esCodigoLluvia(codigoClima)) {
            final formato = DateFormat('HH:mm');
            horasLluvia.add(formato.format(tiempo));
          }
        }
      } catch (e) {
        print('Error al procesar hora: $e');
      }
    }

    return horasLluvia;
  }

  bool _esCodigoLluvia(int codigo) {
    // Según la WMO, los códigos de 51 a 67 indican diferentes tipos de lluvia
    // Códigos de 80 a 82 indican lluvia tormentosa
    return (codigo >= 51 && codigo <= 67) || (codigo >= 80 && codigo <= 82);
  }

  String _traducirCodigoClima(int codigo) {
    // Traducción simplificada de códigos WMO
    if (codigo >= 0 && codigo <= 3) {
      return traducir('Despejado', widget.idiomaSeleccionado);
    } else if (codigo >= 4 && codigo <= 9) {
      return traducir('Bruma', widget.idiomaSeleccionado);
    } else if (codigo >= 10 && codigo <= 19) {
      return traducir('Neblina', widget.idiomaSeleccionado);
    } else if (codigo >= 20 && codigo <= 29) {
      return traducir('Lluvia ligera', widget.idiomaSeleccionado);
    } else if (codigo >= 30 && codigo <= 39) {
      return traducir('Tormenta de arena', widget.idiomaSeleccionado);
    } else if (codigo >= 40 && codigo <= 49) {
      return traducir('Niebla', widget.idiomaSeleccionado);
    } else if (codigo >= 50 && codigo <= 59) {
      return traducir('Llovizna', widget.idiomaSeleccionado);
    } else if (codigo >= 60 && codigo <= 69) {
      return traducir('Lluvia', widget.idiomaSeleccionado);
    } else if (codigo >= 70 && codigo <= 79) {
      return traducir('Nieve', widget.idiomaSeleccionado);
    } else if (codigo >= 80 && codigo <= 89) {
      return traducir('Tormenta', widget.idiomaSeleccionado);
    } else if (codigo >= 90 && codigo <= 99) {
      return traducir('Tormenta fuerte', widget.idiomaSeleccionado);
    }
    return traducir('Desconocido', widget.idiomaSeleccionado);
  }

  String _obtenerRecomendacionClima() {
    double temp = double.tryParse(_temperatura) ?? 0;

    if (temp > 35) {
      return traducir('Hace mucho calor! Mantente hidratado y en la sombra.',
          widget.idiomaSeleccionado);
    } else if (temp > 30) {
      return traducir(
          'Hace calor! Usa protector solar.', widget.idiomaSeleccionado);
    } else if (temp >= 20 && temp <= 30) {
      return traducir(
          'Clima agradable, perfecto para salir.', widget.idiomaSeleccionado);
    } else if (temp >= 15 && temp < 20) {
      return traducir('Clima templado, una chaqueta ligera es recomendable.',
          widget.idiomaSeleccionado);
    } else if (temp >= 10 && temp < 15) {
      return traducir(
          'Hace algo de frío, abrígate.', widget.idiomaSeleccionado);
    } else if (temp >= 0 && temp < 10) {
      return traducir('Hace frío! Abrígate bien.', widget.idiomaSeleccionado);
    } else {
      return traducir('Hace mucho frío! Usa varias capas de ropa.',
          widget.idiomaSeleccionado);
    }
  }

  IconData _obtenerIconoClima(String condicion) {
    if (condicion.contains('Lluvia') || condicion.contains('Llovizna')) {
      return Icons.water_drop;
    } else if (condicion.contains('Tormenta')) {
      return Icons.thunderstorm;
    } else if (condicion.contains('Nieve')) {
      return Icons.ac_unit;
    } else if (condicion.contains('Niebla') || condicion.contains('Bruma')) {
      return Icons.cloud;
    } else if (condicion.contains('Despejado')) {
      // Determinar si es día o noche
      final hora = DateTime.now().hour;
      return (hora >= 6 && hora < 18) ? Icons.wb_sunny : Icons.nights_stay;
    }
    return Icons.wb_sunny;
  }

  Widget _buildIconoClima() {
    final icono = _obtenerIconoClima(_condicionClima);

    return AnimatedBuilder(
      animation: _iconAnimationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _iconRotationAnimation.value,
          child: Transform.scale(
            scale: _iconScaleAnimation.value,
            child: Icon(
              icono,
              color: Colors.white,
              size: 60,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPronosticoExtendido() {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: Container(
            height: 160,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  traducir('Pronóstico de 7 días', widget.idiomaSeleccionado),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5), // Reducido de 10 a 5
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pronosticoExtendido.length,
                    itemBuilder: (context, index) {
                      final item = _pronosticoExtendido[index];
                      final fecha = DateTime.parse(item['fecha']);
                      final dia = _getDayAbbreviation(
                          fecha.weekday, widget.idiomaSeleccionado);
                      final fechaCorta = "${fecha.day}/${fecha.month}";

                      return Container(
                        width: 80,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // Envolvemos el contenido en un FittedBox para asegurar que quepa
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisSize: MainAxisSize
                                  .min, // Importante diego: minimiza el tamaño
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dia,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2), // 2 parece quedar bien
                                Text(
                                  fechaCorta,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 2), // Reducido
                                Icon(
                                  _obtenerIconoClima(_traducirCodigoClima(
                                      item['codigoClima'])),
                                  color: Colors.white,
                                  size: 20, // Reducido
                                ),
                                SizedBox(height: 2), // Reducido
                                Text(
                                  '${item['temperaturaMax']}°',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${item['temperaturaMin']}°',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getDayAbbreviation(int weekday, String idioma) {
    Map<String, List<String>> weekdayAbbreviations = {
      'es': ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'],
      'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      'fr': ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
      'de': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
    };

    // Si el idioma no está soportado, usar español por defecto
    List<String> abbreviations =
        weekdayAbbreviations[idioma] ?? weekdayAbbreviations['es']!;

    // weekday es 1-7 (lunes-domingo), pero arrays son 0-6
    return abbreviations[weekday - 1];
  }

  Widget _buildHistorialClima() {
    if (_historialClima.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            traducir('No hay datos históricos disponibles',
                widget.idiomaSeleccionado),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            traducir('Historial de Clima', widget.idiomaSeleccionado),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ListView.builder(
              itemCount: _historialClima.length,
              itemBuilder: (context, index) {
                final item = _historialClima[index];
                final fecha = DateTime.parse(item['fecha']);

                // Formato manual de fecha en lugar de DateFormat que on hay manera en flutter
                final fechaFormateada =
                    "${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}";

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _obtenerIconoClima(
                            _traducirCodigoClima(item['codigoClima'] ?? 0)),
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fechaFormateada,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${item['temperatura']}°C - ${_traducirCodigoClima(item['codigoClima'] ?? 0)} - ${item['ciudad']}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
List<Color> _obtenerColoresGradienteClaro(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return [Colors.amber.shade300, Colors.amber.shade700];
    case 'deuteranopia':
      return [Colors.teal.shade300, Colors.teal.shade700];
    case 'tritanopia':
      return [Colors.purple.shade300, Colors.purple.shade700];
    default:
      return [Colors.blue.shade300, Colors.blue.shade700];
  }
}

List<Color> _obtenerColoresGradienteOscuros(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return [Colors.amber.shade900, Colors.brown.shade900];
    case 'deuteranopia':
      return [Colors.teal.shade900, Colors.blueGrey.shade900];
    case 'tritanopia':
      return [Colors.deepPurple.shade900, Colors.indigo.shade900];
    default:
      return [Colors.indigo.shade900, Colors.purple.shade900];
  }
}
  @override
Widget build(BuildContext context) {
  // Aplicar colores según el modo de daltonismo
  final List<Color> coloresGradiente = _modoOscuro
      ? _obtenerColoresGradienteOscuros(widget.modoDaltonismo)
      : _obtenerColoresGradienteClaro(widget.modoDaltonismo);

  if (_cargando) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: coloresGradiente,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              traducir(
                  'Cargando datos del clima...', widget.idiomaSeleccionado),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (_errorAlCargar) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade300, Colors.red.shade700],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              traducir('Error al cargar datos del clima',
                  widget.idiomaSeleccionado),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _obtenerDatosClima,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
              ),
              child: Text(traducir('Reintentar', widget.idiomaSeleccionado)),
            ),
          ],
        ),
      ),
    );
  }

  // Widget principal con diseño moderno
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: coloresGradiente,
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Fila superior: Ciudad y Fecha/Hora
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _ciudad,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedBuilder(
                animation: _shimmerAnimation,
                builder: (context, child) {
                  return ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _modoOscuro
                            ? [Colors.white, Colors.blue.shade100]
                            : [Colors.white, Colors.white.withOpacity(0.5)],
                        stops: [
                          _shimmerAnimation.value,
                          _shimmerAnimation.value + 0.2
                        ],
                        tileMode: TileMode.clamp,
                      ).createShader(bounds);
                    },
                    child: Text(
                      _fechaHora,
                      style: TextStyle(
                        color: _modoOscuro
                            ? Colors.white
                            : Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Fila central: Temperatura e icono
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 500),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          shadows: _modoOscuro
                              ? [
                                  Shadow(
                                    color: Colors.blue.withOpacity(0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : [],
                        ),
                        child: Text('$_temperatura°C'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _condicionClima,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${traducir('Viento', widget.idiomaSeleccionado)}: $_velocidadViento km/h',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              _buildIconoClima(),
            ],
          ),

          const SizedBox(height: 16),

          // Información de lluvia
          if (_horasLluvia.isNotEmpty) ...[
            Text(
              traducir('Previsión de lluvia:', widget.idiomaSeleccionado),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _horasLluvia.length <= 3
                  ? _horasLluvia.join(', ')
                  : '${_horasLluvia.take(3).join(', ')} ${traducir('y más', widget.idiomaSeleccionado)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Recomendación según temperatura
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _obtenerRecomendacionClima(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Botón para ver pronóstico extendido
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _mostrarPronosticoExtendido = !_mostrarPronosticoExtendido;
                    _mostrarHistorial = false;
                  });

                  if (_mostrarPronosticoExtendido) {
                    _slideController.reset();
                    _slideController.forward();
                  }
                },
                icon: Icon(
                  _mostrarPronosticoExtendido
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: Colors.black,
                ),
                label: Text(
                  traducir('Pronóstico', widget.idiomaSeleccionado),
                  style: const TextStyle(color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _mostrarHistorial = !_mostrarHistorial;
                    _mostrarPronosticoExtendido = false;
                  });

                  if (_mostrarHistorial) {
                    _slideController.reset();
                    _slideController.forward();
                  }
                },
                icon: Icon(
                  _mostrarHistorial ? Icons.expand_less : Icons.expand_more,
                  color: Colors.black,
                ),
                label: Text(
                  traducir('Historial', widget.idiomaSeleccionado),
                  style: const TextStyle(color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Pronóstico extendido (expandible)
          if (_mostrarPronosticoExtendido && _pronosticoExtendido.isNotEmpty)
            _buildPronosticoExtendido(),

          // Historial de clima (expandible)
          if (_mostrarHistorial) _buildHistorialClima(),
        ],
      ),
    );
  }
}
