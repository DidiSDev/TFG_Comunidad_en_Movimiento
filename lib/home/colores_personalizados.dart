import 'package:flutter/material.dart';

Color obtenerColorTexto() {
  return Colors.black;
}

Color obtenerColorFondo(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.grey.shade100;
    case 'deuteranopia':
      return Colors.grey.shade200;
    case 'tritanopia':
      return Colors.grey.shade300;
    default:
      return Colors.white;
  }
}

Color obtenerColorCampo() {
  return Colors.white;
}

Color obtenerColorBorde() {
  return Colors.grey;
}

Color obtenerColorBoton(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.brown;
    case 'deuteranopia':
      return Colors.green.shade700;
    case 'tritanopia':
      return Colors.purple.shade300;
    default:
      return Colors.blue.shade700;
  }
}

Color obtenerColorTextoBoton() {
  return Colors.white;
}

Color obtenerColorResaltado(
    String modoDaltonismo, bool modoIncidencia, bool modoDestino) {
  if (modoIncidencia || modoDestino) {
    if (modoDaltonismo == 'deuteranopia') {
      return Colors.blue.shade700;
    } else {
      return Colors.greenAccent.shade400;
    }
  } else {
    return Colors.blueAccent;
  }
}

Color obtenerColorIcono(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.brown.shade800;
    case 'deuteranopia':
      return Colors.blueGrey.shade800;
    case 'tritanopia':
      return Colors.purple.shade800;
    default:
      return Colors.blueGrey.shade800;
  }
}

Color obtenerColorMiUbicacion(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.brown;
    case 'deuteranopia':
      return Colors.teal;
    case 'tritanopia':
      return Colors.purple;
    default:
      return Colors.blue;
  }
}

Color obtenerColorDestino(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.pink.shade600;
    case 'deuteranopia':
      return Colors.amber.shade700;
    case 'tritanopia':
      return Colors.pinkAccent.shade400;
    default:
      return Colors.red;
  }
}

Color obtenerColorRuta(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.brown.shade700;
    case 'deuteranopia':
      return Colors.blueGrey.shade700;
    case 'tritanopia':
      return Colors.purple.shade700;
    default:
      return Colors.blue;
  }
}

Color obtenerColorWarning(String modoDaltonismo) {
  switch (modoDaltonismo) {
    case 'protanopia':
      return Colors.brown.shade600;
    case 'deuteranopia':
      return Colors.brown.shade800;
    case 'tritanopia':
      return Colors.pink.shade300;
    default:
      return Colors.orange;
  }
}
