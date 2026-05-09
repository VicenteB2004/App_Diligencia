class Ubicacion {
  const Ubicacion({
    this.id,
    this.abogadoId,
    required this.latitud,
    required this.longitud,
    this.direccion,
    this.descripcion,
    this.nombreUbicacion,
    this.referenciaUbicacion,
    this.identificacionTecnica,
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.nombreNotificador,
    this.cedulaNotificador,
    this.esSegundaNotificacion = false,
    required this.fechaCreacion,
    this.estado = 'pendiente',
  });

  final int? id;
  final int? abogadoId;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String? descripcion;
  final String? nombreUbicacion;
  final String? referenciaUbicacion;
  final String? identificacionTecnica;
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? nombreNotificador;
  final String? cedulaNotificador;
  final bool esSegundaNotificacion;
  final DateTime fechaCreacion;
  final String estado;

  Ubicacion copyWith({
    int? id,
    int? abogadoId,
    double? latitud,
    double? longitud,
    String? direccion,
    String? descripcion,
    String? nombreUbicacion,
    String? referenciaUbicacion,
    String? identificacionTecnica,
    String? razonSocial,
    String? ruc,
    String? representanteLegal,
    String? nombreNotificador,
    String? cedulaNotificador,
    bool? esSegundaNotificacion,
    DateTime? fechaCreacion,
    String? estado,
  }) {
    return Ubicacion(
      id: id ?? this.id,
      abogadoId: abogadoId ?? this.abogadoId,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      direccion: direccion ?? this.direccion,
      descripcion: descripcion ?? this.descripcion,
      nombreUbicacion: nombreUbicacion ?? this.nombreUbicacion,
      referenciaUbicacion: referenciaUbicacion ?? this.referenciaUbicacion,
      identificacionTecnica: identificacionTecnica ?? this.identificacionTecnica,
      razonSocial: razonSocial ?? this.razonSocial,
      ruc: ruc ?? this.ruc,
      representanteLegal: representanteLegal ?? this.representanteLegal,
      nombreNotificador: nombreNotificador ?? this.nombreNotificador,
      cedulaNotificador: cedulaNotificador ?? this.cedulaNotificador,
      esSegundaNotificacion: esSegundaNotificacion ?? this.esSegundaNotificacion,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      estado: estado ?? this.estado,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'abogado_id': abogadoId,
      'latitud': latitud,
      'longitud': longitud,
      'direccion': direccion,
      'descripcion': descripcion,
      'nombre_ubicacion': nombreUbicacion,
      'referencia_ubicacion': referenciaUbicacion,
      'identificacion_tecnica': identificacionTecnica,
      'razon_social': razonSocial,
      'ruc': ruc,
      'representante_legal': representanteLegal,
      'nombre_notificador': nombreNotificador,
      'cedula_notificador': cedulaNotificador,
      'es_segunda_notificacion': esSegundaNotificacion ? 1 : 0,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'estado': estado,
    };
  }

  factory Ubicacion.fromMap(Map<String, Object?> map) {
    return Ubicacion(
      id: map['id'] as int?,
      abogadoId: map['abogado_id'] as int?,
      latitud: (map['latitud'] as num).toDouble(),
      longitud: (map['longitud'] as num).toDouble(),
      direccion: map['direccion'] as String?,
      descripcion: map['descripcion'] as String?,
      nombreUbicacion: map['nombre_ubicacion'] as String?,
      referenciaUbicacion: map['referencia_ubicacion'] as String?,
      identificacionTecnica: map['identificacion_tecnica'] as String?,
      razonSocial: map['razon_social'] as String?,
      ruc: map['ruc'] as String?,
      representanteLegal: map['representante_legal'] as String?,
      nombreNotificador: map['nombre_notificador'] as String?,
      cedulaNotificador: map['cedula_notificador'] as String?,
      esSegundaNotificacion: _parseBool(map['es_segunda_notificacion']),
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      estado: map['estado'] as String? ?? 'pendiente',
    );
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

