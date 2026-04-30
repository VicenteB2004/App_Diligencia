import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportePdfPayload {
  const ReportePdfPayload({
    required this.ubicacionId,
    this.nombreUbicacion,
    required this.fechaHora,
    required this.tipoNotificacion,
    required this.personaNotificada,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    required this.notificadorNombre,
    required this.notificadorEmail,
    required this.descripcionDiligencia,
    required this.fotoRegistroBytes,
    required this.fotoRegistroSecundariaBytes,
    this.fotoMapaBytes,
    this.esSegundaNotificacion = false,
    this.identificacionRpv = false,
    this.identificacionOpi = false,
    // Datos del abogado
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.nombreNotificadorAsignado,
    this.cedulaNotificadorAsignado,
    // Datos de familiar/trabajador
    this.nombreFamiliarTrabajador,
    this.cedulaFamiliarTrabajador,
  });

  final int ubicacionId;
  final String? nombreUbicacion;
  final DateTime fechaHora;
  final String tipoNotificacion;
  final String personaNotificada;
  final String direccion;
  final double latitud;
  final double longitud;
  final String notificadorNombre;
  final String notificadorEmail;
  final String descripcionDiligencia;
  final Uint8List fotoRegistroBytes;
  final Uint8List fotoRegistroSecundariaBytes;
  final Uint8List? fotoMapaBytes;
  final bool esSegundaNotificacion;
  final bool identificacionRpv;
  final bool identificacionOpi;
  // Datos del abogado
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? nombreNotificadorAsignado;
  final String? cedulaNotificadorAsignado;
  // Datos de familiar/trabajador
  final String? nombreFamiliarTrabajador;
  final String? cedulaFamiliarTrabajador;
}

