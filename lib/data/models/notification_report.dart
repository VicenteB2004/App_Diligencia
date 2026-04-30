import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:notificador/data/utils/pdf_bytes_parser.dart';

class NotificationReport {
  const NotificationReport({
    required this.id,
    required this.ubicacionId,
    required this.groupId,
    required this.notificadorUid,
    required this.notificadorNombre,
    required this.notificadorEmail,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.tipoNotificacion,
    required this.personaNotificada,
    required this.descripcionDiligencia,
    required this.nombreUbicacion,
    required this.identificacionTecnica,
    required this.fechaHora,
    required this.createdAt,
    required this.pdfBytes,
    this.pdfDownloadUrl,
    this.pdfStoragePath,
    // Datos del abogado
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.cedulaAbogado,
    // Datos de familiar/trabajador
    this.nombreFamiliarTrabajador,
    this.cedulaFamiliarTrabajador,
  });

  final String id;
  final int ubicacionId;
  final String groupId;
  final String notificadorUid;
  final String notificadorNombre;
  final String notificadorEmail;
  final String direccion;
  final double lat;
  final double lng;
  final String tipoNotificacion;
  final String personaNotificada;
  final String descripcionDiligencia;
  final String nombreUbicacion;
  final String identificacionTecnica;
  final DateTime fechaHora;
  final DateTime createdAt;
  final Uint8List? pdfBytes;
  final String? pdfDownloadUrl;
  final String? pdfStoragePath;
  // Datos del abogado
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? cedulaAbogado;
  // Datos de familiar/trabajador
  final String? nombreFamiliarTrabajador;
  final String? cedulaFamiliarTrabajador;

  factory NotificationReport.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    final Timestamp? fechaHoraTs = data['fechaHora'] as Timestamp?;
    final Timestamp? createdAtTs = data['createdAt'] as Timestamp?;
    Uint8List? pdfBytes = PdfBytesParser.parse(
      data['pdfBytes'] ??
          data['pdf_bytes'] ??
          data['pdf'] ??
          data['pdfBase64'] ??
          data['pdf_base64'] ??
          data['archivoPdf'] ??
          data['archivo_pdf'],
    );
    pdfBytes ??= PdfBytesParser.parseFromMapByLikelyKeys(data);
    pdfBytes ??= PdfBytesParser.parse(data);

    return NotificationReport(
      id: doc.id,
      ubicacionId: (data['ubicacionId'] as num?)?.toInt() ?? 0,
      groupId: (data['groupId'] as String? ?? '').trim(),
      notificadorUid: (data['notificadorUid'] as String? ?? '').trim(),
      notificadorNombre: (data['notificadorNombre'] as String? ?? '').trim(),
      notificadorEmail: (data['notificadorEmail'] as String? ?? '').trim(),
      direccion: (data['direccion'] as String? ?? '').trim(),
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
      tipoNotificacion: (data['tipoNotificacion'] as String? ?? '').trim(),
      personaNotificada: (data['personaNotificada'] as String? ?? '').trim(),
      descripcionDiligencia: (data['descripcionDiligencia'] as String? ?? data['observacion'] as String? ?? '').trim(),
      nombreUbicacion: (data['nombreUbicacion'] as String? ?? '').trim(),
      identificacionTecnica: (data['identificacionTecnica'] as String? ?? '').trim(),
      fechaHora: fechaHoraTs?.toDate().toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: createdAtTs?.toDate().toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      pdfBytes: pdfBytes,
      pdfDownloadUrl: (data['pdfDownloadUrl'] as String? ?? data['pdf_download_url'] as String? ?? data['pdfUrl'] as String? ?? data['pdf_url'] as String? ?? '').trim(),
      pdfStoragePath: (data['pdfStoragePath'] as String? ?? data['pdf_storage_path'] as String? ?? '').trim(),
      razonSocial: (data['razonSocial'] as String? ?? '').trim(),
      ruc: (data['ruc'] as String? ?? '').trim(),
      representanteLegal: (data['representanteLegal'] as String? ?? '').trim(),
      cedulaAbogado: (data['cedulaAbogado'] as String? ?? '').trim(),
      nombreFamiliarTrabajador: (data['nombreFamiliarTrabajador'] as String? ?? '').trim(),
      cedulaFamiliarTrabajador: (data['cedulaFamiliarTrabajador'] as String? ?? '').trim(),
    );
  }

}
