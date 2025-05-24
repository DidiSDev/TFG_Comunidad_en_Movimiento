import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:comunidad_en_movimiento/ia/modelo_ia.dart';
import 'package:comunidad_en_movimiento/models/ruta.dart';
// import 'package:comunidad_en_movimiento/models/tramo_peligroso.dart'; // Eliminado de momento
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'package:comunidad_en_movimiento/utils/constants.dart';

class AsistenteVirtualIA {
  final ModeloIA modeloIA;
  final FlutterTts flutterTts = FlutterTts();

  // Lista de Puntos de Interés (POIs)
  final List<Map<String, dynamic>> POIs = [
    {'nombre': 'Estación de Policía', 'lat': 40.9680, 'lng': -5.6630},
    {'nombre': 'Hospital', 'lat': 40.9740, 'lng': -5.6550},
  ];

  // Mapa para almacenar la densidad de zonas
  Map<String, double> zonaDensity = {};

  AsistenteVirtualIA(this.modeloIA) {
    cargarZonaDensity();
  }

  /// Carga los parámetros de densidad desde zona_density.json
  Future<void> cargarZonaDensity() async {
    try {
      String jsonString = await rootBundle.loadString('assets/zona_density.json');
      Map<String, dynamic> jsonMap = json.decode(jsonString);
      zonaDensity = jsonMap.map((key, value) => MapEntry(key, (value as num).toDouble()));
      print('zona_density.json cargado correctamente.');
    } catch (e) {
      print('Error al cargar zona_density.json: $e');
    }
  }

  /// Asigna una zona basada en latitud y longitud normalizadas
  String asignarZona(double lat, double lng) {
    // Corregir la asignación: lng se relaciona con lngMin, lat con latMin
    int zonaX = ((lng - lngMin) / tamanoCuadricula).floor();
    int zonaY = ((lat - latMin) / tamanoCuadricula).floor();

    // Aseguramos que zonaX y zonaY estén dentro de los límites
    zonaX = zonaX.clamp(0, 49); // según el número total de zonas
    zonaY = zonaY.clamp(0, 49);

    String zona = 'zona_${zonaX}_$zonaY';
    print('Asignada Zona: $zona para lat: $lat, lng: $lng');
    return zona;
  }

  /// Calcula la distancia mínima a los POIs
  double calcularDistanciaMinima(double lat, double lng) {
    double minDist = double.infinity;
    for (var poi in POIs) {
      double dist = _haversineDistance(lat, lng, poi['lat']!, poi['lng']!);
      if (dist < minDist) {
        minDist = dist;
      }
    }
    return minDist;
  }

  /// Combina incidencias de ambas colecciones y calcula densidad total
  Future<double> calcularDensidadTotal(String zona) async {
    QuerySnapshot snapshotIncidencias =
        await FirebaseFirestore.instance.collection('incidencias').get();
    QuerySnapshot snapshotTotal =
        await FirebaseFirestore.instance.collection('total_incidencias').get();

    int incidenciasZona = 0;

    for (var doc in [...snapshotIncidencias.docs, ...snapshotTotal.docs]) {
      if (doc['zona'] == zona) {
        incidenciasZona += 1;
      }
    }
    print("Incidencias en mapa: ${snapshotIncidencias.docs.length}");
    print("Incidencias totales: ${snapshotTotal.docs.length}");
    return incidenciasZona.toDouble(); // Devuelve densidad en esta zona
  }

  // Calcula la distancia usando la fórmula de Haversine
  double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double R = 6371000; // Radio de la Tierra en metros
    double phi1 = lat1 * pi / 180;
    double phi2 = lat2 * pi / 180;
    double deltaPhi = (lat2 - lat1) * pi / 180;
    double deltaLambda = (lng2 - lng1) * pi / 180;

    double a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    double distance = R * c;
    return distance;
  }

  //REVISO RUTA y retorno una lista de probabilidades por tramo
  Future<List<double>> analizarRuta(List<LatLng> puntosRuta) async {
    List<double> probabilidades = [];

    DateTime ahora = DateTime.now();
    int month = ahora.month;
    int weekday = ahora.weekday - 1;
    if (weekday < 0) weekday = 6;

    for (int i = 0; i < puntosRuta.length; i++) {
      LatLng punto = puntosRuta[i];
      double lat = punto.latitude;
      double lng = punto.longitude;

      String zona = asignarZona(lat, lng);
      double distMinPoi = calcularDistanciaMinima(lat, lng);

      // densidad de la zona desde zona_density.json
      double densidadZona = await calcularDensidadTotal(zona);

      Ruta ruta = Ruta(
        lat: lat,
        lng: lng,
        catAcc: 1, 
        month: month,
        weekday: weekday,
        zona: zona,
        distMinPoi: distMinPoi,
        densidadZona: densidadZona,
      );

      double probabilidad = await modeloIA.predecirProbabilidad(ruta);
      print("Probabilidad tramo ${i + 1}: ${(probabilidad * 100).toStringAsFixed(2)}%");

    
      // depuro:
      print('Tramo ${i + 1}: prob = ${(probabilidad * 100).toStringAsFixed(2)}%');

      probabilidades.add(probabilidad * 100); // Almacena la probabilidad como porcentaje
    }

    print('Total de probabilidades calculadas: ${probabilidades.length}');
    return probabilidades;
  }

  /// Calcula la densidad de incidencias usando zona_density.json
  Future<double> calcularDensidadIncidentes(String zona) async {
    return zonaDensity[zona] ?? 0.0;
  }

  /// Función para hablar texto
  Future<void> hablar(String texto) async {
    await flutterTts.speak(texto);
  }
}