class ReportePdfService {
  Future<Uint8List> generarReporte(ReportePdfPayload payload) async {
    final pw.Document pdf = pw.Document();
    final pw.MemoryImage? fotoMapa = _safeMemoryImage(
      payload.fotoMapaBytes,
      esMapa: true,
    );
    final pw.MemoryImage? fotoRegistro = _safeMemoryImage(payload.fotoRegistroBytes);
    final pw.MemoryImage? fotoRegistro2 = _safeMemoryImage(payload.fotoRegistroSecundariaBytes);
    if (fotoRegistro == null || fotoRegistro2 == null) {
      throw const FormatException(
        'Las fotos de registro no son validas para incrustar en el PDF.',
      );
    }
    final PdfColor colorTitulo = PdfColor.fromHex('#1E4E8C');
    final String nombreUbicacion = (payload.nombreUbicacion ?? '').trim().isEmpty
        ? 'U-${payload.ubicacionId}'
        : payload.nombreUbicacion!.trim();
    final String direccion = payload.direccion.trim().isEmpty ? '-' : payload.direccion.trim();
    final String direccionDelSitio = direccion == '-' ? nombreUbicacion : direccion;
    final String descripcionDiligencia = payload.descripcionDiligencia.trim();

    pdf.addPage(
      pw.MultiPage(
        maxPages: 2,
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          theme: pw.ThemeData.withFont(
            base: pw.Font.times(),
            bold: pw.Font.timesBold(),
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          pw.Center(
            child: pw.Text(
              'REPORTE DE NOTIFICACION',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: colorTitulo,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Container(height: 1, color: colorTitulo),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _textoCuerpo(
              'Primera Notificacion ${_checkbox(!payload.esSegundaNotificacion)}   '
              'Segunda Notificacion ${_checkbox(payload.esSegundaNotificacion)}',
              fontSize: 10,
            ),
          ),
          pw.SizedBox(height: 10),
          _seccionTitulo('1. DATOS GENERALES', colorTitulo),
          _fila('Fecha de notificacion', _formatDate(payload.fechaHora)),
          _fila('Hora de notificacion', _formatTime(payload.fechaHora)),
          _fila(
            'Tipo de notificacion',
            '${_checkbox(payload.tipoNotificacion.toLowerCase().contains('personal'))} Personal   '
            '${_checkbox(payload.tipoNotificacion.toLowerCase().contains('boleta'))} Por boleta',
          ),
          _fila(
            'Identificacion Tecnica',
            '${_checkbox(payload.identificacionRpv)} RPV   ${_checkbox(payload.identificacionOpi)} OPI',
          ),
          _fila(
            'Persona',
            '${_checkbox(payload.personaNotificada.toLowerCase().contains('natural'))} Persona Natural   '
            '${_checkbox(payload.personaNotificada.toLowerCase().contains('familiar'))} Familiar   '
            '${_checkbox(payload.personaNotificada.toLowerCase().contains('representante'))} Representante Legal   '
            '${_checkbox(payload.personaNotificada.toLowerCase().contains('trabajador'))} Trabajador',
          ),
          _fila('RAZON SOCIAL', (payload.razonSocial ?? '').trim().isEmpty ? '-' : (payload.razonSocial ?? '').trim()),
          _fila('RUC', (payload.ruc ?? '').trim().isEmpty ? '-' : (payload.ruc ?? '').trim()),
          _fila(
            'REPRESENTANTE LEGAL',
            (payload.representanteLegal ?? '').trim().isEmpty ? '-' : (payload.representanteLegal ?? '').trim(),
          ),
          if ((payload.nombreFamiliarTrabajador ?? '').trim().isNotEmpty) ...<pw.Widget>[
            _fila('Nombre Familiar/Trabajador', payload.nombreFamiliarTrabajador ?? ''),
            _fila('Cedula Familiar/Trabajador', payload.cedulaFamiliarTrabajador ?? ''),
          ],
          pw.SizedBox(height: 10),
          _seccionTitulo('2. UBICACION DEL LUGAR DE NOTIFICACION', colorTitulo),
          _fila('Direccion del sitio', direccionDelSitio),
          _fila(
            'Coordenadas geograficas',
            '(${payload.latitud.toStringAsFixed(4)}, ${payload.longitud.toStringAsFixed(4)})',
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Container(
              width: 170,
              height: 105,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500)),
              child: fotoMapa == null
                  ? pw.Center(
                      child: _textoCuerpo(
                        'Mapa no disponible',
                        fontSize: 9,
                      ),
                    )
                  : pw.Image(fotoMapa, fit: pw.BoxFit.cover),
            ),
          ),
          pw.SizedBox(height: 10),
          _seccionTitulo('3. REGISTRO FOTOGRAFICO', colorTitulo),
          pw.SizedBox(height: 4),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Container(
                  height: 116,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700)),
                  child: pw.Image(fotoRegistro, fit: pw.BoxFit.cover),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  height: 116,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700)),
                  child: pw.Image(fotoRegistro2, fit: pw.BoxFit.cover),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _seccionTitulo('4. DESCRIPCION DE LA DILIGENCIA', colorTitulo),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: _textoCuerpo(
              descripcionDiligencia.isEmpty ? ' ' : descripcionDiligencia,
              fontSize: 10,
            ),
          ),
          ..._lineasDiligencia(4),
          pw.SizedBox(height: 10),
          _seccionTitulo('5. DATOS DEL NOTIFICADOR', colorTitulo),
          _fila(
            'Nombre',
            (payload.nombreNotificadorAsignado ?? '').trim().isEmpty
                ? payload.notificadorNombre
                : (payload.nombreNotificadorAsignado ?? '').trim(),
          ),
          _fila('Cedula', (payload.cedulaNotificadorAsignado ?? '').trim().isEmpty ? '-' : (payload.cedulaNotificadorAsignado ?? '').trim()),
          pw.Row(
            children: <pw.Widget>[
              pw.Text('Firma: ___________________', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.NewPage(),
          pw.Text(
            'RAZON DE NOTIFICACION: En mi calidad de Secretario Abogado Impulsor de la '
            'Coordinacion Provincial de Gestion de Cartera y Coactiva del IESS, conforme a '
            'las facultades delegadas en los articulos 180 y 182 de la Resolucion C.D. 625, '
            'asi como los articulos 164 y 171 del COA se deja constancia de la presente '
            'notificacion, de conformidad con las constancias anteriormente detalladas.',
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 8),
          _textoCuerpo('Lo certifico.', fontSize: 10),
          pw.SizedBox(height: 18),
          _textoCuerpo('Abg. Jorge Luis Benavides Flores', fontSize: 10),
          _textoCuerpo('SECRETARIO ABOGADO EXTERNO', fontSize: 10),
          _textoCuerpo('INSTITUTO ECUATORIANO DE SEGURIDAD SOCIAL - IESS', fontSize: 10),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _seccionTitulo(String texto, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2, bottom: 6),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 12.5,
          fontWeight: pw.FontWeight.bold,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _checkbox(bool marcado) => marcado ? '[X]' : '[ ]';

  List<pw.Widget> _lineasDiligencia(int total) {
    return List<pw.Widget>.generate(
      total,
      (_) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        height: 1,
        color: PdfColors.black,
      ),
    );
  }

  pw.Widget _fila(String titulo, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: <pw.TextSpan>[
            pw.TextSpan(
              text: '$titulo: ',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: valor,
              style: const pw.TextStyle(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _textoCuerpo(String texto, {double fontSize = 11}) {
    return pw.Text(
      texto,
      style: pw.TextStyle(
        fontSize: fontSize,
        lineSpacing: 2.4,
      ),
    );
  }

  pw.MemoryImage? _safeMemoryImage(Uint8List? bytes, {bool esMapa = false}) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    try {
      final Uint8List normalizada = _normalizarImagenParaPdf(bytes, esMapa: esMapa);
      return pw.MemoryImage(normalizada);
    } catch (_) {
      return null;
    }
  }

  Uint8List _normalizarImagenParaPdf(Uint8List bytes, {required bool esMapa}) {
    final img.Image? original = img.decodeImage(bytes);
    if (original == null) {
      return bytes;
    }

    final int maxAncho = esMapa ? 1200 : 900;
    final int maxAlto = esMapa ? 700 : 900;
    img.Image procesada = original;

    if (procesada.width > maxAncho || procesada.height > maxAlto) {
      final double ratioAncho = maxAncho / procesada.width;
      final double ratioAlto = maxAlto / procesada.height;
      final double ratio = ratioAncho < ratioAlto ? ratioAncho : ratioAlto;
      final int nuevoAncho = (procesada.width * ratio).round().clamp(1, maxAncho);
      final int nuevoAlto = (procesada.height * ratio).round().clamp(1, maxAlto);
      procesada = img.copyResize(
        procesada,
        width: nuevoAncho,
        height: nuevoAlto,
        interpolation: img.Interpolation.average,
      );
    }

    final int calidad = esMapa ? 74 : 60;
    return Uint8List.fromList(img.encodeJpg(procesada, quality: calidad));
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year.toString().padLeft(4, '0')}';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

