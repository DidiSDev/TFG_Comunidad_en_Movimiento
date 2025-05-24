import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:comunidad_en_movimiento/models/ruta.dart';
import 'package:comunidad_en_movimiento/ia/asistente_virtual.dart';
import 'package:comunidad_en_movimiento/ia/modelo_ia.dart';
import 'package:intl/intl.dart';
import 'colores_personalizados.dart';
import 'traducciones.dart';
import 'package:comunidad_en_movimiento/utils/constants.dart';


String asignarZona(double lat, double lng) {
  int zonaX = ((lng - lngMin) / tamanoCuadricula).floor();
  int zonaY = ((lat - latMin) / tamanoCuadricula).floor();

  // Posibles límites de zonas
  if (zonaX < 0) zonaX = 0;
  if (zonaX > 49) zonaX = 49;
  if (zonaY < 0) zonaY = 0;
  if (zonaY > 49) zonaY = 49;

  return 'zona_${zonaX}_$zonaY';
}

Future<void> mostrarDialogoIncidencia(
    BuildContext context,
    LatLng latlng,
    Function setStateCallback,
    List<String> opcionesIncidencia,
    String modoDaltonismo,
    String idiomaSeleccionado) async {
  String tipoSeleccionado = opcionesIncidencia.first;
  String descripcion = '';
  int categoriaAccesibilidadSeleccionada = 1;
  String tipoSuperficieSeleccionada = 'acera';

  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: obtenerColorFondo(modoDaltonismo),
        title: Text(
          traducir('Añadir incidencia', idiomaSeleccionado),
          style: TextStyle(color: obtenerColorTexto()),
        ),
        content: SingleChildScrollView(
          child: Column(
            children: [
              // 
              // !!!!!****!!!!!!IMPORTANTE!!!!****!!!!!
              //
              //--- Selección de TIPO de incidencia ---
              DropdownButtonFormField<String>(
                value: tipoSeleccionado,
                decoration: InputDecoration(
                  labelText: traducir('Tipo de incidencia', idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                ),
                dropdownColor: obtenerColorFondo(modoDaltonismo),
                items: opcionesIncidencia.map((String tipo) {
                  return DropdownMenuItem<String>(
                    value: tipo,
                    child: Text(
                      traducir(tipo, idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    tipoSeleccionado = value;
                  }
                },
              ),
              const SizedBox(height: 10),

              // --- Categoría de accesibilidad ---
              DropdownButtonFormField<int>(
                value: categoriaAccesibilidadSeleccionada,
                decoration: InputDecoration(
                  labelText: traducir(
                      'Categoría de Accesibilidad', idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                ),
                dropdownColor: obtenerColorFondo(modoDaltonismo),
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(
                      traducir('Sin problema', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(
                      traducir('Leve', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(
                      traducir('Moderado', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text(
                      traducir('Grave', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    categoriaAccesibilidadSeleccionada = value;
                  }
                },
              ),
              const SizedBox(height: 10),

              // --- Tipo de Superficie ---
              DropdownButtonFormField<String>(
                value: tipoSuperficieSeleccionada,
                decoration: InputDecoration(
                  labelText:
                      traducir('Tipo de Superficie', idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                ),
                dropdownColor: obtenerColorFondo(modoDaltonismo),
                items: [
                  DropdownMenuItem(
                    value: 'acera',
                    child: Text(
                      traducir('Acera', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'calzada',
                    child: Text(
                      traducir('Calzada', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'otro',
                    child: Text(
                      traducir('Otro', idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto()),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    tipoSuperficieSeleccionada = value;
                  }
                },
              ),
              const SizedBox(height: 10),

              // --- Información Adicional ---
              TextField(
                style: TextStyle(color: obtenerColorTexto()),
                decoration: InputDecoration(
                  labelText: traducir(
                      'Información Adicional (opcional)', idiomaSeleccionado),
                  labelStyle: TextStyle(color: obtenerColorTexto()),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: obtenerColorBorde()),
                  ),
                  filled: true,
                  fillColor: obtenerColorCampo(),
                ),
                onChanged: (value) {
                  descripcion = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          // --- Botón de CANCELAR ---
          TextButton(
            child: Text(
              traducir('Cancelar', idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto()),
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),

          // --- Botón ACEPTAR ---
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: obtenerColorBoton(modoDaltonismo),
            ),
            onPressed: () async {
              String fechaInforme =
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
              int peligro = 0;
              if (categoriaAccesibilidadSeleccionada == 3) {
                peligro = 1;
              }

              // CALCULO DE ZONA
              final String zonaCalculada =
                  asignarZona(latlng.latitude, latlng.longitude);

              // Guardar en la coleccion de FB -> 'incidencias'
              DocumentReference nuevaIncidenciaRef = await FirebaseFirestore
                  .instance
                  .collection('incidencias')
                  .add({
                'latitude': latlng.latitude,
                'longitude': latlng.longitude,
                'tipo': tipoSeleccionado,
                'descripcion': descripcion,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'categoria_accesibilidad': categoriaAccesibilidadSeleccionada,
                'informacion_adicional': descripcion.isNotEmpty
                    ? descripcion
                    : traducir('Sin información adicional', idiomaSeleccionado),
                'tipo_superficie': tipoSuperficieSeleccionada,
                'fecha_informe': fechaInforme,
                'peligro': peligro,
                'zona': zonaCalculada, // <--- AÑADIDA LA INTERACCIÓN CON ZONA_
              });

              // Guardar también en 'total_incidencias'
              await FirebaseFirestore.instance
                  .collection('total_incidencias')
                  .add({
                'latitude': latlng.latitude,
                'longitude': latlng.longitude,
                'tipo': tipoSeleccionado,
                'descripcion': descripcion,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'categoria_accesibilidad': categoriaAccesibilidadSeleccionada,
                'informacion_adicional': descripcion.isNotEmpty
                    ? descripcion
                    : traducir('Sin información adicional', idiomaSeleccionado),
                'tipo_superficie': tipoSuperficieSeleccionada,
                'fecha_informe': fechaInforme,
                'peligro': peligro,
                'estado': 'activa',
                'id_incidencia_original': nuevaIncidenciaRef.id,
                'zona': zonaCalculada, // LO MISMO
              });

              Navigator.of(context).pop();
            },
            child: Text(
              traducir('Aceptar', idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTextoBoton()),
            ),
          ),
        ],
      );
    },
  );
}
Future<bool> mostrarDialogoEliminarIncidencia(
    BuildContext context,
    String tipo,
    String descripcion,
    Function setStateCallback,
    String modoDaltonismo,
    String idiomaSeleccionado) async {
  bool? resultado = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: obtenerColorFondo(modoDaltonismo),
        title: Text(
          '${traducir('Incidencia:', idiomaSeleccionado)} ${traducir(tipo, idiomaSeleccionado)}',
          style: TextStyle(color: obtenerColorTexto()),
        ),
        content: Text(
          descripcion.isNotEmpty
              ? '${traducir('Descripción:', idiomaSeleccionado)} $descripcion\n\n${traducir('¿Eliminar esta incidencia?', idiomaSeleccionado)}'
              : traducir('¿Eliminar esta incidencia?', idiomaSeleccionado),
          style: TextStyle(color: obtenerColorTexto()),
        ),
        actions: [
          TextButton(
            child: Text(
              traducir('Cancelar', idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTexto()),
            ),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: obtenerColorBoton(modoDaltonismo),
            ),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(
              traducir('Eliminar', idiomaSeleccionado),
              style: TextStyle(color: obtenerColorTextoBoton()),
            ),
          ),
        ],
      );
    },
  );

  // -------------------------------------------
  // **EVALUACIÓN DEL BOTÓN ELIMINAR**
  // -------------------------------------------
  return resultado ?? false;
}


Future<void> actualizarPeligroIncidenciasExistentes(
    AsistenteVirtualIA asistenteVirtual,
    ModeloIA modeloIA,
    BuildContext context,
    String modoDaltonismo,
    String idiomaSeleccionado) async {
  QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance
      .collection('incidencias')
      .where('peligro', isEqualTo: 0)
      .get();

  for (var doc in snapshot.docs) {
    Map<String, dynamic> data = doc.data();
    double lat = data['latitude'];
    double lng = data['longitude'];
    int catAcc = data['categoria_accesibilidad'] ?? 1;

    int month = DateTime.now().month;
    int weekday = DateTime.now().weekday - 1;
    if (weekday < 0) weekday = 6;

    String zona = asistenteVirtual.asignarZona(lat, lng);

    double distMinPoi = asistenteVirtual.calcularDistanciaMinima(lat, lng);

    double densidadZona =
        await asistenteVirtual.calcularDensidadIncidentes(zona);
    Ruta ruta = Ruta(
      lat: lat,
      lng: lng,
      catAcc: catAcc,
      month: month,
      weekday: weekday,
      zona: zona,
      distMinPoi: distMinPoi,
      densidadZona: densidadZona,
    );

    double prediccion = await modeloIA.predecirProbabilidad(ruta);

    await FirebaseFirestore.instance
        .collection('incidencias')
        .doc(doc.id)
        .update({
      'peligro': prediccion > 0.5 ? 1 : 0,
    });

    print(
        'Incidencia ${doc.id} actualizada con peligro: ${prediccion > 0.5 ? 1 : 0}');
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.green,
      content: Text(
          traducir('Incidencias existentes actualizadas correctamente.',
              idiomaSeleccionado)),
    ),
  );
}

// Esta función se encarga de mostrar el listado de incidencias cercanas al usuario.
// Recibe bastantes parámetros (quizás demasiados, podríamos encapsular algunos en una clase)
Future<void> mostrarListadoIncidencias(
    LatLng? ubicacionOrigen,
    String? filtroIncidencia,
    AsistenteVirtualIA asistenteVirtual,
    ModeloIA modeloIA,
    BuildContext context,
    String modoDaltonismo,
    String idiomaSeleccionado,
    Function setStateCallback) async {
  // Primero sacamos todas las incidencias de Firebase
  QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
      .collection('incidencias')
      .get();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.docs.toList();

  // Si hay filtro de tipo de incidencia, lo aplicamos
  if (filtroIncidencia != null) {
    docs = docs.where((doc) => doc['tipo'] == filtroIncidencia).toList();
  }

  // Ahora recorremos las incidencias y calculamos el nivel de peligro para las que no lo tienen
  // ¡Ojo! Esto me puede costar recursos en android si hay muchas incidencias sin procesar
  for (var doc in docs) {
    Map<String, dynamic> data = doc.data();
    if (!data.containsKey('peligro')) {
      double lat = data['latitude'];
      double lng = data['longitude'];
      int catAcc = data['categoria_accesibilidad'] ?? 1;

      // Sacamos el mes y día de la semana actuales para el modelo
      // El -1 en weekday es porque parece que el modelo usa 0-6 en vez de 1-7
      int month = DateTime.now().month;
      int weekday = DateTime.now().weekday - 1;
      if (weekday < 0) weekday = 6;

      // Usamos el asistente virtual (EL DE MACHINE LEARNING) para obtener datos de contexto
      String zona = asistenteVirtual.asignarZona(lat, lng);

      double distMinPoi =
          asistenteVirtual.calcularDistanciaMinima(lat, lng);

      // Esta llamada podría optimizarse para no calcular la densidad por cada incidencia de la misma zona
      double densidadZona =
          await asistenteVirtual.calcularDensidadIncidentes(zona);
      Ruta ruta = Ruta(
        lat: lat,
        lng: lng,
        catAcc: catAcc,
        month: month,
        weekday: weekday,
        zona: zona,
        distMinPoi: distMinPoi,
        densidadZona: densidadZona,
      );

      // Hacemos la predicción con el modelo de de ML
      double prediccion = await modeloIA.predecirProbabilidad(ruta);

      // Actualizamos la incidencia con el valor calculado (1 si es peligroso, 0 si no)
      await FirebaseFirestore.instance
          .collection('incidencias')
          .doc(doc.id)
          .update({
        'peligro': prediccion > 0.5 ? 1 : 0,
      });
    }
  }

  // Volvemos a cargar las incidencias para tener los datos actualizados
  // Esto es un poco ineficiente, podríamos haberlo hecho en memoria
  docs = snap.docs.toList();
  if (filtroIncidencia != null) {
    docs = docs.where((doc) => doc['tipo'] == filtroIncidencia).toList();
  }

  // Si tenemos ubicación de origen, ordenamos por distancia (las más cercanas primero)
  if (ubicacionOrigen != null) {
    docs.sort((a, b) {
      double distA = Distance().as(
          LengthUnit.Meter,
          LatLng(a['latitude'], a['longitude']),
          ubicacionOrigen);
      double distB = Distance().as(
          LengthUnit.Meter,
          LatLng(b['latitude'], b['longitude']),
          ubicacionOrigen);
      return distA.compareTo(distB);
    });
  }

  // Mostramos el diálogo con la lista de incidencias
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: obtenerColorFondo(modoDaltonismo),
        title: Text(traducir('Incidencias Cercanas', idiomaSeleccionado),
            style: TextStyle(color: obtenerColorTexto())),
        content: SizedBox(
          width: double.minPositive,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: docs.map((doc) {
                String tipo = doc['tipo'];
                String desc = doc['descripcion'] ?? '';
                // Calculamos la distancia y la formateamos para mostrarla en m o km según corresponda hasta 999 m
                double distMetros = ubicacionOrigen != null
                    ? Distance().as(
                        LengthUnit.Meter,
                        LatLng(doc['latitude'], doc['longitude']),
                        ubicacionOrigen)
                    : 0.0;
                String distTexto = distMetros < 1000
                    ? '${distMetros.toStringAsFixed(0)} m'
                    : '${(distMetros / 1000).toStringAsFixed(2)} km';

                // Creamos el ListTile para cada incidencia
                return ListTile(
                  title: Text(traducir(tipo, idiomaSeleccionado),
                      style: TextStyle(color: obtenerColorTexto())),
                  subtitle: Text(
                    '${traducir('Distancia:', idiomaSeleccionado)} $distTexto\n${traducir('Descripción:', idiomaSeleccionado)} $desc',
                    style: TextStyle(color: obtenerColorTexto()),
                  ),
                  onTap: () async {
                    // Al pulsar mostramos un diálogo para eliminar o leer la incidencia
                    bool eliminar = await mostrarDialogoEliminarIncidencia(
                        context,
                        tipo,
                        desc,
                        setStateCallback,
                        modoDaltonismo,
                        idiomaSeleccionado);
                    if (eliminar) {
                      // Si se elige eliminar, movemos la incidencia a la colección de historial
                      // y después la borramos de las activas - esto es bueno para mantener un histórico
                      var docData = doc.data();
                      await FirebaseFirestore.instance
                          .collection('total_incidencias')
                          .add({
                        'latitude': docData['latitude'],
                        'longitude': docData['longitude'],
                        'tipo': docData['tipo'],
                        'descripcion': docData['descripcion'],
                        'timestamp': docData['timestamp'],
                        'categoria_accesibilidad':
                            docData['categoria_accesibilidad'],
                        'informacion_adicional':
                            docData['informacion_adicional'],
                        'tipo_superficie': docData['tipo_superficie'],
                        'fecha_informe': docData['fecha_informe'],
                        'peligro': docData['peligro'],
                        'estado': 'eliminada',
                        'id_incidencia_original': doc.id
                      });

                      await FirebaseFirestore.instance
                          .collection('incidencias')
                          .doc(doc.id)
                          .delete();
                    } else {
                      // Si no se elimina, leemos la incidencia con TTS para accesibilidad
                      FlutterTts tts = FlutterTts();
                      await tts.speak(
                          '${traducir('Incidencia tipo', idiomaSeleccionado)} ${traducir(tipo, idiomaSeleccionado)}. ${traducir('Descripción:', idiomaSeleccionado)} $desc');
                    }
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(traducir('Cerrar', idiomaSeleccionado),
                style: TextStyle(color: obtenerColorTexto())),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}