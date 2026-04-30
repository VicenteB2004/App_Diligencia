import 'package:google_maps_flutter/google_maps_flutter.dart';

class ResultadoBusquedaDestino {
  const ResultadoBusquedaDestino.ok({
    required this.posicion,
    required this.fueCoordenada,
    this.mensajeInfo,
    this.trazadoReferencia = const <LatLng>[],
  })  : exito = true,
        mensajeError = null;

  const ResultadoBusquedaDestino.error(this.mensajeError)
      : exito = false,
        posicion = null,
        fueCoordenada = false,
        mensajeInfo = null,
        trazadoReferencia = const <LatLng>[];

  final bool exito;
  final LatLng? posicion;
  final bool fueCoordenada;
  final String? mensajeError;
  final String? mensajeInfo;
  final List<LatLng> trazadoReferencia;
}

