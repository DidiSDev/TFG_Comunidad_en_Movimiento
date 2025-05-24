import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path; // Path me da problemas
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:comunidad_en_movimiento/ia/modelo_ia.dart';
import 'package:comunidad_en_movimiento/ia/asistente_virtual.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'dart:math' as math;

import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'colores_personalizados.dart';
import 'streetview_google.dart';
import 'traducciones.dart';
import 'incidencias_helper.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'clima_widget.dart';
import 'dart:ui' as ui;
import 'package:comunidad_en_movimiento/services/chatbot_service.dart';
import 'package:comunidad_en_movimiento/home/chatbot_widget.dart';

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  _PantallaPrincipalState createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal>
    with TickerProviderStateMixin {
  StreamSubscription<CompassEvent>? _compassSubscription;
  double _deviceHeading = 0.0;

  double _manualRotation = 0.0; // Rotación manual adicional
  double _totalRotation = 0.0; // Rotación total (dispositivo + manual)
  // NO FUNCIONAN, la api no detecta el gesto de los dedos, es imposible
  // !!!!!!!!!!!!!!!!!!!!!!IMPORTANTE!!!!!!!!!!!!!!!!!!!!!!!
  /**
   * 
   * 
   * SI NO ENCUENTRO NADA EN LA DOC METO BOTÓN PARA RE-ORIENTAR 
   * 
   * 
   */
  bool _showClimaWidget =
      true; // Variable para controlar la visibilidad del widget de clima

  bool _centrar = false;
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _rutaOriginal = [];
  List<Polyline> _polylinesOriginal = [];
  bool _mostrandoRutaEvitarEscaleras = false;
  List<LatLng> _rutaEvitandoEscaleras = [];
  List<Polyline> _polylinesEvitandoEscaleras = [];
  List<Polyline> _polylinesEvitandoEscalerasModificados = [];
  bool _isChatbotVisible = false;
  List<Marker> _escalerasSinRampaMarkers = [];
  bool _mostrarEscalerasSinRampa = true;

  final List<Polyline> _polylinesPorTramo = [];
  List<LatLng> _puntosSubdivididos3D = [];
  bool _esRutaModificada = false;
  List<Polyline> _polylinesModificados = [];
  List<double> _probabilidadesTramos =
      []; // Este array es la lista de probabilidades de cada tramo subdividido en 20 para evaluación de la IA

  String _obtenerNombreDiaSemana(int weekday) {
    Map<int, String> dias = {
      1: 'Lunes',
      2: 'Martes',
      3: 'Miércoles',
      4: 'Jueves',
      5: 'Viernes',
      6: 'Sábado',
      7: 'Domingo',
    };
    return dias[weekday] ?? '';
  }

  final ModeloIA _modeloIA = ModeloIA();

  final FlutterTts _tts = FlutterTts();
  final MapController _mapController = MapController();
  late final AnimatedMapController animatedMapController;

  // Asistente virtual IA
  late final AsistenteVirtualIA _asistenteVirtual;

  // Para la animación de las flechas en el ""3D":
  // Consume muchos recursos, VALORAR
  // *
  // *
  // *
  // +

  late AnimationController _arrowController;
  late Animation<double> _arrowAnimation;
  LatLng? _tappedPosition;
  Timer? _debounceTimer;
  bool _cargandoSugerencias = false;

  bool _isMapReady = false;
  LatLng? _ubicacionOrigen;
  LatLng? _ubicacionDestino;
  List<LatLng> _puntosRuta = [];
  bool _mostrarMapa = false;
  final String _tokenOpenRouteService =
      dotenv.env['OPEN_ROUTE_SERVICE_TOKEN'] ?? '';

  final TextEditingController _controladorUbicacionOrigen =
      TextEditingController();
  final TextEditingController _controladorUbicacionDestino =
      TextEditingController();

  List<String> _sugerenciasOrigen = [];
  List<String> _sugerenciasDestino = [];
  late ChatbotService _chatbotService;
  bool _comprobandoUbicacion = true;
  String _tiempoRuta = '';

  bool _modoIncidencia = false;
  bool _modoDestino = false;

  void _handleChatbotExpandedChanged(bool expanded) {
    setState(() {
      _showClimaWidget = !expanded;
      _isChatbotVisible = expanded;
    });
  }

  // Método para actualizar la rotación total
  void _updateTotalRotation() {
    setState(() {
      _totalRotation = _deviceHeading + _manualRotation;
    });
  }

  final List<String> _opcionesIncidencia = [
    'Escalera o lugar inaccesible',
    'Obras',
    'Vehículo mal estacionado',
    'Barreras arquitectónicas',
    'Señalización confusa',
    'Aceras estrechas',
    'Rampas sin barandilla',
    'Semáforos sin avisos sonoros',
    'Huecos en el pavimento',
    'Señalética mal colocada',
    'Pasos de cebra sin rebajes',
    'Otros',
  ];

  Stream<QuerySnapshot>? _streamIncidencias;

  String _modoDaltonismo = 'por_defecto';
  String? _filtroIncidencia;
  final List<String> _idiomas = ['es', 'en', 'fr', 'de'];
  String _idiomaSeleccionado = 'es';

  bool _mostrarIncidencias = true;
  String _ciudadActual = 'Tu mapa';

  @override
  void initState() {
    super.initState();
    animatedMapController = AnimatedMapController(
      vsync: this,
      mapController: _mapController,
    );

    // Modificamos el listener del compás para actualizar más frecuentemente
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      // Actualizaciones más frecuentes
      setState(() {
        _deviceHeading = event.heading ?? 0.0;
        _updateTotalRotation();
      });
    });

    // Añadimos un listener al MapController para detectar cambios de rotación manuales
    _mapController.mapEventStream.listen((event) {
      if (event is MapEventRotate) {
        setState(() {
          if (event is MapEventRotate) {
            _manualRotation += event.rotationAngle - _totalRotation;
          }
          _updateTotalRotation();
        });
      }
    });

    // Inicialización
    _asistenteVirtual = AsistenteVirtualIA(_modeloIA);
    _cargarModelos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectarUbicacion();
    });
    _streamIncidencias =
        FirebaseFirestore.instance.collection('incidencias').snapshots();
    _configurarNotificaciones();

    // Iniciar la animación de las flechas (probablemente lo tenga que quitar)
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _arrowAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_arrowController);

    // Inicializamos el chatbot (mantenemos el código original)
    _chatbotService = ChatbotService(
      apiKey: dotenv.env['OPENAI_API_KEY'] ?? '',
    );
    // Esto es turbosecreto, si has llegado hasta aquí y NO eres YO. Estaré vigilando lo que haces con esto, que me cuesta dinero

    // Valor total de rotación
    _totalRotation = _deviceHeading;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _arrowController.dispose();
    _controladorUbicacionOrigen.dispose();
    _controladorUbicacionDestino.dispose();
    _compassSubscription?.cancel();

    super.dispose();
  }

/**
 * 
 * SOLUCIONADO PROBLEMA, LA API DE OVERPASS ME PERMITE HACER LLAMADAS MUY INTERESANTES DE DATOS SOBRE EL MAPA
 */
// ================== ESCALERAS SIN RAMPA - EJEMPLO ================== //
  ///Consulta Overpass para obtener "escaleras sin rampa" en tu ciudad.
// Devuelve una lista de marcadores (Marker), bastante feos por cierto, CAMBIAR ICONO <------------
  ///
  /// *********************************IMPORTANTE:
