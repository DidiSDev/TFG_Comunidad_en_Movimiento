import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:comunidad_en_movimiento/home/incidencias_helper.dart';
import 'package:comunidad_en_movimiento/home/traducciones.dart';
import 'package:comunidad_en_movimiento/home/colores_personalizados.dart';

//Datos básicos de una incidencia
class IncidenciaData {
  final double lat;
  final double lng;
  final String tipo;
  IncidenciaData({required this.lat, required this.lng, required this.tipo});

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'tipo': tipo,
      };
}

//Argumentos para StreetView
class StreetViewArguments {
  final double latitude;
  final double longitude;
  final List<IncidenciaData> incidencias;
  final String modoDaltonismo;
  final String idiomaSeleccionado;
  final List<String> opcionesIncidencia;

  StreetViewArguments({
    required this.latitude,
    required this.longitude,
    required this.incidencias,
    required this.modoDaltonismo,
    required this.idiomaSeleccionado,
    required this.opcionesIncidencia,
  });
}

class StreetViewGoogle extends StatefulWidget {
  final StreetViewArguments args;
  const StreetViewGoogle({Key? key, required this.args}) : super(key: key);

  @override
  State<StreetViewGoogle> createState() => _StreetViewGoogleState();
}

class _StreetViewGoogleState extends State<StreetViewGoogle> {
  static const String _googleApiKey =
      "AIzaSyBHAMnu8fwPkxAeGvkfzDo00EMfa3eGw78";
  static const String _channelName = 'StreetViewChannel';

  late final WebViewController _webViewController;

  /// Controla si mostramos el overlay rojo para "colocar incidencia"
  bool _colocandoIncidencia = false;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _channelName,
        onMessageReceived: (JavaScriptMessage message) {
          _onJsMessage(message);
        },
      );

    _loadStreetView();
  }

  Future<void> _loadStreetView() async {
    final htmlStr = _buildStreetViewHtml(
      widget.args.latitude,
      widget.args.longitude,
    );
    final dataUri = Uri.dataFromString(
      htmlStr,
      mimeType: 'text/html',
      encoding: Encoding.getByName('utf-8'),
    );
    await _webViewController.loadRequest(dataUri);
    _setIncidences(widget.args.incidencias);
  }

  /// HTML que muestra StreetView
  String _buildStreetViewHtml(double lat, double lng) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0, user-scalable=no">
  <title>StreetView Demo</title>
  <style>
    html, body { height: 100%; margin: 0; padding: 0; }
    #streetview { width: 100%; height: 100%; }
  </style>
  <script src="https://maps.googleapis.com/maps/api/js?key=$_googleApiKey"></script>
  <script>
    let panorama;
    let markers = [];

    function initStreetView() {
      panorama = new google.maps.StreetViewPanorama(
        document.getElementById("streetview"),
        {
          position: { lat: $lat, lng: $lng },
          pov: { heading: 0, pitch: 0 },
          zoom: 1,
          addressControl: true,
          linksControl: true,
          panControl: true,
          enableCloseButton: false,
          clickToGo: true
        }
      );
    }

    function setIncidencesJson(jsonStr) {
      try {
        const incs = JSON.parse(jsonStr);
        renderIncidences(incs);
      } catch (e) {
        console.error("Error parsing incidences:", e);
      }
    }

    function renderIncidences(incList) {
      markers.forEach(marker => marker.setMap(null));
      markers = [];
      incList.forEach(inc => {
        const marker = new google.maps.Marker({
          position: { lat: inc.lat, lng: inc.lng },
          title: inc.tipo,
          map: panorama
        });
        markers.push(marker);
      });
    }

    window.onload = initStreetView;
  </script>
</head>
<body>
  <div id="streetview"></div>
</body>
</html>
''';
  }

  Future<void> _setIncidences(List<IncidenciaData> incs) async {
    final listMap = incs.map((i) => i.toJson()).toList();
    final jsonStr = jsonEncode(listMap);
    final script = "setIncidencesJson('$jsonStr');";
    await _webViewController.runJavaScript(script);
  }

  void _onJsMessage(JavaScriptMessage message) async {
    // En este ejemplo, no hacemos nada con _colocandoIncidencia en JS
    if (!_colocandoIncidencia) return;
    try {
      final data = json.decode(message.message);
      final lat = data['lat'];
      final lng = data['lng'];
      print("StreetView => GOT lat=$lat, lng=$lng");

      // Muestras el formulario con esa lat/lng
      await mostrarDialogoIncidencia(
        context,
        LatLng(lat, lng),
        (_) => setState(() {}),
        widget.args.opcionesIncidencia,
        widget.args.modoDaltonismo,
        widget.args.idiomaSeleccionado,
      );
    } catch (e) {
      print("Error al parsear streetview: $e");
    }
  }

  ///Overlay rojo para depurar y comporobar q la camara queda quieta
  Widget _buildOverlay() {
    return Positioned.fill(
      child: Listener(
        onPointerDown: (PointerDownEvent event) async {
          print("PointerDown overlay! Pos=\${event.position}");

          // 1) Cierra StreetView
          Navigator.of(context).pop(); 

          // 2) Abre el formulario con la lat/lng del StreetView original
          //Como no podemos interactuar en la vista streetview porq la api de google no lo permite, volvemos atrás pero ya con el formularioi
          await mostrarDialogoIncidencia(
            context,
            LatLng(widget.args.latitude, widget.args.longitude),
            (_) => setState(() {}),
            widget.args.opcionesIncidencia,
            widget.args.modoDaltonismo,
            widget.args.idiomaSeleccionado,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.red.withOpacity(0.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idioma = widget.args.idiomaSeleccionado;
    final modo = widget.args.modoDaltonismo;

    return Scaffold(
      appBar: AppBar(
        title: Text("StreetView", style: TextStyle(color: obtenerColorTextoBoton())),
        backgroundColor: obtenerColorBoton(modo),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add_location_alt_outlined,
              color: _colocandoIncidencia ? Colors.yellow : obtenerColorTextoBoton(),
            ),
            tooltip: traducir("Colocar incidencia", idioma),
            onPressed: () {
              setState(() {
                _colocandoIncidencia = !_colocandoIncidencia;
              });
              if (_colocandoIncidencia) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(traducir("Pulsa la capa roja para cerrar StreetView y abrir el formulario", idioma)),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          //Si activo _colocandoIncidencia, aparece la capa roja que cierra StreetView y abre el formulario, pintamos el icono también.
          if (_colocandoIncidencia)
            _buildOverlay(),
        ],
      ),
    );
  }
}
