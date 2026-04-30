enum UserRole { abogado, notificador }

extension UserRoleX on UserRole {
  String get value {
    switch (this) {
      case UserRole.abogado:
        return 'abogado';
      case UserRole.notificador:
        return 'notificador';
    }
  }

  static UserRole? fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'abogado':
        return UserRole.abogado;
      case 'notificador':
        return UserRole.notificador;
      default:
        return null;
    }
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.rol,
    required this.groupId,
  });

  final String uid;
  final String email;
  final UserRole rol;
  final String groupId;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'email': email,
      'rol': rol.value,
      'groupId': groupId,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final String roleRaw = (map['rol'] as String? ?? '').trim().toLowerCase();
    final UserRole? parsedRole = UserRoleX.fromString(roleRaw);
    if (parsedRole == null) {
      throw const FormatException('Rol invalido en documento de usuario.');
    }

    final String uid = (map['uid'] as String? ?? '').trim();
    final String email = (map['email'] as String? ?? '').trim();
    final String groupId =
        (map['groupId'] as String? ?? map['grupo_id'] as String? ?? '').trim();

    if (uid.isEmpty || email.isEmpty) {
      throw const FormatException('Faltan campos obligatorios del usuario.');
    }

    return AppUser(uid: uid, email: email, rol: parsedRole, groupId: groupId);
  }
}
