import 'package:google_maps_flutter/google_maps_flutter.dart';

class ReporteLlegada {
  ReporteLlegada({
    required this.paradaId,
    required this.fechaHora,
    required this.distanciaLlegadaMetros,
    required this.ubicacionLlegada,
    this.tipoNotificacion,
    this.personaNotificada,
    this.descripcionDiligencia,
    this.reporteFirestoreId,
  });

  final int paradaId;
  final DateTime fechaHora;
  final double distanciaLlegadaMetros;
  final LatLng ubicacionLlegada;
  final String? tipoNotificacion;
  final String? personaNotificada;
  final String? descripcionDiligencia;
  final String? reporteFirestoreId;
}

