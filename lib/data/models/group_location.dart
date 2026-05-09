import 'package:cloud_firestore/cloud_firestore.dart';

class GroupLocation {
  const GroupLocation({
    required this.id,
    required this.lat,
    required this.lng,
    required this.groupId,
    required this.timestamp,
    this.ubicacionId,
    this.nombreUbicacion,
    this.referenciaUbicacion,
    this.identificacionTecnica,
    this.esSegundaNotificacion = false,
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.nombreNotificador,
    this.cedulaNotificador,
    this.estado,
  });

  final String id;
  final double lat;
  final double lng;
  final String groupId;
  final DateTime timestamp;
  final int? ubicacionId;
  final String? nombreUbicacion;
  final String? referenciaUbicacion;
  final String? identificacionTecnica;
  final bool esSegundaNotificacion;
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? nombreNotificador;
  final String? cedulaNotificador;
  final String? estado;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'groupId': groupId,
      'timestamp': Timestamp.fromDate(timestamp.toUtc()),
      'ubicacionId': ubicacionId,
      'nombreUbicacion': nombreUbicacion,
      'referenciaUbicacion': referenciaUbicacion,
      'identificacionTecnica': identificacionTecnica,
      'esSegundaNotificacion': esSegundaNotificacion,
      'razonSocial': razonSocial,
      'ruc': ruc,
      'representanteLegal': representanteLegal,
      'nombreNotificador': nombreNotificador,
      'cedulaNotificador': cedulaNotificador,
      'estado': estado,
    };
  }

  factory GroupLocation.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> map = doc.data() ?? <String, dynamic>{};
    final Object? latRaw = map['lat'];
    final Object? lngRaw = map['lng'];

    if (latRaw is! num || lngRaw is! num) {
      throw const FormatException(
        'Documento de ubicacion sin lat/lng validos.',
      );
    }

    final String groupId = (map['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      throw const FormatException('Documento de ubicacion sin groupId.');
    }

    final DateTime timestamp = _parseTimestamp(map['timestamp']);

    return GroupLocation(
      id: doc.id,
      lat: latRaw.toDouble(),
      lng: lngRaw.toDouble(),
      groupId: groupId,
      timestamp: timestamp,
      ubicacionId: (map['ubicacionId'] as num?)?.toInt(),
      nombreUbicacion: (map['nombreUbicacion'] as String?)?.trim(),
      referenciaUbicacion: (map['referenciaUbicacion'] as String?)?.trim(),
      identificacionTecnica: (map['identificacionTecnica'] as String?)?.trim(),
      esSegundaNotificacion: _parseBool(map['esSegundaNotificacion'] ?? map['es_segunda_notificacion']),
      razonSocial: (map['razonSocial'] as String?)?.trim(),
      ruc: (map['ruc'] as String?)?.trim(),
      representanteLegal: (map['representanteLegal'] as String?)?.trim(),
      nombreNotificador: (map['nombreNotificador'] as String?)?.trim(),
      cedulaNotificador: (map['cedulaNotificador'] as String?)?.trim(),
      estado: (map['estado'] as String?)?.trim(),
    );
  }

  static DateTime _parseTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'si';
    }
    return false;
  }
}