//En las versiones de flutter_map >= 5.0, el Marker usa 'child:' en lugar de 'builder:'.
  ///Ajusto el bounding box (offset) y la query PARA LAS ESCALERAS.
  Future<List<Marker>> _consultarEscalerasSinRampaOverpass() async {
    // Si no tenemos ubicación de origen, salimos con lista vacía.
    if (_ubicacionOrigen == null) {
      return [];
    }

    // Ajustamos el offset(~2km en cada dirección) x ejemplo
    final double offset = 0.02;
    double latMin = _ubicacionOrigen!.latitude - offset;
    double latMax = _ubicacionOrigen!.latitude + offset;
    double lngMin_ = _ubicacionOrigen!.longitude - offset;
    double lngMax_ = _ubicacionOrigen!.longitude + offset;

    // Overpass usa orden: (south,west,north,east) => latMin,lngMin,latMax,lngMax
    // Query: highway=steps AND ramp!=yes => "no rampa"
    // Iconos = escaleras SIN rampa
    final String overpassQuery = '''
  [out:json];
  (
    way["highway"="steps"]["ramp"!="yes"]($latMin,$lngMin_,$latMax,$lngMax_);
    node["highway"="steps"]["ramp"!="yes"]($latMin,$lngMin_,$latMax,$lngMax_);
  );
  out center;
  ''';

    final url = Uri.parse('https://overpass-api.de/api/interpreter');

    try {
      // Hacemos POST con la query
      final resp = await http.post(
        url,
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {'data': overpassQuery},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);

        if (data['elements'] == null) {
          print('No se encontraron escaleras sin rampa en esta zona.');
          return [];
        }

        final List elementos = data['elements'];
        final List<Marker> markers = [];

        for (var elem in elementos) {
          // Puede ser 'node' o 'way'
          double? lat;
          double? lng;

          // Para 'way', Overpass a veces devuelve 'center' ¿?
          if (elem['type'] == 'node') {
            lat = elem['lat'];
            lng = elem['lon'];
          } else if (elem['type'] == 'way' && elem['center'] != null) {
            lat = elem['center']['lat'];
            lng = elem['center']['lon'];
          }

          if (lat == null || lng == null) continue; // Evito nulos

          markers.add(
            Marker(
              width: 60,
              height: 60,
              point: LatLng(lat, lng),
              // En flutter_map >= 5.0, usamos 'child:' en lugar de 'builder:'
              child: const Icon(
                Icons.block, // Escalera sin rampa -> ícono de "bloqueo"
                color: Colors.red,
                size: 15,
              ),
            ),
          );
        }

        print('Escaleras sin rampa encontradas: ${markers.length}');
        return markers;
      } else {
        print('Error Overpass: ${resp.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error consultando Overpass: $e');
      return [];
    }
  }

  Widget _buildCompass() {
    // Offset total = 180° + 180° = 360°
    // Pero 360° equivale a 0° en un círculo, así que usaremos 0° y cambiaremos el signo
    // de la rotación (negando el heading) para invertirlo porque es más dificil orientar esto que centrar un div

    final double correctedHeading = -_deviceHeading; // Inversión completa

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withOpacity(0.9),
            Colors.white.withOpacity(0.7),
          ],
          radius: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1.5),
      ),
      child: Transform.rotate(
        // Invertimos directamente la rotación
        angle: correctedHeading * math.pi / 180, // positivo o no?
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),

            // Norte (resaltado)
            const Positioned(
              top: 8,
              child: Text(
                'N',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
            // Este
            const Positioned(
              right: 8,
              child: Text(
                'E',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            // Sur
            const Positioned(
              bottom: 8,
              child: Text(
                'S',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            // Oeste
            const Positioned(
              left: 8,
              child: Text(
                'O',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),

            // Flecha indicadora (aguja)
            Container(
              width: 2,
              height: 40,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.red,
                    Colors.redAccent,
                  ],
                ),
              ),
            ),

            // Punto central
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cargarModelos() async {
    try {
      await _modeloIA.cargarModelo(
        'lib/assets/modelos/modelo_ia.tflite', // Ruta del modelo TFLite q vamos a cargar
        'assets/zona_mapping.json', // Ruta del mapeo de zonas
      );
      print('Ambos modelos se han cargado correctamente.');
      setState(() {});
    } catch (e) {
      print('Error al cargar los modelos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            '${traducir('Error al cargar los modelos:', _idiomaSeleccionado)} $e',
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
    }
  }

// Necesito una lista de artículos por si en los campos de origenn o destino el usuario los escribe, no son de utilidad para cargar calles en la API
  String _simplificarConsulta(String consulta) {
    List<String> palabrasIgnoradas = [
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'en',
      'y',
      'por',
      'con',
      'para'
    ];
    return consulta
        .toLowerCase()
        .split(' ')
        .where((palabra) => !palabrasIgnoradas.contains(palabra))
        .join(' ');
  }

  Future<void> _configurarNotificaciones() async {
    await Firebase.initializeApp();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: obtenerColorWarning(_modoDaltonismo),
            content: Text(
              '${traducir('Nueva incidencia:', _idiomaSeleccionado)} ${message.notification!.title}',
              style: TextStyle(color: obtenerColorTexto()),
            ),
          ),
        );
      }
    });
  }

  Future<void> _detectarUbicacion() async {
    bool servicioHabilitado;
    LocationPermission permiso;

    try {
      servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: obtenerColorWarning(_modoDaltonismo),
            content: Text(
              traducir('Los servicios de ubicación están deshabilitados.',
                  _idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto()),
            ),
          ),
        );
        setState(() {
          _comprobandoUbicacion = false;
        });
        return;
      }

      permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: obtenerColorWarning(_modoDaltonismo),
              content: Text(
                traducir('Permiso de ubicación denegado.', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTexto()),
              ),
            ),
          );
          setState(() {
            _comprobandoUbicacion = false;
          });
          return;
        }
      }

      if (permiso == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: obtenerColorWarning(_modoDaltonismo),
            content: Text(
              traducir('Permiso de ubicación denegado permanentemente.',
                  _idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto()),
            ),
          ),
        );
        setState(() {
          _comprobandoUbicacion = false;
        });
        return;
      }

      Position posicion = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        _ubicacionOrigen = LatLng(posicion.latitude, posicion.longitude);

        // Obtengo ciudad
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
              posicion.latitude, posicion.longitude);
          if (placemarks.isNotEmpty) {
            _ciudadActual =
                placemarks.first.locality ?? 'Ubicación desconocida';
          } else {
            _ciudadActual = 'Ubicación desconocida';
          }
        } catch (e) {
          _ciudadActual = 'Ubicación desconocida';
        }

        await _actualizarTextoOrigen(_ubicacionOrigen);

        setState(() {
          if (_isMapReady && _ubicacionOrigen != null) {
            _mapController.move(_ubicacionOrigen!, 15.0);
          }
          _comprobandoUbicacion = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            '${traducir('Error al obtener la ubicación:', _idiomaSeleccionado)} $e',
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _comprobandoUbicacion = false;
        });
      }
    }
  }

  Future<void> _actualizarTextoOrigen(LatLng? latLng) async {
    if (latLng == null) return;
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        Placemark pm = placemarks.first;
        String calle = pm.thoroughfare ??
            pm.name ??
            traducir('Tu Ubicación', _idiomaSeleccionado);
        if (calle.isEmpty) {
          calle = traducir('Tu Ubicación', _idiomaSeleccionado);
        }
        _controladorUbicacionOrigen.text = calle;
      } else {
        _controladorUbicacionOrigen.text =
            traducir('Tu Ubicación', _idiomaSeleccionado);
      }
    } catch (e) {
      _controladorUbicacionOrigen.text =
          traducir('Tu Ubicación', _idiomaSeleccionado);
    }
  }

  void _abrirMapa() async {
    if (await Geolocator.isLocationServiceEnabled()) {
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.whileInUse ||
          permiso == LocationPermission.always) {
        Position posicion = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        _ubicacionOrigen = LatLng(posicion.latitude, posicion.longitude);
        await _actualizarTextoOrigen(_ubicacionOrigen);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: obtenerColorWarning(_modoDaltonismo),
            content: Text(
              traducir('No se ha obtenido tu ubicación actual.',
                  _idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto()),
            ),
          ),
        );
      }
    }

    setState(() {
      _mostrarMapa = true;
      _ubicacionDestino = null;
      _puntosRuta = [];
      _controladorUbicacionDestino.clear();
      _tiempoRuta = '';
    });

