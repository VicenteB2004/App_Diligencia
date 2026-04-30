import 'package:notificador/features/operacion/domain/entities/rol_app.dart';

class Usuario {
  const Usuario({
    this.id,
    required this.nombre,
    required this.email,
    required this.password,
    required this.rol,
    required this.fechaCreacion,
    this.groupId = '',
  });

  final int? id;
  final String nombre;
  final String email;
  final String password;
  final RolApp rol;
  final DateTime fechaCreacion;
  final String groupId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'nombre': nombre,
      'email': email,
      'password': password,
      'rol': rol == RolApp.abogado ? 'abogado' : 'notificador',
      'group_id': groupId,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  factory Usuario.fromMap(Map<String, Object?> map) {
    return Usuario(
      id: map['id'] as int?,
      nombre: map['nombre'] as String? ?? '',
      email: map['email'] as String? ?? '',
      password: map['password'] as String? ?? '',
      rol: (map['rol'] as String? ?? 'notificador').toLowerCase() == 'abogado'
          ? RolApp.abogado
          : RolApp.notificador,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      groupId: (map['group_id'] as String? ?? map['groupId'] as String? ?? '').trim(),
    );
  }
}

