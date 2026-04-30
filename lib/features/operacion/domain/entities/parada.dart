import 'package:google_maps_flutter/google_maps_flutter.dart';

class Parada {
  Parada({
    required this.id,
    required this.posicion,
    this.nombreUbicacion,
    this.identificacionTecnica,
    this.esSegundaNotificacion = false,
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.nombreNotificador,
    this.cedulaNotificador,
    this.completada = false,
  });

  final int id;
  final LatLng posicion;
  final String? nombreUbicacion;
  final String? identificacionTecnica;
  final bool esSegundaNotificacion;
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? nombreNotificador;
  final String? cedulaNotificador;
  bool completada;
}