/* IMPORTANTE IMPORTANTE IMPORTANTE */
    // =+************* IMPORTANTE: llamamos Overpass para cargar escaleras sin rampa =+***********************
    Future.microtask(() async {
      List<Marker> marcadores = await _consultarEscalerasSinRampaOverpass();
      if (mounted) {
        setState(() {
          _escalerasSinRampaMarkers = marcadores;
        });
      }
    });
  }

  void _cerrarMapa() {
    setState(() {
      _mostrarMapa = false;
      _ubicacionDestino = null;
      _puntosRuta = [];
      _controladorUbicacionDestino.clear();
      _tiempoRuta = '';
    });
  }

  void _onMapTap(LatLng latlng) async {
    if (_modoIncidencia) {
      // En lugar de mostrar el diálogo inmediato, guardamos la posición tocada.
      setState(() {
        _tappedPosition = latlng;
      });
      //SnackBar informando
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            traducir(
                'Tocaste el mapa. Presiona "Abrir StreetView" para marcar incidencia con precisión.',
                _idiomaSeleccionado),
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
    } else if (_modoDestino) {
      setState(() {
        _ubicacionDestino = latlng;
        _puntosRuta = [];
        _tiempoRuta = '';
      });
      _modoDestino = false;
    }
  }

  // Función para obtener la ruta (GET para ruta normal, POST para evitar escaleras)
  Future<void> _obtenerRuta({bool avoidStairs = false}) async {
    if (_ubicacionOrigen == null || _ubicacionDestino == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Selecciona origen y destino antes de iniciar la ruta.'),
        ),
      );
      return;
    }

    // RUTA NORMAL => foot-walking
    if (!avoidStairs) {
      _esRutaModificada = false;

      // Llamada GET con el perfil "foot-walking" -> osea a pie
      final url = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/foot-walking'
          '?api_key=$_tokenOpenRouteService'
          '&start=${_ubicacionOrigen!.longitude},${_ubicacionOrigen!.latitude}'
          '&end=${_ubicacionDestino!.longitude},${_ubicacionDestino!.latitude}');

      // DEPURAMOS, no funciona nada ¿?¿¿?
      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          print('--- TURBO RESPUESTA ORS foot-walking (Ruta original) ---');
          print('StatusCode: ${response.statusCode}');
          print('Body: ${response.body}');
          _processRouteResponse(response.body, false);
        } else {
          print('Error al obtener la ruta: ${response.statusCode}');
          print('Cuerpo del error: ${response.body}');
        }
      } catch (e) {
        print('Error en foot-walking GET: $e');
      }
    } else {
      // RUTA EVITANDO ESCALERAS => "wheelchair" -> SILLA DE RUEDAS
      _esRutaModificada = true;

      // Llamada GET con el perfil "wheelchair"
      final url = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/wheelchair'
          '?api_key=$_tokenOpenRouteService'
          '&start=${_ubicacionOrigen!.longitude},${_ubicacionOrigen!.latitude}'
          '&end=${_ubicacionDestino!.longitude},${_ubicacionDestino!.latitude}');

      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          print('--- RESPUESTA ORS wheelchair (Evitar escaleras) ---');
          print('StatusCode: ${response.statusCode}');
          print('Body: ${response.body}');
          _processRouteResponse(response.body, true);

          // Popup de elección de ruta
          _mostrarDialogoEleccionRuta();
        } else {
          print(
              'Error al obtener la ruta (wheelchair): ${response.statusCode}');
          print('Cuerpo del error: ${response.body}');
        }
      } catch (e) {
        print('Error en wheelchair GET: $e');
      }
    }
  }

  // Popup para preguntar si quiere ruta original o evitando eskleras
  Future<void> _mostrarDialogoEleccionRuta() async {
    bool? deseaRutaEvitarEscaleras = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: obtenerColorFondo(_modoDaltonismo),
          title: Text(
            '¿Qué ruta prefieres?',
            style: TextStyle(color: obtenerColorTexto()),
          ),
          content: Text(
            'Hemos encontrado una ruta alternativa evitando escaleras.\n'
            '¿Quieres conservar la RUTA ORIGINAL o usar la RUTA EVITANDO ESCALERAS?',
            style: TextStyle(color: obtenerColorTexto()),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Si elige la ruta original
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Ruta Original',
                style: TextStyle(color: obtenerColorTexto()),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: obtenerColorBoton(_modoDaltonismo),
              ),
              onPressed: () {
                // Si elige la ruta evitando escaleras
                Navigator.of(context).pop(true);
              },
              child: Text(
                'Evitar Escaleras',
                style: TextStyle(color: obtenerColorTextoBoton()),
              ),
            ),
          ],
        );
      },
    );

    // Si el usuario cierra el diálogo, no hacemos nada, la que esté
    if (deseaRutaEvitarEscaleras == null) return;

    // Actualizamos el estado según la elección
    setState(() {
      if (deseaRutaEvitarEscaleras == true) {
        // Mostrar la ruta evitando escaleras
        _mostrandoRutaEvitarEscaleras = true;
      } else {
        // Conservar la ruta original
        _mostrandoRutaEvitarEscaleras = false;

        // Limpiamos las polilíneas de "evitar escaleras" para no confundir
        _polylinesEvitandoEscaleras.clear();
        _polylinesEvitandoEscalerasModificados.clear();

        // Restauramos la polilínea original a _puntosRuta
        _puntosRuta = _rutaOriginal;
        _polylinesPorTramo.clear();
        _polylinesPorTramo.addAll(_polylinesOriginal);
        // Sin tramos "modificados"
        _polylinesModificados.clear();
      }
    });
  }

  //************************* IMPORTANTE***************************** */
  //*
  //*
  // Esta función está copiada de la documentación de overpass
  // Así que cualquier actualización puede hacer que deje de funcionar, REVISAR SI OCURRE

  // No puedo pinear la versión en pubspec así que si se rompe, f-.-'

  void _processRouteResponse(String responseBody, bool avoidStairs) {
    final data = json.decode(responseBody);

    // 1) Verificar si la respuesta trae "features" o "routes"
    List<dynamic>? coords;
    double duracionSegundos = 0.0;

    if (data['features'] != null) {
      // Estructura "FeatureCollection"
      coords = data['features'][0]['geometry']['coordinates'] as List;
      duracionSegundos =
          data['features'][0]['properties']['summary']['duration'] ?? 0.0;
    } else if (data['routes'] != null) {
      // Estructura con "routes"
      coords = data['routes'][0]['geometry']['coordinates'] as List;
      duracionSegundos = data['routes'][0]['summary']['duration'] ?? 0.0;
    } else {
      // Desconocido
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            'No se reconoce el formato de la respuesta de OpenRouteService.',
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
      return;
    }

    if (coords == null) {
      // Evitar crasheo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            'No se encontró la geometría en la respuesta de OpenRouteService.',
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
      return;
    }

    // 2) Convertir coords a lista de LatLng (lon, lat => lat, lon)
    final List<LatLng> puntos =
        coords.map<LatLng>((coord) => LatLng(coord[1], coord[0])).toList();

    // 3) Calcular tiempo estimado
    int horas = (duracionSegundos ~/ 3600);
    int minutos = ((duracionSegundos % 3600) ~/ 60);
    String tiempoEstimado = '';
    if (horas > 0) {
      tiempoEstimado += '$horas ${traducir('horas', _idiomaSeleccionado)} ';
    }
    if (minutos > 0) {
      tiempoEstimado += '$minutos ${traducir('minutos', _idiomaSeleccionado)}';
    }
    _tiempoRuta = tiempoEstimado.trim().isEmpty
        ? traducir('Menos de un minuto', _idiomaSeleccionado)
        : tiempoEstimado.trim();

    // 4) Guardar la ruta en polilíneas
    if (!avoidStairs) {
      // Ruta Original => color azul
      _rutaOriginal = puntos;
      _polylinesOriginal.clear();
      _polylinesOriginal.add(
        Polyline(points: puntos, color: Colors.blue, strokeWidth: 4.0),
      );

      _puntosRuta = puntos;
      _polylinesPorTramo
        ..clear()
        ..add(Polyline(
            points: _puntosRuta, color: Colors.blue, strokeWidth: 4.0));
      _polylinesModificados.clear();
    } else {
      // Ruta Evitando Escaleras => color rosado
      _rutaEvitandoEscaleras = puntos;
      _polylinesEvitandoEscaleras
        ..clear()
        ..add(Polyline(
            points: puntos, color: Colors.pinkAccent, strokeWidth: 4.0));

      _puntosRuta = puntos;
      _polylinesPorTramo
        ..clear()
        ..add(Polyline(
            points: _puntosRuta, color: Colors.pinkAccent, strokeWidth: 4.0));

      // Sub-tramos "modificados" junto a escaleras
      _polylinesModificados =
          _calcularSegmentosModificados(_puntosRuta, _escalerasSinRampaMarkers);
    }

    setState(() {});
  }

  /// ****!!!!!!!!!!!!**********PARTES MODIFICADAS******!!!!!!!!!!! ///
  List<Polyline> _calcularSegmentosModificados(
      List<LatLng> route, List<Marker> markers) {
    List<LatLng> modifiedPoints = [];
    const double threshold =
        10.0; // Umbral en metros para considerar que el tramo pasa cerca de una escalera

    for (int i = 0; i < route.length - 1; i++) {
      LatLng p1 = route[i];
      LatLng p2 = route[i + 1];
      // Calculamos el punto medio
      LatLng mid = LatLng(
          (p1.latitude + p2.latitude) / 2, (p1.longitude + p2.longitude) / 2);
      bool isModified = false;
      for (Marker marker in markers) {
        double d = Distance().as(LengthUnit.Meter, mid, marker.point);
        if (d < threshold) {
          isModified = true;
          break;
        }
      }
      if (isModified) {
        modifiedPoints.add(p1);
        modifiedPoints.add(p2);
      }
    }

    List<Polyline> modifiedPolylines = [];
    if (modifiedPoints.isNotEmpty) {
      modifiedPolylines.add(
        Polyline(
          points: modifiedPoints,
          color: Colors
              .pink, // <-- aquí el color de los segmentos "modificados" q se ve en todos los tipos de daltonismo, supuestamente
          strokeWidth: 4.0,
        ),
      );
    }
    return modifiedPolylines;
  }

  // REVISAR DOCUMENTACIÓN TAMBIÉN AQUÍ SI FALLA
  List<List<List<List<double>>>> _generateAvoidPolygons(
      List<Marker> markers, double radiusMeters) {
    List<List<List<List<double>>>> multipolygon = [];
    int maxPolygons = 10; // Máximo de polígonos que se peta
    int numSides = 4; // Reducimos a 4 lados (cuadrado) para simplificar

    for (int i = 0; i < markers.length && i < maxPolygons; i++) {
      double centerLat = markers[i].point.latitude;
      double centerLng = markers[i].point.longitude;
      List<List<double>> polygon = [];

      for (int j = 0; j < numSides; j++) {
        double angle = (2 * pi * j) / numSides;
        double deltaLat = (radiusMeters / 111320) * cos(angle);
        double deltaLng =
            (radiusMeters / (111320 * cos(centerLat * pi / 180))) * sin(angle);
        double pointLat = centerLat + deltaLat;
        double pointLng = centerLng + deltaLng;
        polygon.add([pointLng, pointLat]); // Formato GeoJSON: [lng, lat]
      }

      polygon.add(polygon[0]); // Le cierro
      multipolygon.add([polygon]);
    }

    print("Total de polígonos generados: ${multipolygon.length}");
    return multipolygon;
  }

  void _toggleCentrar() {
    setState(() {
      _centrar = !_centrar;

      // Si estamos activando el centrado, reseteamos la rotación manual
      if (_centrar) {
        _manualRotation = 0.0; // Resetear rotación manual al centrar
        _updateTotalRotation(); // Actualiza _totalRotation

        // Forzar actualización inmediata de la brújula
        if (FlutterCompass.events != null) {
          FlutterCompass.events!.first.then((event) {
            setState(() {
              _deviceHeading = event.heading ?? 0.0;
              _updateTotalRotation();
            });
          });
        }
      }
    });

    if (_centrar) {
      // Cancelamos cualquier suscripción previa o movimiento acumulado hecho con los ddos
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        setState(() {
          _ubicacionOrigen = LatLng(position.latitude, position.longitude);
        });

        // Recortamos la ruta para eliminar el tramo ya recorrido
        _recortarRuta();

        // Si tenemos ubicación, animamos el mapa centrándolo y usando la rotación del dispositivo
        if (_ubicacionOrigen != null) {
          animatedMapController.animateTo(
            dest: _ubicacionOrigen!,
            zoom: 17.0,
            rotation: _deviceHeading,
            // Usamos la rotación del dispositivo directamente
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );

          // Forzamos la actualización del estado para asegurar que la brújula se redibuje
          setState(() {
            _totalRotation = _deviceHeading;
          });
        }
      });
    } else {
      _positionStream?.cancel();
      _positionStream = null;
    }
  }

