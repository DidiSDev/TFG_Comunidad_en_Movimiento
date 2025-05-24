import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:comunidad_en_movimiento/models/ruta.dart';
import 'package:comunidad_en_movimiento/utils/constants.dart';
import 'package:comunidad_en_movimiento/ia/feature_scaler.dart'; // Importamos el scaler

class ModeloIA {
  late Interpreter _interpreter;
  bool _modeloCargado = false;

  Map<String, int> _zonaMap = {};
  Map<String, double> _zonaDensityMap = {};
  final FeatureScaler _featureScaler = FeatureScaler(); // Le instanciamos

  bool get modeloCargado => _modeloCargado;

  Future<void> cargarModelo(String modelPath, String zonaMapPath) async {
    if (!_modeloCargado) {
      try {
        _interpreter = await Interpreter.fromAsset(modelPath);
        print('Modelo cargado correctamente desde $modelPath');

        String jsonString = await rootBundle.loadString(zonaMapPath);
        Map<String, dynamic> jsonMap = json.decode(jsonString);
        _zonaMap = jsonMap.map((key, value) => MapEntry(key.toLowerCase(), value as int));
        print('Zona map cargado correctamente desde $zonaMapPath');

        String densityString = await rootBundle.loadString('assets/zona_density.json');
        Map<String, dynamic> densityMap = json.decode(densityString);
        _zonaDensityMap = densityMap.map((key, value) => MapEntry(key.toLowerCase(), (value as num).toDouble()));
        print('Zona density map cargado correctamente desde zona_density.json');

        // Cargar los parámetros del scaler
        await _featureScaler.loadScalerParams('assets/scaler_params.json');
        print('Scaler cargado correctamente desde assets/scaler_params.json');

        _modeloCargado = true;
      } catch (e) {
        print('Error al cargar el modelo o mapas: $e');
        rethrow;
      }
    }
  }

  int getZonaCod(String zona) {
    int zonaCod = _zonaMap[zona.toLowerCase()] ?? -1;
    print('Zona: $zona, ZonaCod: $zonaCod');
    return zonaCod;
  }

  double getZonaDensidad(String zona) {
    double densidad = _zonaDensityMap[zona.toLowerCase()] ?? 0.0;
    print('Zona: $zona, DensidadZona: $densidad');
    return densidad;
  }

  String asignarZona(double lat, double lng) {
    int zonaX = ((lng - lngMin) / tamanoCuadricula).floor();
    int zonaY = ((lat - latMin) / tamanoCuadricula).floor();

    if (zonaX < 0) zonaX = 0;
    if (zonaX > 49) zonaX = 49; 
    if (zonaY < 0) zonaY = 0;
    if (zonaY > 49) zonaY = 49;  

    String zona = 'zona_${zonaX}_$zonaY';
    print('Asignada Zona: $zona para lat: $lat, lng: $lng');
    return zona;
  }

  Future<double> predecirProbabilidad(Ruta ruta) async {
    if (!_modeloCargado) {
      throw Exception("Modelo no cargado.");
    }

    int zonaCod = getZonaCod(ruta.zona);
    if (zonaCod == -1) {
      print("Zona desconocida: ${ruta.zona}");
      throw Exception("Zona desconocida: ${ruta.zona}");
    }

    double densidadZona = getZonaDensidad(ruta.zona);

    // DATOS CRUDOS
    List<double> inputRaw = [
      ruta.latNorm,
      ruta.lngNorm,
      ruta.catAcc.toDouble(),
      ruta.month.toDouble(),
      ruta.weekday.toDouble(),
      zonaCod.toDouble(),
      ruta.distMinPoi,
      densidadZona
    ];

    print('Entradas modelo (crudas): $inputRaw');

    // Escalamos los datos
    List<double> inputScaled = _featureScaler.transform(inputRaw);
    print('Entradas modelo (escaladas): $inputScaled');

    List<List<double>> input = [inputScaled];
    List<List<double>> output = List.generate(1, (_) => List.filled(1, 0.0));

    try {
      _interpreter.run(input, output);
      print('Salida del modelo: $output');
    } catch (e) {
      print('Error al ejecutar el modelo: $e');
      throw Exception('Error al ejecutar el modelo: $e');
    }

//DE MOMENTO ESTO QUEDA FALSO Y LO QUITAMOS, YA SABEMOS POR QUÉ LA IA NO PASABA DEL 3% EN SUS PREDICCIONES
    // Ajuste de la probabilidad
// double probabilidadAjustada;
// if (output[0][0] > 0.5) {
//   probabilidadAjustada = output[0][0] * 100; // Multiplica por 100 si es mayor a 0.5%
// } else {
//   probabilidadAjustada = output[0][0] * 20; // Multiplica por 10 si es menor o igual a 0.5%
// }
// LA REGRESIÓN LINEAL NO FUNCIONA, LO QUE HAY QUE HACER ES AJUSTAR EL PESO DE LA SALIDA DEL MODELO qUE YA ES UN VALOR ENTRE 0 Y 1

double probabilidadAjustada = output[0][0]; 


// Imprimir probabilidad ajustada
print('Probabilidad ajustada: ${probabilidadAjustada.toStringAsFixed(2)}%');
return probabilidadAjustada;

  }
}
