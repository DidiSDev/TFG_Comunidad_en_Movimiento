import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;


// Regresiones y ajuste de pesos para el modelo (w y b). Funciona mejor a ojo que con la regresión lineal al tener tan pocos datos.
// ES DECIR, !!!!!!!!!!!!!!!!IMPORTANTE!!!!!!!!!!!!!!!!!!!!!! SE DEBE AÑADIR LA FUNCIÓN DE REGRESIÓN LINEAL CUANDO HAYA + 1000 INCIDENCIAS REGISTRADAS
class FeatureScaler {
  late List<double> mean;
  late List<double> scale;
  bool loaded = false;

  Future<void> loadScalerParams(String path) async {
    String jsonString = await rootBundle.loadString(path);
    Map<String, dynamic> jsonMap = json.decode(jsonString);

    final List<dynamic> meanList = jsonMap['mean'];
    final List<dynamic> scaleList = jsonMap['scale'];

    mean = meanList.map<double>((e) => (e as num).toDouble()).toList();
    scale = scaleList.map<double>((e) => (e as num).toDouble()).toList();
    loaded = true;
  }

  List<double> transform(List<double> input) {
    if (!loaded) {
      throw Exception("Scaler not loaded.");
    }
    if (input.length != mean.length) {
      throw Exception("Input length does not match mean/scale length.");
    }

    List<double> result = [];
    for (int i = 0; i < input.length; i++) {
      double scaled = (input[i] - mean[i]) / scale[i];
      result.add(scaled);
    }
    return result;
  }
}
