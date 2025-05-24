import 'package:comunidad_en_movimiento/utils/constants.dart'; 

class Ruta {
  final double lat;
  final double lng;
  final int catAcc;
  final int month;
  final int weekday;
  final String zona;
  final double distMinPoi;
  final double densidadZona;

  final double latNorm;
  final double lngNorm;

  Ruta({
    required this.lat,
    required this.lng,
    required this.catAcc,
    required this.month,
    required this.weekday,
    required this.zona,
    required this.distMinPoi,
    required this.densidadZona,
  })  : latNorm = (lat - latMin) / (latMax - latMin),
        lngNorm = (lng - lngMin) / (lngMax - lngMin);
}
