class Visita {
  const Visita({
    this.id,
    required this.ubicacionId,
    required this.notificadorId,
    required this.latitud,
    required this.longitud,
    required this.fecha,
    required this.hora,
    required this.estado,
    this.observacion,
  });

  final int? id;
  final int ubicacionId;
  final int notificadorId;
  final double latitud;
  final double longitud;
  final String fecha;
  final String hora;
  final String estado;
  final String? observacion;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ubicacion_id': ubicacionId,
      'notificador_id': notificadorId,
      'latitud': latitud,
      'longitud': longitud,
      'fecha': fecha,
      'hora': hora,
      'estado': estado,
      'observacion': observacion,
    };
  }

  factory Visita.fromMap(Map<String, Object?> map) {
    return Visita(
      id: map['id'] as int?,
      ubicacionId: map['ubicacion_id'] as int,
      notificadorId: map['notificador_id'] as int,
      latitud: (map['latitud'] as num).toDouble(),
      longitud: (map['longitud'] as num).toDouble(),
      fecha: map['fecha'] as String? ?? '',
      hora: map['hora'] as String? ?? '',
      estado: map['estado'] as String? ?? 'completada',
      observacion: map['observacion'] as String?,
    );
  }
}

