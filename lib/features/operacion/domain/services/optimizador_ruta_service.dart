import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:notificador/features/operacion/domain/entities/parada.dart';

class ResultadoRuta {
  const ResultadoRuta({required this.rutaIds, required this.polylines});

  final List<int> rutaIds;
  final Set<Polyline> polylines;
}

class OptimizadorRutaService {
  const OptimizadorRutaService();

  double distanciaMetros(LatLng origen, LatLng destino) {
    return Geolocator.distanceBetween(
      origen.latitude,
      origen.longitude,
      destino.latitude,
      destino.longitude,
    );
  }

  ResultadoRuta recalcularRuta({
    required LatLng miUbicacion,
    required Iterable<Parada> paradas,
  }) {
    final List<Parada> pendientes = paradas.where((Parada p) => !p.completada).toList();

    final List<int> nuevaRutaIds = <int>[];
    final List<LatLng> puntos = <LatLng>[miUbicacion];
    LatLng cursor = miUbicacion;

    while (pendientes.isNotEmpty) {
      pendientes.sort(
        (Parada a, Parada b) => distanciaMetros(cursor, a.posicion)
            .compareTo(distanciaMetros(cursor, b.posicion)),
      );

      final Parada siguiente = pendientes.removeAt(0);
      nuevaRutaIds.add(siguiente.id);
      puntos.add(siguiente.posicion);
      cursor = siguiente.posicion;
    }

    final Set<Polyline> nuevasLineas = <Polyline>{};
    if (puntos.length > 1) {
      nuevasLineas.add(
        Polyline(
          polylineId: const PolylineId('ruta_optima'),
          points: puntos,
          width: 5,
          color: Colors.blue,
        ),
      );
    }

    return ResultadoRuta(rutaIds: nuevaRutaIds, polylines: nuevasLineas);
  }

  LatLngBounds calcularBounds(List<LatLng> puntos) {
    double? minLat;
    double? maxLat;
    double? minLng;
    double? maxLng;

    for (final LatLng p in puntos) {
      minLat = minLat == null ? p.latitude : math.min(minLat, p.latitude);
      maxLat = maxLat == null ? p.latitude : math.max(maxLat, p.latitude);
      minLng = minLng == null ? p.longitude : math.min(minLng, p.longitude);
      maxLng = maxLng == null ? p.longitude : math.max(maxLng, p.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }
}