// No es posible reconocer el gesto de los dedos al rotar el mapa, así que dejamos un botón para arreglarlo
  void _orientarMapa() {
    setState(() {
      // Resetear rotacion de ddos
      _manualRotation = 0.0;
      _updateTotalRotation();

      // Fuerza a la brújula a actualizarse
      if (FlutterCompass.events != null) {
        FlutterCompass.events!.first.then((event) {
          setState(() {
            _deviceHeading = event.heading ?? 0.0;
            _updateTotalRotation();
          });
        });
      }

      // Forzar la orientación del mapa según la brújula actual
      animatedMapController.animateTo(
        dest: _mapController.camera.center,
        zoom: _mapController.camera.zoom,
        rotation:
            0, // Resetear rotación para orientar al norte (que no es 0 como tal, es como 6-8 grados, pero según chatgpt si no es 0 es por culpa del giroscopio del tlf), en la documnentación pone 0
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  // Le voy a meter un debounce mientras escribo para no hacer 1209310301932019302193 peticiones a la api y que me vuelvan a banear

  // IMPORTANTE:
  // LAS FUNCIONES DE DEBAJO ESTÁN BASADAS EN LA DOCUMUENTACIÓN, TODO EL MUNDO LAS APLICA DE LA MISMA FORMA Y ESTÁN MUY BIEN EXPLICADAS
  Future<void> _buscarSugerenciasUbicacion(
      String consulta, bool esOrigen) async {
    if (consulta.isEmpty) {
      setState(() {
        if (esOrigen) {
          _sugerenciasOrigen = [];
        } else {
          _sugerenciasDestino = [];
        }
        _cargandoSugerencias = false;
      });
      return;
    }

    _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _cargandoSugerencias = true;
      });

      String consultaSimplificada = _simplificarConsulta(consulta);

      String urlSugerencia =
          'https://nominatim.openstreetmap.org/search?q=$consultaSimplificada'
          '&format=json&addressdetails=1&limit=6';

      if (_ubicacionOrigen != null) {
        double offset = 0.27;
        double minx = _ubicacionOrigen!.longitude - offset;
        double maxx = _ubicacionOrigen!.longitude + offset;
        double miny = _ubicacionOrigen!.latitude - offset;
        double maxy = _ubicacionOrigen!.latitude + offset;

        urlSugerencia += '&bounded=1&viewbox=$minx,$maxy,$maxx,$miny';
      }

      final url = Uri.parse(urlSugerencia);

      try {
        final response = await http.get(url).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('La solicitud ha tardado demasiado tiempo');
          },
        );

        if (response.statusCode == 200) {
          final List data = json.decode(response.body);

          List<String> sugerencias = [];
          for (var item in data) {
            String nombre = item['display_name'] ?? 'Lugar sin nombre';
            double lat = double.parse(item['lat'] ?? '0');
            double lon = double.parse(item['lon'] ?? '0');

            double distancia = 0.0;
            if (_ubicacionOrigen != null) {
              const Distance distanciaCalculadora = Distance();
              distancia = distanciaCalculadora(
                LatLng(_ubicacionOrigen!.latitude, _ubicacionOrigen!.longitude),
                LatLng(lat, lon),
              );
            }

            String distanciaTexto = distancia < 1000
                ? '${distancia.toStringAsFixed(0)} m'
                : '${(distancia / 1000).toStringAsFixed(2)} km';

            sugerencias.add('$nombre ($distanciaTexto)');
          }

          if (mounted) {
            setState(() {
              if (esOrigen) {
                _sugerenciasOrigen = sugerencias;
              } else {
                _sugerenciasDestino = sugerencias;
              }
              _cargandoSugerencias = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _cargandoSugerencias = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Error al obtener sugerencias (${response.statusCode})'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _cargandoSugerencias = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Error de conexión: ${e.toString().contains('timeout') ? 'Tiempo de espera agotado' : e.toString()}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  Future<void> _seleccionarUbicacionSugerida(
      String direccion, bool esOrigen) async {
    try {
      List<Location> ubicaciones = await locationFromAddress(direccion);
      if (ubicaciones.isNotEmpty) {
        Location ubicacion = ubicaciones.first;
        setState(() {
          if (esOrigen) {
            _ubicacionOrigen = LatLng(ubicacion.latitude, ubicacion.longitude);
            _controladorUbicacionOrigen.text = direccion;
            _sugerenciasOrigen.clear();
            _mapController.move(_ubicacionOrigen!, 15.0);
          } else {
            _ubicacionDestino = LatLng(ubicacion.latitude, ubicacion.longitude);
            _controladorUbicacionDestino.text = direccion;
            _sugerenciasDestino.clear();
          }
          _puntosRuta = [];
          _tiempoRuta = '';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: obtenerColorWarning(_modoDaltonismo),
          content: Text(
            '${traducir('Error al seleccionar la ubicación:', _idiomaSeleccionado)} $e',
            style: TextStyle(color: obtenerColorTexto()),
          ),
        ),
      );
    }
  }

  double _distancia(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    double distMetros = distance(p1, p2);
    return distMetros;
  }

  String _formatearDistancia(double distEnMetros) {
    if (distEnMetros < 1000) {
      return '${distEnMetros.toStringAsFixed(0)} m';
    } else {
      double km = distEnMetros / 1000.0;
      return '${km.toStringAsFixed(2)} km';
    }
  }

  Widget _construirCapaIncidencias(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) return Container();

    final docs = snapshot.data!.docs;
    var incidencias = docs;
    if (_filtroIncidencia != null) {
      incidencias =
          docs.where((doc) => doc['tipo'] == _filtroIncidencia).toList();
    }

    if (!_mostrarIncidencias) return Container();

    List<Marker> marcadores = [];
    for (var doc in incidencias) {
      double lat = doc['latitude'];
      double lng = doc['longitude'];
      String tipo = doc['tipo'];
      String descripcion = doc['descripcion'] ?? '';
      int peligro = doc['peligro'] ?? 0;
      int categoriaAccesibilidad = doc['categoria_accesibilidad'] ?? 1;

      double distMetros = 0.0;
      if (_ubicacionOrigen != null) {
        distMetros = _distancia(_ubicacionOrigen!, LatLng(lat, lng));
      }

      String distTexto = _formatearDistancia(distMetros);

      // Determino el color del marcador basado en categoría y peligro
      Color colorMarcador;
      if (categoriaAccesibilidad == 2 || peligro == 1) {
        colorMarcador = Colors.red; // Rojo para moderado y grave
      } else {
        colorMarcador = Colors
            .green; // Verde para leve <- Se ve en todos los daltonismos aunque mal, contrasta bien con el resto
      }

      marcadores.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: LatLng(lat, lng),
          child: Transform.rotate(
            // Contrarrestar la rotación del mapa
            angle: _totalRotation * math.pi / 180,
            child: GestureDetector(
              onTap: () async {
                bool eliminar = await mostrarDialogoEliminarIncidencia(
                  context,
                  tipo,
                  descripcion,
                  setState,
                  _modoDaltonismo,
                  _idiomaSeleccionado,
                );
                if (eliminar) {
                  await FirebaseFirestore.instance
                      .collection('incidencias')
                      .doc(doc.id)
                      .delete();
                } else {
                  await _tts.speak(
                    '${traducir('Incidencia tipo', _idiomaSeleccionado)} '
                    '${traducir(tipo, _idiomaSeleccionado)}. '
                    '${traducir('Descripción:', _idiomaSeleccionado)} $descripcion',
                  );
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.warning, color: colorMarcador),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Text(
                      distTexto,
                      style: const TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MarkerLayer(markers: marcadores);
  }

  Widget _construirMapa() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Factor reducido para evitar sobrecarga (1.1 en lugar de 3)
        // 1.2 es el límite, a partir de aquí el mapa se empieza a cortar en las esquinas
        final double factor = 1.1;
        final double maxSide =
            factor * math.max(constraints.maxWidth, constraints.maxHeight);

        return StreamBuilder<QuerySnapshot>(
          stream: _streamIncidencias,
          builder: (context, snapshotIncidencias) {
            return Stack(
              children: [
                // Mapa con OverflowBox y Transform.rotate
                Positioned.fill(
                  child: OverflowBox(
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Center(
                      child: SizedBox(
                        width: maxSide,
                        height: maxSide,
                        child: Transform.rotate(
                          angle: -_deviceHeading * math.pi / 180,
                          child: AbsorbPointer(
                            // Recojo eventos de gestos cuando centrar está activado
                            absorbing: _centrar,
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _ubicacionOrigen ??
                                    const LatLng(40.9701, -5.6635),
                                initialZoom: 15.0,
                                onTap: (tapPosition, latlng) =>
                                    _onMapTap(latlng),
                                onMapReady: () {
                                  setState(() {
                                    _isMapReady = true;
                                  });
                                  if (_ubicacionOrigen != null) {
                                    _mapController.move(
                                        _ubicacionOrigen!, 15.0);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  subdomains: const <String>[],
                                  userAgentPackageName:
                                      'com.didisdev.comunidad_en_movimiento',
                                ),
                                // Marcadores de origen/destino
                                MarkerLayer(
                                  markers: [
                                    if (_ubicacionOrigen != null)
                                      Marker(
                                        width: 80.0,
                                        height: 80.0,
                                        point: _ubicacionOrigen!,
                                        child: Transform.rotate(
                                          // Contrarresto la rotación del mapa para mantener orientación al usuario
                                          angle: _totalRotation * math.pi / 180,
                                          child: Icon(
                                            Icons.my_location,
                                            color: obtenerColorMiUbicacion(
                                                _modoDaltonismo),
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    if (_ubicacionDestino != null)
                                      Marker(
                                        width: 80.0,
                                        height: 80.0,
                                        point: _ubicacionDestino!,
                                        child: Transform.rotate(
                                          // Lo mismo
                                          angle: _totalRotation * math.pi / 180,
                                          child: Icon(
                                            Icons.location_on,
                                            color: obtenerColorDestino(
                                                _modoDaltonismo),
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // Ruta original
                                if (_polylinesPorTramo.isNotEmpty)
                                  PolylineLayer(polylines: _polylinesPorTramo),
                                // Si la ruta fue modificada (evitar escaleras), dibuja los segmentos modificados
                                if (_polylinesModificados.isNotEmpty)
                                  PolylineLayer(
                                      polylines: _polylinesModificados),
                                if (_mostrarEscalerasSinRampa)
                                  MarkerLayer(
                                      markers: _escalerasSinRampaMarkers),
                                if (snapshotIncidencias.connectionState ==
                                    ConnectionState.active)
                                  _construirCapaIncidencias(
                                      snapshotIncidencias),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Recuadro con tiempo estimado
                if (_tiempoRuta.isNotEmpty && _mostrarMapa)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        '${traducir('Tiempo estimado:', _idiomaSeleccionado)} $_tiempoRuta',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                // Campos de búsqueda (Origen y Destino)
                Positioned(
                  top: 70, // Así dejo espacio al recuadro 
                  left: 10,
                  right: 60,
                  child: Column(
                    children: [
                      _crearCampoBusqueda(
                        _controladorUbicacionOrigen,
                        traducir('Ubicación Origen', _idiomaSeleccionado),
                        _sugerenciasOrigen,
                        true,
                      ),
                      const SizedBox(height: 10),
                      _crearCampoBusqueda(
                        _controladorUbicacionDestino,
                        traducir('Ubicación Destino', _idiomaSeleccionado),
                        _sugerenciasDestino,
                        false,
                      ),
                    ],
                  ),
                ),
                // Botón "Iniciar Ruta"
                if (_mostrarMapa &&
                    _ubicacionOrigen != null &&
                    _ubicacionDestino != null)
                  Positioned(
                    bottom: 60,
                    left: 20,
                    child: _buildModernButton(
                      text: traducir('Iniciar Ruta', _idiomaSeleccionado),
                      icon: Icons.navigation,
                      onPressed: _obtenerRuta,
                    ),
                  ),

                // Botón "Volver"
                if (_mostrarMapa)
                  Positioned(
                    bottom: 60,
                    right: 20,
                    child: _buildModernButton(
                      text: traducir('Volver', _idiomaSeleccionado),
                      icon: Icons.arrow_back,
                      onPressed: _cerrarMapa,
                      isSmall: true,
                    ),
                  ),

                // Botón "Evitar escaleras"
                if (_mostrarMapa &&
                    _ubicacionOrigen != null &&
                    _ubicacionDestino != null)
                  Positioned(
                    bottom: 120,
                    left: 20,
                    child: _buildModernButton(
                      text: 'Evitar escaleras',
                      icon: Icons.accessible,
                      onPressed: () {
                        _obtenerRuta(avoidStairs: true);
                      },
                    ),
                  ),

                // Botón "Orientar"
                if (_mostrarMapa)
                  Positioned(
                    bottom: 180,
                    left: 20,
                    child: _buildModernButton(
                      text: traducir('Orientar', _idiomaSeleccionado),
                      icon: Icons.compass_calibration,
                      onPressed: _orientarMapa,
                    ),
                  ),

                // Botones de centrar y cancelar centrado 
                if (_mostrarMapa)
                  Positioned(
                    bottom: 120,
                    right: 20,
                    child: _centrar
                        ? _buildModernButton(
                            // Botón para desactivar el centrado
                            text: traducir(
                                'Desbloquear mapa', _idiomaSeleccionado),
                            icon: Icons.lock_open,
                            onPressed: _toggleCentrar,
                            backgroundColor: Colors.red.shade700,
                          )
                        : _buildModernButton(
                            // Botón para activar el centrado
                            text: traducir(
                                'Centrar y bloquear', _idiomaSeleccionado),
                            icon: Icons.my_location,
                            onPressed: _toggleCentrar,
                          ),
                  ),
                // Menú de incidencias (filtro, listado, etc.)
                if (_mostrarMapa)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: PopupMenuButton<String>(
                        color: obtenerColorFondo(_modoDaltonismo),
                        icon: Icon(Icons.more_vert, color: obtenerColorTexto()),
                        onSelected: (value) {
                          if (value == 'filtro') {
                            _mostrarFiltroIncidencias();
                          } else if (value == 'listado') {
                            _mostrarListadoIncidencias();
                          } else if (value == 'ocultar') {
                            setState(() {
                              _mostrarIncidencias = !_mostrarIncidencias;
                            });
                          } else if (value == 'escaleras') {
                            setState(() {
                              _mostrarEscalerasSinRampa =
                                  !_mostrarEscalerasSinRampa;
                            });
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'filtro',
                            child: Text(
                              traducir(
                                  'Filtrar Incidencias', _idiomaSeleccionado),
                              style: TextStyle(color: obtenerColorTexto()),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'listado',
                            child: Text(
                              traducir('Listado Incidencias Cercanas',
                                  _idiomaSeleccionado),
                              style: TextStyle(color: obtenerColorTexto()),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'ocultar',
                            child: Text(
                              _mostrarIncidencias
                                  ? traducir('Ocultar Incidencias',
                                      _idiomaSeleccionado)
                                  : traducir('Mostrar Incidencias',
                                      _idiomaSeleccionado),
                              style: TextStyle(color: obtenerColorTexto()),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'escaleras',
                            child: Text(
                              _mostrarEscalerasSinRampa
                                  ? traducir(
                                      'Ocultar Escaleras', _idiomaSeleccionado)
                                  : traducir(
                                      'Mostrar Escaleras', _idiomaSeleccionado),
                              style: TextStyle(color: obtenerColorTexto()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Botón "Abrir StreetView" (modo incidencia)
                if (_modoIncidencia && _tappedPosition != null)
                  Positioned(
                    bottom: 180,
                    right: 20,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/streetview_google',
                          arguments: StreetViewArguments(
                            latitude: _tappedPosition!.latitude,
                            longitude: _tappedPosition!.longitude,
                            incidencias: _obtenerIncidencias(),
                            modoDaltonismo: _modoDaltonismo,
                            idiomaSeleccionado: _idiomaSeleccionado,
                            opcionesIncidencia: _opcionesIncidencia,
                          ),
                        );
                        setState(() {
                          _tappedPosition = null;
                          _modoIncidencia = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: obtenerColorBoton(_modoDaltonismo),
                      ),
                      child: Text(
                        traducir('Abrir StreetView', _idiomaSeleccionado),
                        style: TextStyle(color: obtenerColorTextoBoton()),
                      ),
                    ),
                  ),
                // Brújula
                Positioned(
                  top: 220,
                  right: 20,
                  child: _buildCompass(),
                ),
              ],
            );
          },
        );
      },
    );
  }




  // Voy a basar la función en la DISTANCIA DE MANHATTAN
  // Recorta la polilínea para eliminar los puntos que ya se llevan recorridos
  /// Llamo en cada actualización de _ubicacionOrigen
  void _recortarRuta() {
    // 1) Si no tenemos ruta o destino, NADA...
    if (_puntosRuta.isEmpty || _ubicacionDestino == null) return;
    if (_ubicacionOrigen == null) return;

    // 2) Índice del punto de la polilínea más cercano a la ubicación actual.
    int indiceMasCercano = 0;
    double distanciaMin = double.infinity;
    for (int i = 0; i < _puntosRuta.length; i++) {
      double dist = _distancia(_ubicacionOrigen!, _puntosRuta[i]);
      if (dist < distanciaMin) {
        distanciaMin = dist;
        indiceMasCercano = i;
      }
    }

    // 3) Recortamos, quitamos todos los puntos desde 0 hasta indiceMasCercano - 1,
    // así que el primer punto sea "el más cercano o posterior".
    // Para evitar rarezas, comprobamos si indiceMasCercano < ((_puntosRuta.length - )
    if (indiceMasCercano > 0 && indiceMasCercano < _puntosRuta.length) {
      _puntosRuta.removeRange(0, indiceMasCercano);
    }

    // 4) opacinal: ponemos el primer punto EXACTO a la ubicación actual
    // para que el tramo empiece exactamente en tu ubicación.
    if (_puntosRuta.isNotEmpty) {
      _puntosRuta[0] = _ubicacionOrigen!;
    }

    // 5) Recalcular el tiempo estimado para la parte restante.
    //   Lo pueudo hacer con la API o localmente con un cálculo aproximado -> De momento localmente mejor
    _recalcularTiempoRestante();
  }

  /// Cálculo local del tiempo para la parte restante de la ruta.
  void _recalcularTiempoRestante() {
    if (_puntosRuta.length < 2) {
      // Ruta vacía o un solo punto => llegaste
      _tiempoRuta = '0 min';
      setState(() {});
      return;
    }

    // Distancia total que queda
    double distanciaRestante = 0.0;
    for (int i = 0; i < _puntosRuta.length - 1; i++) {
      distanciaRestante += _distancia(_puntosRuta[i], _puntosRuta[i + 1]);
    }

    // Según chatgpt la Velocidad promedio a pie es esta: -> (1.4 m/s = ~5 km/h)
    // Convertiremos metros / (m/s) => segundos => min/h
    double velocidadMporS = 1.4;

    // Tiempo en segundos
    double tiempoSegundos = distanciaRestante / velocidadMporS;
    int horas = (tiempoSegundos ~/ 3600);
    int minutos = ((tiempoSegundos % 3600) ~/ 60);

    String tiempoEstimado = '';
    if (horas > 0) {
      tiempoEstimado += '$horas ${traducir('horas', _idiomaSeleccionado)} ';
    }
    if (minutos > 0) {
      tiempoEstimado += '$minutos ${traducir('minutos', _idiomaSeleccionado)}';
    }
    if (tiempoEstimado.trim().isEmpty) {
      tiempoEstimado = traducir('Menos de un minuto', _idiomaSeleccionado);
    }

    setState(() {
      _tiempoRuta = tiempoEstimado;
    });
  }

  List<IncidenciaData> _obtenerIncidencias() {
    return [];
  }

  Widget _construirPantallaInicio() {
    if (_comprobandoUbicacion) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              traducir('Cargando ubicación...', _idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto(), fontSize: 16),
            ),
            const SizedBox(height: 10),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(obtenerColorTexto()),
            ),
          ],
        ),
      );
    }

    // Usamos un LayoutBuilder para controlar mejor las dimensiones
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Widget de clima en la parte superior (visible solo si _showClimaWidget es true)
            if (_showClimaWidget) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: ClimaWidget(
                  modoDaltonismo: _modoDaltonismo,
                  idiomaSeleccionado: _idiomaSeleccionado,
                  latitud: _ubicacionOrigen?.latitude,
                  longitud: _ubicacionOrigen?.longitude,
                ),
              ),
            ],

            // Widget de chatbot debajo del clima
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: ChatbotWidget(
                modoDaltonismo: _modoDaltonismo,
                idiomaSeleccionado: _idiomaSeleccionado,
                chatbotService: _chatbotService,
                onExpandedChanged: _handleChatbotExpandedChanged,
              ),
            ),

            // Empujo los botones hacia abajo q se pegan
            const Spacer(),

            // Contenedor para los botones en la parte inferior
            // Hueco, que respire, que respire, que respire...
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 30),
              child: _construirBotonesModernos(),
            ),
          ],
        );
      },
    );
  }

// Botones mapa
  Widget _buildModernButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
    bool isSmall = false,
  }) {
    backgroundColor ??= obtenerColorBoton(_modoDaltonismo);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  backgroundColor.withOpacity(0.8),
                  backgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(
              vertical: isSmall ? 8.0 : 12.0,
              horizontal: isSmall ? 12.0 : 16.0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: isSmall ? 16.0 : 20.0,
                ),
                if (!isSmall) const SizedBox(width: 8),
                if (!isSmall)
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// Efectitos modernos
  Widget _construirBotonesModernos() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      // Cambiamos la curva a una que no excede el rango 0.0-1.0
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            // Aseguramos que la opacidad siempre esté en el rango válido
            opacity: value.clamp(0.0, 1.0),
            child: Row(
              children: [
                // Botón "Abrir Mapa" (izquierda)
                Expanded(
                  child: _botonPersonalizado(
                    icono: Icons.map_rounded,
                    texto: traducir('Abrir Mapa', _idiomaSeleccionado),
                    onPressed: _abrirMapa,
                    colorPrincipal: obtenerColorBoton(_modoDaltonismo),
                  ),
                ),

                const SizedBox(width: 20), // Espacio entre botones

                // Botón "Configuración" (abajoderecha)
                Expanded(
                  child: _botonPersonalizado(
                    icono: Icons.settings_rounded,
                    texto: traducir('Configuración', _idiomaSeleccionado),
                    onPressed: _mostrarConfiguracion,
                    colorPrincipal: obtenerColorBoton(_modoDaltonismo),
                    rotacion: true, // El engranaje rotando
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _botonPersonalizado({
    required IconData icono,
    required String texto,
    required VoidCallback onPressed,
    required Color colorPrincipal,
    bool rotacion = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorPrincipal.withOpacity(0.8),
                colorPrincipal,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // El icono puede rotar
                rotacion
                    ? _construirIconoRotanteCorregido(
                        icono, obtenerColorTextoBoton())
                    : Icon(
                        icono,
                        color: obtenerColorTextoBoton(),
                        size: 28, // ligerillo 
                      ),
                const SizedBox(height: 8), //ligero
                // Texto con estilo
                Text(
                  texto,
                  style: TextStyle(
                    color: obtenerColorTextoBoton(),
                    fontWeight: FontWeight.bold,
                    fontSize: 14, // Sutil tamb
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirIconoRotanteCorregido(IconData icono, Color color) {
    // Usamos el controlador de animación _arrowController que ya está configurado con repeat()
    return AnimatedBuilder(
      animation: _arrowController,
      builder: (context, child) {
        // Multiplicamos por un número mayor para hacer la rotación más lenta
        // 0.5 significa que dará una vuelta cada 2 ciclos completos de la animación
        return Transform.rotate(
          angle: _arrowController.value * 0.25 * 2 * 3.14159,
          child: Icon(
            icono,
            color: color,
            size: 28,
          ),
        );
      },
    );
  }

// Efectos pedidos a chatgpt -> Método para construir un botón con efectos visuales modernos
  Widget _construirBotonModerno({
    required IconData icono,
    required String texto,
    required VoidCallback onPressed,
    required Color colorPrincipal,
    bool rotacion = false,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        // Variables para el efecto de presión
        bool isPressed = false;

        return GestureDetector(
          onTapDown: (_) => setState(() => isPressed = true),
          onTapUp: (_) => setState(() => isPressed = false),
          onTapCancel: () => setState(() => isPressed = false),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorPrincipal.withOpacity(0.8),
                  colorPrincipal,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isPressed ? 0.1 : 0.3),
                  blurRadius: isPressed ? 5 : 15,
                  offset: isPressed ? const Offset(0, 2) : const Offset(0, 8),
                  spreadRadius: isPressed ? 0 : 1,
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            transform: Matrix4.identity()
              ..translate(0.0, isPressed ? 4.0 : 0.0, 0.0)
              ..scale(isPressed ? 0.98 : 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // El icono puede rotar si se especifica
                rotacion
                    ? _construirIconoRotante(icono, obtenerColorTextoBoton())
                    : Icon(
                        icono,
                        color: obtenerColorTextoBoton(),
                        size: 32,
                      ),
                const SizedBox(height: 10),
                // Texto con efecto de brillo (shimmer)
                _construirTextoConBrillo(texto),
              ],
            ),
          ),
        );
      },
    );
  }

// Método para crear un ícono que rota suavemente
  Widget _construirIconoRotante(IconData icono, Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 2 * 3.14159),
      duration: const Duration(seconds: 10),
      builder: (context, value, child) {
        return Transform.rotate(
          angle: value,
          child: Icon(
            icono,
            color: color,
            size: 32,
          ),
        );
      },
      // Hace que la animación se repita indefinidamente
      onEnd: () => {},
    );
  }

// Método para crear texto con efecto de brillo
  Widget _construirTextoConBrillo(String texto) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.white.withOpacity(0.8),
            Colors.white,
          ],
          stops: const [0.0, 0.5, 1.0],
          tileMode: TileMode.mirror,
        ).createShader(bounds);
      },
      child: Text(
        texto,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _mostrarConfiguracion() {
    String modoSeleccionado = _modoDaltonismo;
    String idiomaSeleccionado = _idiomaSeleccionado;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: obtenerColorFondo(_modoDaltonismo),
          title: Text(
            traducir('Configuración Daltonismo', _idiomaSeleccionado),
            style: TextStyle(color: obtenerColorTexto()),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: modoSeleccionado,
                decoration: InputDecoration(
                  labelText: traducir('Modo', _idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                ),
                dropdownColor: obtenerColorFondo(_modoDaltonismo),
                items: [
                  DropdownMenuItem(
                    value: 'por_defecto',
                    child: Text(
                      traducir('Por defecto', _idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'protanopia',
                    child: Text(
                      'Protanopia',
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'deuteranopia',
                    child: Text(
                      'Deuteranopia',
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'tritanopia',
                    child: Text(
                      'Tritanopia',
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    modoSeleccionado = value;
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: idiomaSeleccionado,
                decoration: InputDecoration(
                  labelText: traducir('Idioma', _idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                ),
                dropdownColor: obtenerColorFondo(_modoDaltonismo),
                items: _idiomas.map((lang) {
                  return DropdownMenuItem(
                    value: lang,
                    child: Text(
                      lang.toUpperCase(),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    idiomaSeleccionado = value;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                traducir('Cancelar', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTexto()),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: obtenerColorBoton(_modoDaltonismo),
              ),
              onPressed: () {
                setState(() {
                  _modoDaltonismo = modoSeleccionado;
                  _idiomaSeleccionado = idiomaSeleccionado;
                });
                Navigator.of(context).pop();
              },
              child: Text(
                traducir('Aceptar', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTextoBoton()),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarFiltroIncidencias() {
    String? filtroSeleccionado = _filtroIncidencia;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: obtenerColorFondo(_modoDaltonismo),
          title: Text(
            traducir('Filtrar por tipo', _idiomaSeleccionado),
            style: TextStyle(color: obtenerColorTexto()),
          ),
          content: DropdownButtonFormField<String>(
            value: filtroSeleccionado,
            decoration: InputDecoration(
              labelText: traducir('Tipo', _idiomaSeleccionado),
              labelStyle: TextStyle(color: obtenerColorTexto()),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: obtenerColorBorde()),
              ),
            ),
            dropdownColor: obtenerColorFondo(_modoDaltonismo),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: null,
                child: Text(
                  traducir('Todos', _idiomaSeleccionado),
                  style: TextStyle(color: obtenerColorTexto()),
                ),
              ),
              ..._opcionesIncidencia.map((tipo) {
                return DropdownMenuItem(
                  value: tipo,
                  child: Text(
                    traducir(tipo, _idiomaSeleccionado),
                    style: TextStyle(color: obtenerColorTexto()),
                  ),
                );
              }),
            ],
            onChanged: (value) {
              filtroSeleccionado = value;
            },
          ),
          actions: [
            TextButton(
              child: Text(
                traducir('Cancelar', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTexto()),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: obtenerColorBoton(_modoDaltonismo),
              ),
              onPressed: () {
                setState(() {
                  _filtroIncidencia = filtroSeleccionado;
                });
                Navigator.of(context).pop();
              },
              child: Text(
                traducir('Aceptar', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTextoBoton()),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mostrarListadoIncidencias() async {
    await mostrarListadoIncidencias(
      _ubicacionOrigen,
      _filtroIncidencia,
      _asistenteVirtual,
      _modeloIA,
      context,
      _modoDaltonismo,
      _idiomaSeleccionado,
      setState,
    );
  }

  String _getNombreMes(int month) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    return meses[(month - 1) % 12];
  }

  // Control de ejecución para evitar predicciones simultáneas no le vaya a dar el usuario 7 veces al boton
  bool _analisisEnProgreso = false;

  // BOTON PREDICCION GLOBAL + DESGLOSAR
  Future<void> _mostrarPrediccion() async {
    // Verificar si ya hay un análisis en progreso
    if (_analisisEnProgreso) {
      print('Un análisis ya está en curso. Ignorando nueva solicitud.');
      return;
    }
    _analisisEnProgreso = true;

    try {
      print('Botón "Hacer Predicción" presionado.');

      if (_ubicacionOrigen == null || _ubicacionDestino == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Por favor, selecciona origen y destino antes de ver la predicción.',
            ),
          ),
        );
        print('Origen o destino no seleccionado.');
        return;
      }

      if (!_modeloIA.modeloCargado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Los modelos aún se están cargando. Por favor, espera un momento.',
            ),
          ),
        );
        print('Modelos aún no cargados.');
        return;
      }

      DateTime ahora = DateTime.now();
      print('Fecha y hora actual: $ahora');

      // CÁLCULO de la probabilidad global de la ruta
      double probRuta = await _predecirIncidenciaRuta(ahora);
      print('Probabilidad de incidencia en la ruta: $probRuta');

      int porcentaje = (probRuta * 100).round();
      String diaSemana = _obtenerNombreDiaSemana(ahora.weekday);

      String comentarioTramos = '';
      if (probRuta > 0.1) {
        comentarioTramos =
            ' En algunos tramos específicos del recorrido, esta probabilidad podría elevarse aún más, alcanzando incluso valores superiores al promedio. ';
      }

      String mes = _getNombreMes(ahora.month);

      String mensaje =
          'Hay una probabilidad de $porcentaje% de que ocurra una incidencia '
          'durante el $diaSemana o a lo largo del mes de $mes.$comentarioTramos'
          'Considera evaluar rutas alternativas, o viajar con mayor precaución. '
          'Si se detectan tramos con mayor riesgo, el sistema puede sugerir recalcular la ruta para evitarlos.';

      print('Mensaje de predicción: $mensaje');

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              'Predicción de Incidencias',
              style: TextStyle(color: Colors.red),
            ),
            content: Text(
              mensaje,
              style: TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // Cerramos el AlertDialog actual
                  Navigator.of(context).pop();

                  // Muestro el desglose de la predicción
                  _desglosarTramosRuta();
                },
                child: Text('Desglosar predicción'),
              ),
            ],
          );
        },
      );
    } catch (e, stacktrace) {
      print('Error en _mostrarPrediccion: $e');
      print(stacktrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ocurrió un error al mostrar la predicción: $e'),
        ),
      );
    } finally {
      // Libero el bloqueo para permitir nuevas predicciones (Ya le puede dar 7 veces otra vez)
      _analisisEnProgreso = false;
    }
  }

  void _desglosarTramosRuta() {
    if (_puntosSubdivididos3D.isEmpty || _probabilidadesTramos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay datos para desglosar. ¿Hiciste la predicción primero?',
          ),
        ),
      );
      return;
    }

    // Abrimos el pseudo-3D con lo que ya calculamos
    _mostrarDialogo3DTramos(_puntosSubdivididos3D, _probabilidadesTramos);
  }

  /// Muestra un diálogo con pseudo-3D, listado de tramos peligrosos,
  /// y flechas/círculos dibujados con un CustomPainter + InteractiveViewer.
  void _mostrarDialogo3DTramos(
    List<LatLng> puntosRuta3D,
    List<double> probabilidades,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          child: SizedBox(
            width: 320,
            height: 420,
            child: AnimatedBuilder(
              animation: _arrowAnimation,
              builder: (ctx, _) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Tramos Peligrosos (vista 3D)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: InteractiveViewer(
                        boundaryMargin: const EdgeInsets.all(20),
                        minScale: 0.5,
                        maxScale: 5.0,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateX(0.3),
                          child: CustomPaint(
                            // TURBO IMPORTANTE-> Size.infinite para ocupar todo el Expanded
                            size: Size.infinite,
                            painter: _Tramos3DPainter(
                              puntosRuta: puntosRuta3D,
                              probabilidades: probabilidades,
                              animationValue: _arrowAnimation.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// FUNCIÓN PARA SUBDIVIDIR LA RUTA REAL EN 20 TRAMOS y analizar la IA la peligrosidad de cada uno de ellos
  Future<List<LatLng>> _segmentarRutaCompleta(
      List<LatLng> rutaCompleta, int numTramos) async {
    if (rutaCompleta.length < 2) return rutaCompleta;

    const Distance distCalc = Distance();
    // (1) Calculamos la distancia total
    double distanciaTotal = 0.0;
    for (int i = 0; i < rutaCompleta.length - 1; i++) {
      distanciaTotal += distCalc(rutaCompleta[i], rutaCompleta[i + 1]);
    }

    // Evitamos división entre cero q la indeterminación me crashea la app
    if (distanciaTotal <= 0) return rutaCompleta;

    // (2) Definimos la longitud de cada subtramo (en metros)
    double paso = distanciaTotal / numTramos;

    List<LatLng> resultado = [];
    resultado.add(rutaCompleta.first); // Primer punto

    double distanciaAcumulada = 0.0;
    double distanciaObjetivo = paso;
    int idxSegmento = 1;

    // (3) Recorremos la ruta original, sumando tramos hasta
    // alcanzar la distanciaObjetivo, e interpolamos un nuevo punto.
    for (int i = 0; i < rutaCompleta.length - 1; i++) {
      LatLng puntoActual = rutaCompleta[i];
      LatLng puntoSiguiente = rutaCompleta[i + 1];
      double distEntrePuntos = distCalc(puntoActual, puntoSiguiente);

      if ((distanciaAcumulada + distEntrePuntos) < distanciaObjetivo) {
        // Todavía no llegamos a la distanciaObjetivo
        distanciaAcumulada += distEntrePuntos;
      } else {
        // Recorremos la distancia necesaria para llegar a distanciaObjetivo
        while ((distanciaAcumulada + distEntrePuntos) >= distanciaObjetivo) {
          double resto = distanciaObjetivo - distanciaAcumulada;
          double proporcion = resto / distEntrePuntos;

          double latInterpolada = puntoActual.latitude +
              proporcion * (puntoSiguiente.latitude - puntoActual.latitude);
          double lngInterpolada = puntoActual.longitude +
              proporcion * (puntoSiguiente.longitude - puntoActual.longitude);
          LatLng puntoInterpolado = LatLng(latInterpolada, lngInterpolada);

          resultado.add(puntoInterpolado);
          idxSegmento++;

          distanciaObjetivo = paso * idxSegmento;

          if (idxSegmento > numTramos) {
            // Ya tenemos los 20 (o numTramos) segmentos
            break;
          }
        }
        // Ahora sumamos el distEntrePuntos, porque ya hemos "consumido" parte.
        distanciaAcumulada += distEntrePuntos;
      }

      if (idxSegmento > numTramos) {
        break;
      }
    }

    // Nos aseguramos de añadir el último punto (destino)
    if (resultado.last != rutaCompleta.last) {
      resultado.add(rutaCompleta.last);
    }

    return resultado;
  }

  Future<double> _predecirIncidenciaRuta(DateTime dayTime) async {
    // 1) Verifico que tenemos una ruta (puntos) calculada
    if (_puntosRuta.isEmpty) {
      print('No hay _puntosRuta, no se puede predecir.');
      return 0.0;
    }

    // 2) La subdividimos la ruta en 20 sub-tramos
    List<LatLng> subTramos = await _segmentarRutaCompleta(_puntosRuta, 20);

    try {
      // 3) Llamammos a analizarRuta una sola vez para todos los subtramos
      List<double> probabilidadesRaw =
          await _asistenteVirtual.analizarRuta(subTramos);

      // 4) Guardamos resultados y calcular probabilidad promedio
      List<double> probabilidades = probabilidadesRaw;

      // Calculamos el promedio de probabilidades (0..100)
      if (probabilidades.isEmpty) {
        print(
            'No se obtuvieron probabilidades, devolviendo 0.0'); // si no hay el desglose de la predicción es el último realizado
        return 0.0;
      }

      double promedio =
          probabilidades.reduce((a, b) => a + b) / probabilidades.length;
      double resultado = promedio / 100.0; // Convertir de 0..100 a 0..1

      // Actualizar el estado para que los datos estén disponibles para la UI
      setState(() {
        _probabilidadesTramos = probabilidades;
        _puntosSubdivididos3D = subTramos;
      });

      print('Probabilidad de incidencia en la ruta: $resultado');
      return resultado;
    } catch (e) {
      print('Error al analizar los subTramos: $e');
      return 0.0;
    }
  }

  // Función original para segmentar una LÍNEA recta entre 2 puntos
  ///La mantenemos SIN ELIMINARLA por si se necesita
  Future<List<LatLng>> _segmentarRuta(LatLng origen, LatLng destino,
      {int numPuntos = 10}) async {
    List<LatLng> puntos = [];
    double latStep = (destino.latitude - origen.latitude) / (numPuntos + 1);
    double lngStep = (destino.longitude - origen.longitude) / (numPuntos + 1);
    for (int i = 1; i <= numPuntos; i++) {
      double lat = origen.latitude + (latStep * i);
      double lng = origen.longitude + (lngStep * i);
      puntos.add(LatLng(lat, lng));
    }
    return puntos;
  }

  // Función para mostrar el diálogo de peligro (simplificada)
  Future<void> _mostrarDialogoPeligro(
    double probRuta,
  ) async {
    String detallesTramos = ''; // ESTE MENSAJE LO DEJO VACÍO DE MOMENTO.

    bool cambiarRuta = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(
                traducir('Peligro detectado en la ruta', _idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTexto()),
              ),
              backgroundColor: obtenerColorFondo(_modoDaltonismo),
              content: Text(
                '${traducir('Probabilidad general de incidencia:', _idiomaSeleccionado)} '
                '${(probRuta * 100).toStringAsFixed(0)}%\n\n'
                '$detallesTramos',
                style: TextStyle(color: obtenerColorTexto()),
              ),
              actions: [
                TextButton(
                  child: Text(
                    traducir('No', _idiomaSeleccionado),
                    style: TextStyle(color: obtenerColorTexto()),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: obtenerColorBoton(_modoDaltonismo),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: Text(
                    traducir('Sí, evitar peligro', _idiomaSeleccionado),
                    style: TextStyle(color: obtenerColorTextoBoton()),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _crearCampoBusqueda(
    TextEditingController controlador,
    String label,
    List<String> sugerencias,
    bool esOrigen,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: controlador,
              style: TextStyle(color: obtenerColorTexto()),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: obtenerColorTexto()),
                prefixIcon: Icon(
                  Icons.search,
                  color: obtenerColorIcono(_modoDaltonismo),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: obtenerColorBorde()),
                ),
                filled: true,
                fillColor: obtenerColorCampo(),
              ),
              onChanged: (valor) =>
                  _buscarSugerenciasUbicacion(valor, esOrigen),
            ),
            if (_cargandoSugerencias)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (sugerencias.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: obtenerColorFondo(_modoDaltonismo),
              border: Border.all(color: obtenerColorBorde()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: sugerencias.map((s) {
                return InkWell(
                  onTap: () =>
                      _seleccionarUbicacionSugerida(s.split(' (')[0], esOrigen),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    height: MediaQuery.of(context).size.height * 0.06,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      s,
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // Ahora toda la construucción del mapa, llamando a cada función, colocando cada botón y dandole estilo
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: obtenerColorFondo(_modoDaltonismo),
      appBar: AppBar(
        title: Text(
          _ciudadActual,
          style: TextStyle(color: obtenerColorTextoBoton()),
        ),
        centerTitle: true,
        backgroundColor: obtenerColorBoton(_modoDaltonismo),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add_alert,
              color: _modoIncidencia
                  ? obtenerColorResaltado(
                      _modoDaltonismo, _modoIncidencia, _modoDestino)
                  : obtenerColorTextoBoton(),
            ),
            tooltip: traducir('Añadir incidencia', _idiomaSeleccionado),
            onPressed: () {
              setState(() {
                _modoIncidencia = true;
                _modoDestino = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: obtenerColorWarning(_modoDaltonismo),
                  content: Text(
                    traducir('Haz click en el mapa para añadir una incidencia.',
                        _idiomaSeleccionado),
                    style: TextStyle(color: obtenerColorTexto()),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.location_on,
              color: _modoDestino
                  ? obtenerColorResaltado(
                      _modoDaltonismo, _modoIncidencia, _modoDestino)
                  : obtenerColorTextoBoton(),
            ),
            tooltip:
                traducir('Seleccionar destino en el mapa', _idiomaSeleccionado),
            onPressed: () {
              setState(() {
                _modoDestino = true;
                _modoIncidencia = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: obtenerColorWarning(_modoDaltonismo),
                  content: Text(
                    traducir(
                        'Haz click en el mapa para seleccionar el destino.',
                        _idiomaSeleccionado),
                    style: TextStyle(color: obtenerColorTexto()),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.insights, color: obtenerColorTextoBoton()),
            tooltip: 'Ver Predicción',
            onPressed: _modeloIA.modeloCargado ? _mostrarPrediccion : null,
          ),
          IconButton(
            icon: Icon(Icons.logout, color: obtenerColorTextoBoton()),
            tooltip: traducir('Cerrar Sesión', _idiomaSeleccionado),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
          if (_mostrarMapa)
            IconButton(
              icon: Icon(Icons.clear, color: obtenerColorTextoBoton()),
              tooltip: traducir('Limpiar Ruta', _idiomaSeleccionado),
              onPressed: () {
                setState(() {
                  _ubicacionOrigen = null;
                  _ubicacionDestino = null;
                  _puntosRuta = [];
                  _controladorUbicacionOrigen.clear();
                  _controladorUbicacionDestino.clear();
                  _tiempoRuta = '';
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _mostrarMapa ? _construirMapa() : _construirPantallaInicio(),
          ),
        ],
      ),
      // Boto´n flotante fuera
      floatingActionButton: null,
    );
  }
}

extension on MapEventRotate {
  get rotationAngle => null;
}

// CUSTOM PAINTER (Refactorizado para eliminar TramoPeligroso)
class _Tramos3DPainter extends CustomPainter {
  final List<LatLng> puntosRuta; // Ruta subdividida (N puntos)
  final List<double> probabilidades; // Probabilidades en %
  final double animationValue; // 0..1 para animar flecha

  // Umbral para determinar la peligrosidad
  final double UMBRAL = 20.0;

  _Tramos3DPainter({
    required this.puntosRuta,
    required this.probabilidades,
    required this.animationValue,
  });

  // Mapeo la probabilidad a un color base (verde, naranja o rojo), las prob son completamente a ojo para ofrecer un color, considero que menos del 15 debe ser verde.
  Color _colorDeProb(double prob) {
    // prob viene en [0..100]
    // Esto me lo invento, no es científico, he supuesto que a partir de 15 ya naranja, y de 60 rojo
    if (prob < 15) {
      return const Color(0xFF2E7D32); // verde
    } else if (prob < 60) {
      return const Color(0xFFFFA000); // naranja
    } else {
      return const Color(0xFFD32F2F); // rojo
    }
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // Dibuja el fondo gris claro
    final rectFondo = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    final paintFondo = ui.Paint()..color = const ui.Color(0xFFEEEEEE);
    canvas.drawRect(rectFondo, paintFondo);

    if (puntosRuta.length < 2) return;

    // Calculo los mínimos y máximos de latitud y longitud
    double minLat =
        puntosRuta.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat =
        puntosRuta.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng =
        puntosRuta.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng =
        puntosRuta.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;

    // Evitamos división por cero
    // En lugar de hacer shader, dart me ofrece representar el tramo con formulas sencillas
    // Si la diferencia es cero, le asignamos un valor mínimo
    // para evitar problemas de escala
    // y asegurar que la ruta se dibuje correctamente
    // (esto es un truco)
    if (latDiff == 0) latDiff = 0.000001;
    if (lngDiff == 0) lngDiff = 0.000001;

    // Factor de escalado (~80% del tamaño disponible)
    double scaleX = (size.width * 0.8) / lngDiff;
    double scaleY = (size.height * 0.8) / latDiff;
    double scale = scaleX < scaleY ? scaleX : scaleY;

    // Offset para centrar la ruta en el canvas popup
    double offsetX = (size.width - (lngDiff * scale)) / 2;
    double offsetY = (size.height - (latDiff * scale)) / 2;

    // Recorrer cada subtramo consecutivo
    for (int i = 0; i < puntosRuta.length - 1; i++) {
      final p1 = puntosRuta[i];
      final p2 = puntosRuta[i + 1];

      double x1 = offsetX + (p1.longitude - minLng) * scale;
      double y1 = offsetY + (maxLat - p1.latitude) * scale;
      double x2 = offsetX + (p2.longitude - minLng) * scale;
      double y2 = offsetY + (maxLat - p2.latitude) * scale;

      final o1 = ui.Offset(x1, y1);
      final o2 = ui.Offset(x2, y2);

      double prob = probabilidades[i]; // 0..100

      // línea del tramo
      final paintLinea = ui.Paint()
        ..color = _colorDeProb(prob)
        ..strokeWidth = 3.0
        ..style = ui.PaintingStyle.stroke;
      canvas.drawLine(o1, o2, paintLinea);

      // Punto medio del tramo
      final mid = ui.Offset((x1 + x2) / 2, (y1 + y2) / 2);

      // Flecha:
      // - si prob >= UMBRAL => flecha grande, animada, + círculo
      // - si prob < UMBRAL  => flecha pequeña, fija, sin círculo
      if (prob >= UMBRAL) {
        // Círculo rojo
        final paintCirculo = ui.Paint()..color = Colors.red;
        canvas.drawCircle(mid, 6.0, paintCirculo);

        // Calculamos posición animada de la flecha
        double offsetYFlecha = (animationValue * 10.0) - 5.0;
        final flechaPos = mid.translate(0, offsetYFlecha - 15.0);

        // Path de la flecha
        final pathFlecha = ui.Path()
          ..moveTo(flechaPos.dx - 6, flechaPos.dy - 6)
          ..lineTo(flechaPos.dx + 6, flechaPos.dy - 6)
          ..lineTo(flechaPos.dx, flechaPos.dy + 6)
          ..close();

        final paintFlecha = ui.Paint()..color = Colors.red;
        canvas.drawPath(pathFlecha, paintFlecha);
      } else {
        // Flecha gris
        final flechaPos = mid.translate(0, -15.0);

        final pathFlecha = ui.Path()
          ..moveTo(flechaPos.dx - 4, flechaPos.dy - 4)
          ..lineTo(flechaPos.dx + 4, flechaPos.dy - 4)
          ..lineTo(flechaPos.dx, flechaPos.dy + 4)
          ..close();

        final paintFlecha = ui.Paint()..color = Colors.grey;
        canvas.drawPath(pathFlecha, paintFlecha);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
