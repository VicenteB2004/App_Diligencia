import 'package:cloud_firestore/cloud_firestore.dart';

class GrupoNotificador {
  const GrupoNotificador({
	required this.uid,
	required this.email,
	required this.nombre,
	required this.groupId,
	this.joinCode,
  });

  final String uid;
  final String email;
  final String nombre;
  final String groupId;
  final String? joinCode;

  factory GrupoNotificador.fromDocument(
	DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
	final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
	final String rol = (data['rol'] as String? ?? '').trim().toLowerCase();
	if (rol != 'notificador') {
	  throw const FormatException('El documento no pertenece a un notificador.');
	}

	final String uid = (data['uid'] as String? ?? doc.id).trim();
	final String email = (data['email'] as String? ?? '').trim();
	final String nombre = (data['nombre'] as String? ?? '').trim();
	final String groupId =
		(data['groupId'] as String? ?? data['grupo_id'] as String? ?? data['group_id'] as String? ?? '')
			.trim();

	if (uid.isEmpty || email.isEmpty || groupId.isEmpty) {
	  throw const FormatException('Faltan datos obligatorios del notificador.');
	}

	final String rawJoinCode = (data['joinCode'] as String? ?? '').trim();

	return GrupoNotificador(
	  uid: uid,
	  email: email,
	  nombre: nombre.isEmpty ? email.split('@').first : nombre,
	  groupId: groupId,
	  joinCode: rawJoinCode.isEmpty ? null : rawJoinCode,
	);
  }
}

