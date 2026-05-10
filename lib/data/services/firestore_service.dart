import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:notificador/data/models/group_location.dart';
import 'package:notificador/data/models/notification_report.dart';
import 'package:notificador/data/utils/pdf_bytes_parser.dart';

class FirestoreService {
  FirestoreService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })
    : _firestoreSource = firestore,
      _authSource = auth,
      _storageSource = storage;

  static const String usuariosCollection = 'usuarios';
  static const String ubicacionesCollection = 'ubicaciones';
  static const String reportesCollection = 'reportes_notificacion';
  static const int _maxPdfBytesFirestore = 950000;

  final FirebaseFirestore? _firestoreSource;
  final FirebaseAuth? _authSource;
  final FirebaseStorage? _storageSource;

  late final FirebaseFirestore _firestore = _firestoreSource ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = _authSource ?? FirebaseAuth.instance;
  late final FirebaseStorage _storage = _storageSource ?? FirebaseStorage.instance;

  Future<String> getCurrentUserGroupId() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const FirestoreServiceException('No hay un usuario autenticado.');
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> userDoc = await _firestore
          .collection(usuariosCollection)
          .doc(uid)
          .get();

      final Map<String, dynamic> data = userDoc.data() ?? <String, dynamic>{};
      final String groupId =
          (data['groupId'] as String? ??
                  data['grupo_id'] as String? ??
                  data['group_id'] as String? ??
                  '')
              .trim();
      if (groupId.isEmpty) {
        throw const FirestoreServiceException(
          'El usuario no tiene groupId asignado.',
        );
      }

      return groupId;
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible obtener el groupId del usuario.',
        code: e.code,
      );
    }
  }

  Future<String> saveLocation({
    required double lat,
    required double lng,
    String? groupId,
    DateTime? timestamp,
    int? ubicacionId,
    String? nombreUbicacion,
    String? referenciaUbicacion,
    String? identificacionTecnica,
    String? razonSocial,
    String? ruc,
    String? representanteLegal,
    String? nombreNotificador,
    String? cedulaNotificador,
    bool esSegundaNotificacion = false,
    String? estado,
  }) async {
    _validateCoordinates(lat: lat, lng: lng);

    final String targetGroupId = groupId == null || groupId.trim().isEmpty
        ? await getCurrentUserGroupId()
        : groupId.trim();

    final Map<String, dynamic> payloadExtendido = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'groupId': targetGroupId,
      'timestamp': timestamp == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(timestamp.toUtc()),
      if (ubicacionId != null) 'ubicacionId': ubicacionId,
      if ((nombreUbicacion ?? '').trim().isNotEmpty) 'nombreUbicacion': nombreUbicacion!.trim(),
      if ((referenciaUbicacion ?? '').trim().isNotEmpty)
        'referenciaUbicacion': referenciaUbicacion!.trim(),
      if ((identificacionTecnica ?? '').trim().isNotEmpty)
        'identificacionTecnica': identificacionTecnica!.trim().toUpperCase(),
      if ((razonSocial ?? '').trim().isNotEmpty) 'razonSocial': razonSocial!.trim(),
      if ((ruc ?? '').trim().isNotEmpty) 'ruc': ruc!.trim(),
      if ((representanteLegal ?? '').trim().isNotEmpty)
        'representanteLegal': representanteLegal!.trim(),
      if ((nombreNotificador ?? '').trim().isNotEmpty)
        'nombreNotificador': nombreNotificador!.trim(),
      if ((cedulaNotificador ?? '').trim().isNotEmpty)
        'cedulaNotificador': cedulaNotificador!.trim(),
      'esSegundaNotificacion': esSegundaNotificacion,
      if ((estado ?? '').trim().isNotEmpty) 'estado': estado!.trim(),
    };

    final Map<String, dynamic> payloadBasico = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'groupId': targetGroupId,
      'timestamp': timestamp == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(timestamp.toUtc()),
    };

    try {
      final DocumentReference<Map<String, dynamic>> ref = await _firestore
          .collection(ubicacionesCollection)
          .add(payloadExtendido);
      return ref.id;
    } on FirebaseException catch (e) {
      final bool intentarBasico =
          (e.code == 'permission-denied' || e.code == 'failed-precondition') &&
          payloadExtendido.length > payloadBasico.length;
      if (intentarBasico) {
        try {
          final DocumentReference<Map<String, dynamic>> ref = await _firestore
              .collection(ubicacionesCollection)
              .add(payloadBasico);
          return ref.id;
        } on FirebaseException {
          // Continua al manejo inferior para exponer el error original.
        }
      }
      throw FirestoreServiceException(
        e.message ?? 'No fue posible guardar la ubicacion.',
        code: e.code,
      );
    }
  }

  Future<List<GroupLocation>> getLocationsByCurrentUserGroup() async {
    final String groupId = await getCurrentUserGroupId();
    return getLocationsByGroupId(groupId);
  }

  Future<List<GroupLocation>> getLocationsByGroupId(String groupId) async {
    final String normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw const FirestoreServiceException('El groupId no puede estar vacio.');
    }

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection(ubicacionesCollection)
          .where('groupId', isEqualTo: normalizedGroupId)
          .get();

      return _mapGroupLocationsSafely(snapshot.docs);
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible consultar ubicaciones.',
        code: e.code,
      );
    } on FormatException catch (e) {
      throw FirestoreServiceException(e.message);
    }
  }

  Stream<List<GroupLocation>> streamLocationsByCurrentUserGroup() async* {
    final String groupId = await getCurrentUserGroupId();
    yield* streamLocationsByGroupId(groupId);
  }

  Stream<List<GroupLocation>> streamLocationsByGroupId(String groupId) {
    final String normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw const FirestoreServiceException('El groupId no puede estar vacio.');
    }

    return _firestore
        .collection(ubicacionesCollection)
        .where('groupId', isEqualTo: normalizedGroupId)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return _mapGroupLocationsSafely(snapshot.docs);
        });
  }

  Future<void> deleteLocationsByCurrentUserGroup() async {
    final String groupId = await getCurrentUserGroupId();
    await deleteLocationsByGroupId(groupId);
  }

  Future<void> deleteLocationsByGroupId(String groupId) async {
    final String normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw const FirestoreServiceException('El groupId no puede estar vacio.');
    }

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection(ubicacionesCollection)
          .where('groupId', isEqualTo: normalizedGroupId)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      const int batchSize = 450;
      for (int i = 0; i < snapshot.docs.length; i += batchSize) {
        final WriteBatch batch = _firestore.batch();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> chunk =
            snapshot.docs.skip(i).take(batchSize).toList();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible limpiar las ubicaciones remotas.',
        code: e.code,
      );
    }
  }

  Future<void> deleteLocationByDocId(String docId) async {
    final String normalizedId = docId.trim();

    if (normalizedId.isEmpty) {
      throw const FirestoreServiceException(
        'El ID de ubicación es inválido.',
      );
    }

    try {
      await _firestore
          .collection(ubicacionesCollection)
          .doc(normalizedId)
          .delete();
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible eliminar la ubicación.',
        code: e.code,
      );
    }
  }

  List<GroupLocation> _mapGroupLocationsSafely(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final List<GroupLocation> output = <GroupLocation>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      try {
        output.add(GroupLocation.fromDocument(doc));
      } on FormatException {
        // Ignora documentos legacy o mal formados para no romper toda la sincronizacion.
      }
    }
    output.sort((GroupLocation a, GroupLocation b) => b.timestamp.compareTo(a.timestamp));
    return output;
  }

  Stream<List<NotificationReport>> streamNotificationReportsByCurrentUserGroup({
    int limit = 50,
  }) async* {
    final String groupId = await getCurrentUserGroupId();
    yield* streamNotificationReportsByGroupId(groupId, limit: limit);
  }

  Future<List<NotificationReport>> getNotificationReportsByCurrentUserGroup({
    int limit = 50,
  }) async {
    final String groupId = await getCurrentUserGroupId();
    return getNotificationReportsByGroupId(groupId, limit: limit);
  }

  Future<List<NotificationReport>> getNotificationReportsByGroupId(
    String groupId, {
    int limit = 50,
  }) async {
    final String normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw const FirestoreServiceException('El groupId no puede estar vacio.');
    }

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection(reportesCollection)
          .where('groupId', isEqualTo: normalizedGroupId)
          .get();

      final List<NotificationReport> reportes = snapshot.docs
          .map(NotificationReport.fromDocument)
          .toList()
        ..sort((NotificationReport a, NotificationReport b) =>
            b.createdAt.compareTo(a.createdAt));

      if (limit <= 0 || reportes.length <= limit) {
        return reportes;
      }
      return reportes.take(limit).toList();
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible consultar reportes.',
        code: e.code,
      );
    }
  }

  Stream<List<NotificationReport>> streamNotificationReportsByGroupId(
    String groupId, {
    int limit = 50,
  }) {
    final String normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw const FirestoreServiceException('El groupId no puede estar vacio.');
    }

    return _firestore
        .collection(reportesCollection)
        .where('groupId', isEqualTo: normalizedGroupId)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          final List<NotificationReport> reportes = snapshot.docs
              .map(NotificationReport.fromDocument)
              .toList()
            ..sort((NotificationReport a, NotificationReport b) =>
                b.createdAt.compareTo(a.createdAt));

          if (limit <= 0 || reportes.length <= limit) {
            return reportes;
          }
          return reportes.take(limit).toList();
        });
  }

  Future<String> saveNotificationReport({
    required int ubicacionId,
    required double lat,
    required double lng,
    required String direccion,
    required String tipoNotificacion,
    required String personaNotificada,
    required String descripcionDiligencia,
    required String notificadorNombre,
    required String notificadorEmail,
    required DateTime fechaHora,
    required Uint8List pdfBytes,
    String? nombreUbicacion,
    String? referenciaUbicacion,
    String? identificacionTecnica,
    bool esSegundaNotificacion = false,
    String? cedulaAbogado,
    String? nombreFamiliarTrabajador,
    String? cedulaFamiliarTrabajador,
  }) async {
    _validateCoordinates(lat: lat, lng: lng);

    if (pdfBytes.isEmpty || !PdfBytesParser.looksLikePdf(pdfBytes)) {
      throw const FirestoreServiceException(
        'No se pudo enviar el informe porque el PDF generado es invalido.',
      );
    }

    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const FirestoreServiceException('No hay un usuario autenticado.');
    }

    final Map<String, dynamic> currentProfile = await _getCurrentUserProfile(uid);
    final String role = (currentProfile['rol'] as String? ?? '').trim().toLowerCase();
    if (role != 'notificador') {
      throw const FirestoreServiceException(
        'Solo el rol notificador puede enviar informes.',
      );
    }

    final String groupId =
        (currentProfile['groupId'] as String? ??
                currentProfile['grupo_id'] as String? ??
                currentProfile['group_id'] as String? ??
                '')
            .trim();
    if (groupId.isEmpty) {
      throw const FirestoreServiceException(
        'Tu usuario no tiene grupo asignado. Debes unirte a un grupo antes de enviar informes.',
      );
    }

    final bool incluirPdfEnFirestore = pdfBytes.lengthInBytes <= _maxPdfBytesFirestore;
    String? pdfStoragePath;
    String? pdfDownloadUrl;
    try {
      final String stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      final Reference ref = _storage
          .ref()
          .child('reportes_notificacion')
          .child(groupId)
          .child(uid)
          .child('${stamp}_u${ubicacionId}.pdf');
      await ref.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      pdfStoragePath = ref.fullPath;
      pdfDownloadUrl = await ref.getDownloadURL();
    } catch (_) {
      // Si Storage falla, se mantiene el flujo con Firestore cuando sea posible.
    }

    if (!incluirPdfEnFirestore && (pdfDownloadUrl ?? '').trim().isEmpty) {
      final int kb = (pdfBytes.lengthInBytes / 1024).round();
      throw FirestoreServiceException(
        'El PDF es demasiado grande para Firestore (${kb} KB) y no se pudo subir a Storage.',
      );
    }

    final Map<String, dynamic> baseData = <String, dynamic>{
      'ubicacionId': ubicacionId,
      'groupId': groupId,
      'notificadorUid': uid,
      'notificadorNombre': notificadorNombre,
      'notificadorEmail': notificadorEmail,
      'direccion': direccion,
      'lat': lat,
      'lng': lng,
      'tipoNotificacion': tipoNotificacion,
      'personaNotificada': personaNotificada,
      'nombreUbicacion': (nombreUbicacion ?? '').trim(),
      if ((referenciaUbicacion ?? '').trim().isNotEmpty) 'referenciaUbicacion': referenciaUbicacion!.trim(),
      'identificacionTecnica': (identificacionTecnica ?? '').trim().toUpperCase(),
      if ((cedulaAbogado ?? '').trim().isNotEmpty) 'cedulaAbogado': cedulaAbogado!.trim(),
      if ((nombreFamiliarTrabajador ?? '').trim().isNotEmpty)
        'nombreFamiliarTrabajador': nombreFamiliarTrabajador!.trim(),
      if ((cedulaFamiliarTrabajador ?? '').trim().isNotEmpty)
        'cedulaFamiliarTrabajador': cedulaFamiliarTrabajador!.trim(),
      'fechaHora': Timestamp.fromDate(fechaHora.toUtc()),
      'createdAt': FieldValue.serverTimestamp(),
      if (incluirPdfEnFirestore) 'pdfBytes': Blob(pdfBytes),
      if ((pdfStoragePath ?? '').trim().isNotEmpty) 'pdfStoragePath': pdfStoragePath,
      if ((pdfDownloadUrl ?? '').trim().isNotEmpty) 'pdfDownloadUrl': pdfDownloadUrl,
    };
    final Map<String, dynamic> baseDataConSegundaNotificacion = <String, dynamic>{
      ...baseData,
      'esSegundaNotificacion': esSegundaNotificacion,
    };
    final Map<String, dynamic> baseDataLegacy = Map<String, dynamic>.from(baseDataConSegundaNotificacion)
      ..remove('referenciaUbicacion');

    try {
      final DocumentReference<Map<String, dynamic>> ref = await _firestore
          .collection(reportesCollection)
          .add(<String, dynamic>{
            ...baseDataConSegundaNotificacion,
            'descripcionDiligencia': descripcionDiligencia,
            'observacion': descripcionDiligencia,
          });
      return ref.id;
    } on FirebaseException catch (e) {
      final bool canRetryLegacy =
          e.code == 'permission-denied' || e.code == 'failed-precondition';
      if (canRetryLegacy) {
        try {
          final DocumentReference<Map<String, dynamic>> ref = await _firestore
              .collection(reportesCollection)
              .add(<String, dynamic>{
                ...baseDataLegacy,
                // Reglas antiguas: solo observacion.
                'observacion': descripcionDiligencia,
              });
          return ref.id;
        } on FirebaseException {
          // Continua al manejo inferior para exponer mensaje original.
        }
      }
      if (e.code == 'permission-denied') {
        throw const FirestoreServiceException(
          'Permiso denegado al enviar informe. Verifica que usuarios/{uid} tenga rol "notificador" y groupId/grupo_id valido.',
          code: 'permission-denied',
        );
      }
      if (e.code == 'invalid-argument' || e.code == 'failed-precondition') {
        throw FirestoreServiceException(
          'No fue posible guardar el informe. El PDF puede exceder el tamano permitido por Firestore.',
          code: e.code,
        );
      }
      throw FirestoreServiceException(
        e.message ?? 'No fue posible guardar el informe en Firestore.',
        code: e.code,
      );
    }
  }

  Future<Map<String, dynamic>> _getCurrentUserProfile(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> userDoc = await _firestore
          .collection(usuariosCollection)
          .doc(uid)
          .get();
      return userDoc.data() ?? <String, dynamic>{};
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible validar el perfil del usuario.',
        code: e.code,
      );
    }
  }

  Future<void> deleteNotificationReport(String reportId) async {
    final String normalizedId = reportId.trim();
    if (normalizedId.isEmpty) {
      throw const FirestoreServiceException('El id del informe es invalido.');
    }

    try {
      await _firestore.collection(reportesCollection).doc(normalizedId).delete();
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible eliminar el informe PDF.',
        code: e.code,
      );
    }
  }

  Future<Uint8List?> getNotificationReportPdfBytes(
    String reportId, {
    String? knownPdfDownloadUrl,
    String? knownPdfStoragePath,
  }) async {
    final String normalizedId = reportId.trim();
    if (normalizedId.isEmpty) {
      throw const FirestoreServiceException('El id del informe es invalido.');
    }

    try {
      final List<String> debugSteps = <String>[];
      // 1) Intento rapido con metadatos ya cargados en memoria del reporte.
      final Uint8List? fromKnownUrl = await _downloadPdfFromUrlOrStorageRef(
        (knownPdfDownloadUrl ?? '').trim(),
      );
      if (fromKnownUrl != null && fromKnownUrl.isNotEmpty) {
        _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde knownPdfDownloadUrl (${fromKnownUrl.lengthInBytes} bytes).');
        return fromKnownUrl;
      }
      if ((knownPdfDownloadUrl ?? '').trim().isNotEmpty) {
        debugSteps.add('knownPdfDownloadUrl sin bytes validos');
      }

      final Uint8List? fromKnownPath = await _downloadPdfFromStoragePath(
        (knownPdfStoragePath ?? '').trim(),
      );
      if (fromKnownPath != null && fromKnownPath.isNotEmpty) {
        _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde knownPdfStoragePath (${fromKnownPath.lengthInBytes} bytes).');
        return fromKnownPath;
      }
      if ((knownPdfStoragePath ?? '').trim().isNotEmpty) {
        debugSteps.add('knownPdfStoragePath sin bytes validos');
      }

      final DocumentReference<Map<String, dynamic>> reportRef = _firestore
          .collection(reportesCollection)
          .doc(normalizedId);

      // 2) Preferimos servidor para evitar leer cache desactualizada.
      DocumentSnapshot<Map<String, dynamic>> doc = await reportRef.get(
        const GetOptions(source: Source.server),
      );
      if (!doc.exists) {
        doc = await reportRef.get();
      }
      if (!doc.exists) {
        _debugPdf(reportId: normalizedId, message: 'No existe documento en reportes_notificacion.');
        return null;
      }

      final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
      Uint8List? parsed = PdfBytesParser.parse(
        data['pdfBytes'] ??
            data['pdf_bytes'] ??
            data['pdf'] ??
            data['pdfBase64'] ??
            data['pdf_base64'] ??
            data['archivoPdf'] ??
            data['archivo_pdf'],
      );
      parsed ??= PdfBytesParser.parseFromMapByLikelyKeys(data);
      if (parsed != null && parsed.isNotEmpty) {
        _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde campo embebido en Firestore (${parsed.lengthInBytes} bytes).');
        return parsed;
      }
      debugSteps.add('sin pdfBytes/Blob valido en Firestore');

      final String downloadUrl =
          (data['pdfDownloadUrl'] as String? ??
                  data['pdf_download_url'] as String? ??
                  data['pdfUrl'] as String? ??
                  data['pdf_url'] as String? ??
                  data['archivoPdfDownloadUrl'] as String? ??
                  data['archivo_pdf_download_url'] as String? ??
                  data['archivoPdfUrl'] as String? ??
                  data['archivo_pdf_url'] as String? ??
                  data['urlPdf'] as String? ??
                  data['url_pdf'] as String? ??
                  data['archivoPdfUrl'] as String? ??
                  data['archivo_pdf_url'] as String? ??
                  '')
              .trim();
      if (downloadUrl.isNotEmpty) {
        final Uint8List? fromUrl = await _downloadPdfFromUrlOrStorageRef(downloadUrl);
        if (fromUrl != null && fromUrl.isNotEmpty) {
          _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde pdfDownloadUrl (${fromUrl.lengthInBytes} bytes).');
          return fromUrl;
        }
        debugSteps.add('pdfDownloadUrl sin bytes validos');
      }

      for (final String candidateUrl in _collectLikelyPdfUrls(data)) {
        final Uint8List? fromCandidate = await _downloadPdfFromUrlOrStorageRef(candidateUrl);
        if (fromCandidate != null && fromCandidate.isNotEmpty) {
          _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde URL candidata (${fromCandidate.lengthInBytes} bytes).');
          return fromCandidate;
        }
      }

      final String storagePath =
          (data['pdfStoragePath'] as String? ??
                  data['pdf_storage_path'] as String? ??
                  data['storagePathPdf'] as String? ??
                  data['storage_path_pdf'] as String? ??
                  '')
              .trim();
      if (storagePath.isNotEmpty) {
        final Uint8List? fromPath = await _downloadPdfFromStoragePath(storagePath);
        if (fromPath != null && fromPath.isNotEmpty) {
          _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde pdfStoragePath (${fromPath.lengthInBytes} bytes).');
          return fromPath;
        }
        debugSteps.add('pdfStoragePath sin bytes validos');
      }

      for (final String candidatePath in _collectLikelyStoragePaths(data)) {
        final Uint8List? fromCandidate = await _downloadPdfFromStoragePath(candidatePath);
        if (fromCandidate != null && fromCandidate.isNotEmpty) {
          _debugPdf(reportId: normalizedId, message: 'PDF recuperado desde storage path candidato (${fromCandidate.lengthInBytes} bytes).');
          return fromCandidate;
        }
      }

      _debugPdf(
        reportId: normalizedId,
        message: 'No se pudo recuperar PDF. Diagnostico: ${debugSteps.join(' | ')}',
      );
      return null;
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible obtener el PDF del informe.',
        code: e.code,
      );
    }
  }

  void _debugPdf({required String reportId, required String message}) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[PDF][$reportId] $message');
  }

  Future<Uint8List?> _downloadPdfFromUrlOrStorageRef(String url) async {
    if (url.trim().isEmpty) {
      return null;
    }

    final String normalized = url.trim();
    try {
      if (normalized.startsWith('gs://')) {
        final Uint8List? byGs = await _storage.refFromURL(normalized).getData(20 * 1024 * 1024);
        if (byGs != null && byGs.isNotEmpty && PdfBytesParser.looksLikePdf(byGs)) {
          return byGs;
        }
        return null;
      }

      final Uri uri = Uri.parse(normalized);
      final http.Response response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.bodyBytes.isNotEmpty && PdfBytesParser.looksLikePdf(response.bodyBytes)) {
          return response.bodyBytes;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadPdfFromStoragePath(String storagePath) async {
    if (storagePath.trim().isEmpty) {
      return null;
    }
    try {
      final Uint8List? bytes = await _storage
          .ref(storagePath.trim())
          .getData(20 * 1024 * 1024);
      if (bytes != null && bytes.isNotEmpty && PdfBytesParser.looksLikePdf(bytes)) {
        return bytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<String> _collectLikelyPdfUrls(Map<String, dynamic> data) {
    final Set<String> output = <String>{};
    for (final MapEntry<String, dynamic> entry in data.entries) {
      final dynamic raw = entry.value;
      if (raw is! String) {
        continue;
      }
      final String value = raw.trim();
      if (value.isEmpty) {
        continue;
      }

      final String key = entry.key.toLowerCase();
      final bool keySuggestsUrl = key.contains('url') || key.contains('pdf') || key.contains('archivo');
      final bool valueSuggestsUrl =
          value.startsWith('http://') ||
          value.startsWith('https://') ||
          value.startsWith('gs://') ||
          value.contains('firebasestorage.googleapis.com');
      if (keySuggestsUrl && valueSuggestsUrl) {
        output.add(value);
      }
    }
    return output.toList(growable: false);
  }

  List<String> _collectLikelyStoragePaths(Map<String, dynamic> data) {
    final Set<String> output = <String>{};
    for (final MapEntry<String, dynamic> entry in data.entries) {
      final dynamic raw = entry.value;
      if (raw is! String) {
        continue;
      }
      final String value = raw.trim();
      if (value.isEmpty) {
        continue;
      }

      final String key = entry.key.toLowerCase();
      final bool keySuggestsPath = key.contains('path') || key.contains('storage') || key.contains('pdf');
      final bool valueLooksPath =
          !value.startsWith('http://') &&
          !value.startsWith('https://') &&
          !value.startsWith('gs://') &&
          value.contains('/') &&
          (value.contains('reportes_notificacion') || value.endsWith('.pdf'));
      if (keySuggestsPath && valueLooksPath) {
        output.add(value);
      }
    }
    return output.toList(growable: false);
  }

  void _validateCoordinates({required double lat, required double lng}) {
    if (lat < -90 || lat > 90) {
      throw const FirestoreServiceException(
        'Latitud fuera de rango (-90 a 90).',
      );
    }
    if (lng < -180 || lng > 180) {
      throw const FirestoreServiceException(
        'Longitud fuera de rango (-180 a 180).',
      );
    }
  }

  Future<void> updateLocationEstado({
    required String ubicacionDocId,
    required String estado,
  }) async {
    final String normalizedId = ubicacionDocId.trim();
    if (normalizedId.isEmpty) {
      throw const FirestoreServiceException('El ID de ubicacion es invalido.');
    }

    try {
      await _firestore
          .collection(ubicacionesCollection)
          .doc(normalizedId)
          .update(<String, dynamic>{
        'estado': estado,
      });
    } on FirebaseException catch (e) {
      throw FirestoreServiceException(
        e.message ?? 'No fue posible actualizar el estado de la ubicacion.',
        code: e.code,
      );
    }
  }
}

class FirestoreServiceException implements Exception {
  const FirestoreServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      'FirestoreServiceException(code: $code, message: $message)';
}
