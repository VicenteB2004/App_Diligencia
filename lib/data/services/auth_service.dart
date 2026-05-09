import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/grupo_notificador.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _authSource = auth,
      _firestoreSource = firestore;

  static const String usuariosCollection = 'usuarios';
  static const String invitacionesCollection = 'invitaciones_grupo';
  static const Duration invitacionTtl = Duration(hours: 24);

  final FirebaseAuth? _authSource;
  final FirebaseFirestore? _firestoreSource;

  late final FirebaseAuth _auth = _authSource ?? FirebaseAuth.instance;
  late final FirebaseFirestore _firestore = _firestoreSource ?? FirebaseFirestore.instance;

  User? get currentFirebaseUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<AppUser> registerUser({
    required String email,
    required String password,
    required String rol,
    required String groupId,
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();
    final String normalizedGroupId = groupId.trim();
    final UserRole? parsedRole = UserRoleX.fromString(rol);

    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthServiceException(
        'Email y password son obligatorios.',
      );
    }
    if (parsedRole == null) {
      throw const AuthServiceException(
        'Rol invalido. Usa abogado o notificador.',
      );
    }
    final String effectiveGroupId = normalizedGroupId;
    if (parsedRole == UserRole.abogado && effectiveGroupId.isEmpty) {
      throw const AuthServiceException(
        'El abogado debe registrar un groupId valido.',
      );
    }

    try {
      final UserCredential credential = await _auth
          .createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(const Duration(seconds: 20));

      final User? createdUser = credential.user;
      if (createdUser == null) {
        throw const AuthServiceException(
          'No se pudo crear el usuario en Firebase Auth.',
        );
      }

      final AppUser appUser = AppUser(
        uid: createdUser.uid,
        email: normalizedEmail,
        rol: parsedRole,
        groupId: effectiveGroupId,
      );
      final Map<String, dynamic> profileData = <String, dynamic>{
        ...appUser.toMap(),
        'grupo_id': effectiveGroupId,
        'nombre': normalizedEmail.split('@').first,
      };

      try {
        await _firestore
            .collection(usuariosCollection)
            .doc(createdUser.uid)
            .set(profileData, SetOptions(merge: true))
            .timeout(const Duration(seconds: 20));
      } on FirebaseException catch (e) {
        // Keep Auth and Firestore data in sync when profile creation fails.
        await createdUser.delete();
        throw AuthServiceException(
          e.message ?? 'Error al guardar usuario en Firestore.',
          code: e.code,
        );
      } on TimeoutException {
        throw const AuthServiceException(
          'Se agoto el tiempo al guardar usuario en Firestore. Revisa tu conexion o reglas.',
          code: 'timeout',
        );
      }

      return appUser;
    } on FirebaseAuthException catch (e) {
      throw AuthServiceException(_firebaseAuthMessage(e), code: e.code);
    } on FirebaseException catch (e) {
      throw AuthServiceException(_firebaseGenericAuthMessage(e), code: e.code);
    } on TimeoutException {
      throw const AuthServiceException(
        'Se agoto el tiempo al crear la cuenta en Firebase Auth.',
        code: 'timeout',
      );
    }
  }

  Future<UserCredential> loginUser({
    required String email,
    required String password,
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthServiceException('Email y password son obligatorios.');
    }

    try {
      return await _auth
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(const Duration(seconds: 20));
    } on FirebaseAuthException catch (e) {
      throw AuthServiceException(_firebaseAuthMessage(e), code: e.code);
    } on FirebaseException catch (e) {
      throw AuthServiceException(_firebaseGenericAuthMessage(e), code: e.code);
    } on TimeoutException {
      throw const AuthServiceException(
        'Se agoto el tiempo al iniciar sesion en Firebase Auth.',
        code: 'timeout',
      );
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<AppUser?> getCurrentAppUser() async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        return null;
      }
      return getAppUserByUid(currentUser.uid, fallbackEmail: currentUser.email);
    } on TypeError {
      throw AuthServiceException(
        'Error interno leyendo la sesion de Firebase Auth. Intenta reiniciar la app.',
        code: 'auth-state-error',
      );
    }
  }

  Future<AppUser?> getAppUserByUid(String uid, {String? fallbackEmail}) async {
    final String normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return null;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _getUserSnapshotWithRetry(normalizedUid);
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }

      final Map<String, dynamic> userData = Map<String, dynamic>.from(
        snapshot.data()!,
      );
      userData['uid'] = (userData['uid'] as String?)?.trim().isNotEmpty == true
          ? userData['uid']
          : normalizedUid;
      userData['email'] =
          (userData['email'] as String?)?.trim().isNotEmpty == true
          ? userData['email']
          : (fallbackEmail ?? '');

      final String groupId =
          (userData['groupId'] as String? ??
                  userData['grupo_id'] as String? ??
                  userData['group_id'] as String? ??
                  '')
              .trim();
      final String grupoId =
          (userData['grupo_id'] as String? ??
                  userData['groupId'] as String? ??
                  userData['group_id'] as String? ??
                  '')
              .trim();
      final String groupSnakeId =
          (userData['group_id'] as String? ??
                  userData['groupId'] as String? ??
                  userData['grupo_id'] as String? ??
                  '')
              .trim();
      if (groupId.isNotEmpty || grupoId.isNotEmpty || groupSnakeId.isNotEmpty) {
        final String synced = groupId.isNotEmpty
            ? groupId
            : (grupoId.isNotEmpty ? grupoId : groupSnakeId);
        userData['groupId'] = synced;
        userData['grupo_id'] = synced;
        userData['group_id'] = synced;
      }

      final String? originalRole = userData['rol'] as String?;
      final String roleRaw = (originalRole ?? '').trim().toLowerCase();
      if (roleRaw == 'abogado' || roleRaw == 'notificador') {
        userData['rol'] = roleRaw;
      }

      return AppUser.fromMap(userData);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AuthServiceException(
          'Permiso denegado al leer tu perfil de Firestore. Verifica reglas publicadas y que este usuario tenga documento en usuarios/{uid}.',
          code: 'permission-denied',
        );
      }
      throw AuthServiceException(
        e.message ?? 'Error al leer el perfil del usuario.',
        code: e.code,
      );
    } on FormatException catch (e) {
      throw AuthServiceException(e.message, code: 'invalid-user-profile');
    } on TimeoutException {
      throw const AuthServiceException(
        'Se agoto el tiempo al leer el perfil del usuario.',
        code: 'timeout',
      );
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserSnapshotWithRetry(String uid) async {
    const int maxAttempts = 3;
    FirebaseException? lastException;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _firestore
            .collection(usuariosCollection)
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 20));
      } on FirebaseException catch (e) {
        lastException = e;
        final bool canRetry =
            e.code == 'permission-denied' && attempt < maxAttempts && _auth.currentUser != null;
        if (!canRetry) {
          rethrow;
        }

        // Reintentamos sin refrescar token para evitar cierres nativos en Windows.
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw lastException ??
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unknown',
          message: 'No fue posible leer el perfil del usuario.',
        );
  }

  Future<String?> getCurrentUserGroupId() async {
    final AppUser? appUser = await getCurrentAppUser();
    return appUser?.groupId;
  }

  Future<AppUser> ensureLawyerGroup() async {
    final AppUser appUser = await _requireCurrentAppUser();
    if (appUser.rol != UserRole.abogado) {
      throw const AuthServiceException('Solo el rol abogado puede crear o administrar un grupo.');
    }

    if (appUser.groupId.trim().isNotEmpty) {
      return appUser;
    }

    final String uidPrefix = appUser.uid.length >= 6
        ? appUser.uid.substring(0, 6).toLowerCase()
        : appUser.uid.toLowerCase();
    final int suffix = DateTime.now().millisecondsSinceEpoch % 100000;
    final String newGroupId = 'grupo-$uidPrefix-$suffix';

    await _updateUserGroup(uid: appUser.uid, groupId: newGroupId);
    return AppUser(uid: appUser.uid, email: appUser.email, rol: appUser.rol, groupId: newGroupId);
  }

  Future<String> generarInvitacionGrupo() async {
    final AppUser appUser = await _requireCurrentAppUser();
    if (appUser.rol != UserRole.abogado) {
      throw const AuthServiceException('Solo el abogado puede invitar personas al grupo.');
    }

    try {
      final AppUser abogadoConGrupo = await ensureLawyerGroup();
      if (abogadoConGrupo.groupId.trim().isEmpty) {
        throw const AuthServiceException(
          'Tu usuario abogado no tiene groupId. Asigna un grupo antes de invitar.',
        );
      }

      const int maxIntentos = 6;
      for (int intento = 1; intento <= maxIntentos; intento++) {
        final String codigo = _generarCodigoInvitacion();
        final DocumentReference<Map<String, dynamic>> ref = _firestore
            .collection(invitacionesCollection)
            .doc(codigo);

        final DocumentSnapshot<Map<String, dynamic>> existente = await ref.get();
        if (existente.exists) {
          continue;
        }

        final DateTime expiresAt = DateTime.now().toUtc().add(invitacionTtl);
        await ref.set(<String, dynamic>{
          'codigo': codigo,
          'groupId': abogadoConGrupo.groupId,
          'creadoPorUid': abogadoConGrupo.uid,
          'creadoAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'activo': true,
          'usedAt': null,
          'usedByUid': null,
          'estado': 'activa',
        });

        return codigo;
      }

      throw const AuthServiceException(
        'No fue posible generar un codigo unico. Intenta nuevamente.',
        code: 'code-collision',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AuthServiceException(
          'Permiso denegado al generar invitacion. Verifica que el documento usuarios/{uid} del abogado exista, tenga rol "abogado" y groupId/grupo_id con valor.',
          code: 'permission-denied',
        );
      }
      throw AuthServiceException(
        e.message ?? 'No fue posible generar la invitacion temporal.',
        code: e.code,
      );
    }
  }

  Future<AppUser> unirseAGrupoConInvitacion(String codigoInput) async {
    final String codigo = codigoInput.trim().toUpperCase();
    if (codigo.isEmpty) {
      throw const AuthServiceException('Ingresa un codigo de invitacion.');
    }

    final AppUser appUser = await _requireCurrentAppUser();
    if (appUser.rol != UserRole.notificador) {
      throw const AuthServiceException('Solo el notificador puede unirse con codigo de invitacion.');
    }
    if (appUser.groupId.trim().isNotEmpty) {
      throw const AuthServiceException(
        'Tu cuenta ya pertenece a un grupo. Si necesitas cambiarlo, contacta a un abogado administrador.',
      );
    }

    final DocumentReference<Map<String, dynamic>> invitacionRef = _firestore
        .collection(invitacionesCollection)
        .doc(codigo);
    final DocumentReference<Map<String, dynamic>> userRef = _firestore
        .collection(usuariosCollection)
        .doc(appUser.uid);

    final DocumentSnapshot<Map<String, dynamic>> snap = await invitacionRef.get();
    if (!snap.exists || snap.data() == null) {
      throw const AuthServiceException('Codigo de invitacion no valido o inexistente.');
    }

    final Map<String, dynamic> data = snap.data()!;
    final bool activo = data['activo'] as bool? ?? false;
    final String groupId = (data['groupId'] as String? ?? '').trim();
    final Timestamp? expiresTs = data['expiresAt'] as Timestamp?;
    final DateTime? expiresAt = expiresTs?.toDate().toUtc();
    final DateTime now = DateTime.now().toUtc();
    final bool expirado = expiresAt == null || now.isAfter(expiresAt);
    final bool yaUsado = data['usedByUid'] != null || (data['estado'] as String? ?? '') == 'consumida';

    if (!activo || groupId.isEmpty || expirado || yaUsado) {
      throw const AuthServiceException('La invitacion no esta activa o ya expiro.');
    }

    try {
      final Map<String, dynamic> baseUserData = <String, dynamic>{
        'uid': appUser.uid,
        'email': appUser.email,
        'rol': appUser.rol.value,
        'groupId': groupId,
        'grupo_id': groupId,
        'joinCode': codigo,
        'nombre': appUser.email.split('@').first,
      };

      await userRef.set(baseUserData, SetOptions(merge: true));

      await invitacionRef.set(<String, dynamic>{
        'activo': false,
        'usedAt': FieldValue.serverTimestamp(),
        'usedByUid': appUser.uid,
        'estado': 'consumida',
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AuthServiceException(
          'Permiso denegado al unirse al grupo. Verifica que el usuario notificador tenga groupId vacio y que la invitacion este activa.',
          code: 'permission-denied',
        );
      }
      throw AuthServiceException(
        e.message ?? 'No fue posible completar la union al grupo.',
        code: e.code,
      );
    }

    return AppUser(uid: appUser.uid, email: appUser.email, rol: appUser.rol, groupId: groupId);
  }

  Stream<List<GrupoNotificador>> streamNotificadoresByCurrentUserGroup() async* {
    final AppUser appUser = await _requireCurrentAppUser();
    final String groupId = appUser.groupId.trim();
    if (groupId.isEmpty) {
      throw const AuthServiceException('Tu usuario no tiene grupo asignado.');
    }

    // List all invitations for the group (not only those created by this abogado).
    // We will resolve usedByUid across all invitations so the abogado sees all
    // notificadores that joined the same group.
    yield* _firestore
        .collection(invitacionesCollection)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .asyncMap((QuerySnapshot<Map<String, dynamic>> snapshot) async {
          final Map<String, String> uidsPorCodigo = <String, String>{};
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
            final Map<String, dynamic> data = doc.data();
            final String usedByUid = (data['usedByUid'] as String? ?? '').trim();
            final String estado = (data['estado'] as String? ?? '').trim().toLowerCase();
            if (usedByUid.isEmpty || estado == 'activa') {
              continue;
            }
            uidsPorCodigo[doc.id] = usedByUid;
          }

          final List<GrupoNotificador> notificadores = <GrupoNotificador>[];
          final Set<String> uidsProcesados = <String>{};
          for (final MapEntry<String, String> entry in uidsPorCodigo.entries) {
            final String uid = entry.value.trim();
            if (uid.isEmpty || !uidsProcesados.add(uid)) {
              continue;
            }

            try {
              final DocumentSnapshot<Map<String, dynamic>> userSnap = await _getUserSnapshotWithRetry(uid);
              if (!userSnap.exists || userSnap.data() == null) {
                continue;
              }

              final Map<String, dynamic> userData = Map<String, dynamic>.from(userSnap.data()!);
              final String role = (userData['rol'] as String? ?? '').trim().toLowerCase();
              final String notifierGroupId =
                  (userData['groupId'] as String? ?? userData['grupo_id'] as String? ?? userData['group_id'] as String? ?? '')
                      .trim();
              if (role != 'notificador' || notifierGroupId != groupId) {
                continue;
              }

              final String email = (userData['email'] as String? ?? '').trim();
              if (email.isEmpty) {
                continue;
              }
              final String nombre = (userData['nombre'] as String? ?? '').trim();
              final String codigo = entry.key.trim();

              notificadores.add(
                GrupoNotificador(
                  uid: uid,
                  email: email,
                  nombre: nombre.isEmpty ? email.split('@').first : nombre,
                  groupId: groupId,
                  joinCode: codigo.isEmpty ? null : codigo,
                ),
              );
            } catch (_) {
              // Si un perfil no se puede leer, seguimos con el resto.
            }
          }

          notificadores.sort((GrupoNotificador a, GrupoNotificador b) {
            final String nombreA = a.nombre.toLowerCase();
            final String nombreB = b.nombre.toLowerCase();
            final int nombreCompare = nombreA.compareTo(nombreB);
            if (nombreCompare != 0) {
              return nombreCompare;
            }
            return a.email.toLowerCase().compareTo(b.email.toLowerCase());
          });
          return notificadores;
        });
  }

  Future<List<GrupoNotificador>> getNotificadoresByCurrentUserGroup() async {
    final AppUser appUser = await _requireCurrentAppUser();
    final String groupId = appUser.groupId.trim();
    if (groupId.isEmpty) {
      throw const AuthServiceException('Tu usuario no tiene grupo asignado.');
    }

    try {
      // Query all invitations for the group (not restricted to creador)
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection(invitacionesCollection)
          .where('groupId', isEqualTo: groupId)
          .get();

      final List<GrupoNotificador> notificadores = <GrupoNotificador>[];
      final Set<String> uidsProcesados = <String>{};
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        final String usedByUid = (data['usedByUid'] as String? ?? '').trim();
        final String estado = (data['estado'] as String? ?? '').trim().toLowerCase();
        if (usedByUid.isEmpty || estado == 'activa' || !uidsProcesados.add(usedByUid)) {
          continue;
        }

        try {
          final DocumentSnapshot<Map<String, dynamic>> userSnap = await _getUserSnapshotWithRetry(usedByUid);
          if (!userSnap.exists || userSnap.data() == null) {
            continue;
          }

          final Map<String, dynamic> userData = Map<String, dynamic>.from(userSnap.data()!);
          final String role = (userData['rol'] as String? ?? '').trim().toLowerCase();
          final String notifierGroupId =
              (userData['groupId'] as String? ?? userData['grupo_id'] as String? ?? userData['group_id'] as String? ?? '')
                  .trim();
          if (role != 'notificador' || notifierGroupId != groupId) {
            continue;
          }

          final String email = (userData['email'] as String? ?? '').trim();
          if (email.isEmpty) {
            continue;
          }
          final String nombre = (userData['nombre'] as String? ?? '').trim();

          notificadores.add(
            GrupoNotificador(
              uid: usedByUid,
              email: email,
              nombre: nombre.isEmpty ? email.split('@').first : nombre,
              groupId: groupId,
              joinCode: doc.id,
            ),
          );
        } catch (_) {
          // Ignora perfiles que no se puedan resolver.
        }
      }
      notificadores.sort((GrupoNotificador a, GrupoNotificador b) {
        final String nombreA = a.nombre.toLowerCase();
        final String nombreB = b.nombre.toLowerCase();
        final int nombreCompare = nombreA.compareTo(nombreB);
        if (nombreCompare != 0) {
          return nombreCompare;
        }
        return a.email.toLowerCase().compareTo(b.email.toLowerCase());
      });
      return notificadores;
    } on FirebaseException catch (e) {
      throw AuthServiceException(
        e.message ?? 'No fue posible consultar los notificadores del grupo.',
        code: e.code,
      );
    }
  }

  Future<void> expulsarNotificadorDelGrupo(String uidNotificador) async {
    final String uid = uidNotificador.trim();
    if (uid.isEmpty) {
      throw const AuthServiceException('El uid del notificador es invalido.');
    }

    final AppUser abogado = await _requireCurrentAppUser();
    if (abogado.rol != UserRole.abogado) {
      throw const AuthServiceException('Solo el abogado puede expulsar notificadores del grupo.');
    }
    final String groupId = abogado.groupId.trim();
    if (groupId.isEmpty) {
      throw const AuthServiceException('Tu usuario no tiene grupo asignado.');
    }

    final DocumentReference<Map<String, dynamic>> userRef = _firestore
        .collection(usuariosCollection)
        .doc(uid);

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await userRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        throw const AuthServiceException('No se encontro el notificador a expulsar.');
      }

      final Map<String, dynamic> data = snapshot.data()!;
      final String role = (data['rol'] as String? ?? '').trim().toLowerCase();
      final String targetGroupId =
          (data['groupId'] as String? ?? data['grupo_id'] as String? ?? data['group_id'] as String? ?? '')
              .trim();
      if (role != 'notificador') {
        throw const AuthServiceException('Solo puedes expulsar notificadores.');
      }
      if (targetGroupId != groupId) {
        throw const AuthServiceException('Ese notificador no pertenece a tu grupo.');
      }

      await userRef.set(
        <String, dynamic>{
          'groupId': '',
          'grupo_id': '',
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      throw AuthServiceException(
        e.message ?? 'No fue posible expulsar al notificador del grupo.',
        code: e.code,
      );
    }
  }

  Future<AppUser> _requireCurrentAppUser() async {
    final AppUser? appUser = await getCurrentAppUser();
    if (appUser == null) {
      throw const AuthServiceException('No hay una sesion activa.');
    }
    return appUser;
  }

  Future<void> _updateUserGroup({
    required String uid,
    required String groupId,
    String? joinCode,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'groupId': groupId,
      'grupo_id': groupId,
    };
    if (joinCode != null && joinCode.trim().isNotEmpty) {
      data['joinCode'] = joinCode.trim().toUpperCase();
    }

    await _firestore.collection(usuariosCollection).doc(uid).set(data, SetOptions(merge: true));
  }

  String _generarCodigoInvitacion() {
    const String chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final Random random = Random.secure();
    return List<String>.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _firebaseAuthMessage(FirebaseAuthException exception) {
    final String rawMessage = (exception.message ?? '').trim();

    switch (exception.code) {
      case 'configuration-not-found':
      case 'operation-not-allowed':
        return 'Firebase Auth no tiene habilitado Email/Password para este proyecto. Ve a Firebase Console > Authentication > Sign-in method y activa Email/Password.';
      case 'invalid-api-key':
      case 'app-not-authorized':
        return 'La API key de Firebase no es valida para esta app de Windows. Revisa restricciones de la API key en Google Cloud y permite Identity Toolkit API.';
      case 'email-already-in-use':
        return 'Este email ya esta en uso.';
      case 'invalid-email':
        return 'El email no tiene formato valido.';
      case 'weak-password':
        return 'La password es demasiado debil.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Credenciales invalidas.';
      case 'network-request-failed':
        return 'No se pudo conectar con Firebase. Verifica tu internet, firewall o proxy.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos y vuelve a intentar.';
      case 'internal-error':
      case 'unknown':
      case 'unknown-error':
        final String lower = rawMessage.toLowerCase();
        if (lower.contains('api key not valid') || lower.contains('api_key_invalid')) {
          return 'La API key de Firebase no es valida para Windows. Revisa `firebase_options.dart` y las restricciones de la API key en Google Cloud.';
        }
        if (lower.contains('configuration_not_found') || lower.contains('email_password_provider')) {
          return 'Firebase Auth no tiene habilitado Email/Password para este proyecto.';
        }
        if (rawMessage.isNotEmpty) {
          return 'Firebase devolvio un error interno al autenticar. Detalle tecnico: $rawMessage';
        }
        return 'Firebase devolvio un error interno al autenticar. Verifica Email/Password, fecha/hora del equipo y restricciones de API key.';
      default:
        return rawMessage.isEmpty ? 'Error de autenticacion.' : rawMessage;
    }
  }

  String _firebaseGenericAuthMessage(FirebaseException exception) {
    final String code = exception.code.trim().toLowerCase();
    final String rawMessage = (exception.message ?? '').trim();
    final String lower = rawMessage.toLowerCase();

    if (code == 'unknown' || code == 'unknown-error' || code == 'internal-error') {
      if (lower.contains('api key not valid') || lower.contains('api_key_invalid')) {
        return 'La API key de Firebase no es valida para Windows. Revisa restricciones en Google Cloud y habilita Identity Toolkit API.';
      }
      if (lower.contains('configuration_not_found') ||
          lower.contains('email_password_provider') ||
          lower.contains('operation_not_allowed')) {
        return 'Firebase Auth no tiene habilitado Email/Password para este proyecto.';
      }
      if (lower.contains('has occured') || lower.contains('has occurred')) {
        return 'Firebase devolvio un error interno al autenticar. Revisa API key, metodo Email/Password y que tu reloj de Windows este en hora automatica.';
      }
    }

    return rawMessage.isEmpty
        ? 'Error de autenticacion en Firebase ($code).'
        : rawMessage;
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AuthServiceException(code: $code, message: $message)';
}
