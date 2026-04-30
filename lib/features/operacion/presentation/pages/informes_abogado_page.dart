import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notificador/data/models/notification_report.dart';
import 'package:notificador/data/services/firestore_service.dart';
import 'package:notificador/data/utils/pdf_bytes_parser.dart';
import 'package:printing/printing.dart';

class InformesAbogadoPage extends StatelessWidget {
  const InformesAbogadoPage({
    super.key,
    this.firestoreService,
  });

  final FirestoreService? firestoreService;

  bool get _pdfHabilitadoEnEstaPlataforma =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final FirestoreService service = firestoreService ?? FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes del notificador'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: StreamBuilder<List<NotificationReport>>(
            stream: service.streamNotificationReportsByCurrentUserGroup(),
            builder: (BuildContext context, AsyncSnapshot<List<NotificationReport>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No se pudieron cargar los informes.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final List<NotificationReport> reportes = snapshot.data ?? <NotificationReport>[];
              if (reportes.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Todavia no hay informes enviados por notificadores en tu grupo.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: reportes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final NotificationReport reporte = reportes[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: CircleAvatar(
                        child: Text(
                          reporte.identificacionTecnica.isEmpty
                              ? 'U-${reporte.ubicacionId}'
                              : reporte.identificacionTecnica,
                        ),
                      ),
                      title: Text(
                        reporte.notificadorNombre.isEmpty
                            ? reporte.notificadorEmail
                            : reporte.notificadorNombre,
                      ),
                      subtitle: Text(
                        '${reporte.nombreUbicacion.isEmpty ? 'U-${reporte.ubicacionId}' : reporte.nombreUbicacion}\n'
                        '${_capitalize(reporte.tipoNotificacion)} - ${_capitalize(reporte.personaNotificada)}\n'
                        '${_formatDateTime(reporte.fechaHora)}',
                      ),
                      isThreeLine: true,
                      trailing: _pdfHabilitadoEnEstaPlataforma
                          ? const Icon(Icons.chevron_right)
                          : const Icon(Icons.description_outlined),
                      onTap: () => _mostrarDetalle(context, reporte, service),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarDetalle(
    BuildContext context,
    NotificationReport reporte,
    FirestoreService service,
  ) async {
    final bool esEscritorio = MediaQuery.of(context).size.width >= 720;
    final bool habilitarPdf = _pdfHabilitadoEnEstaPlataforma;
    if (esEscritorio) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
              child: _DetalleInformeContent(
                reporte: reporte,
                onDescargarPdf: habilitarPdf
                    ? () => _descargarPdf(context, reporte, service)
                    : null,
                onPrevisualizarPdf: habilitarPdf
                    ? () => _previsualizarPdf(context, reporte, service)
                    : null,
                onEliminar: () async {
                  final bool confirmar = await _confirmarEliminacion(dialogContext);
                  if (!confirmar) {
                    return;
                  }

                  try {
                    await service.deleteNotificationReport(reporte.id);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    _mostrarSnack(context, 'Informe eliminado de la app y de la base de datos.');
                  } on FirestoreServiceException catch (e) {
                    _mostrarSnack(context, e.message);
                  } catch (e) {
                    _mostrarSnack(context, 'No se pudo eliminar el informe: $e');
                  }
                },
                onCerrar: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext bottomContext) {
        return SafeArea(
          child: _DetalleInformeContent(
            reporte: reporte,
            onDescargarPdf: habilitarPdf
                ? () => _descargarPdf(context, reporte, service)
                : null,
            onPrevisualizarPdf: habilitarPdf
                ? () => _previsualizarPdf(context, reporte, service)
                : null,
            onEliminar: () async {
              final bool confirmar = await _confirmarEliminacion(bottomContext);
              if (!confirmar) {
                return;
              }

              try {
                await service.deleteNotificationReport(reporte.id);
                if (bottomContext.mounted) {
                  Navigator.of(bottomContext).pop();
                }
                _mostrarSnack(context, 'Informe eliminado de la app y de la base de datos.');
              } on FirestoreServiceException catch (e) {
                _mostrarSnack(context, e.message);
              } catch (e) {
                _mostrarSnack(context, 'No se pudo eliminar el informe: $e');
              }
            },
            onCerrar: () => Navigator.of(bottomContext).pop(),
          ),
        );
      },
    );
  }

  Future<void> _descargarPdf(
    BuildContext context,
    NotificationReport reporte,
    FirestoreService service,
  ) async {
    if (!_pdfHabilitadoEnEstaPlataforma) {
      return;
    }

    debugPrint('[PDF][${reporte.id}] Click en Descargar PDF');
    final Uint8List? bytes = await _obtenerPdfBytes(reporte, service);
    if (bytes == null) {
      debugPrint('[PDF][${reporte.id}] Sin bytes PDF validos. url=${reporte.pdfDownloadUrl ?? ''} path=${reporte.pdfStoragePath ?? ''}');
      _mostrarSnack(
        context,
        'No se encontro un PDF valido para este informe.',
      );
      return;
    }
    debugPrint('[PDF][${reporte.id}] PDF listo para descarga (${bytes.lengthInBytes} bytes).');

    final String prefijo = reporte.identificacionTecnica.trim().isEmpty
        ? 'u${reporte.ubicacionId}'
        : reporte.identificacionTecnica.toLowerCase();
    final String fileName = 'informe_${prefijo}_${_fileDate(reporte.fechaHora)}.pdf';
    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      debugPrint('[PDF][${reporte.id}] Error al descargar/abrir: $e');
      _mostrarSnack(context, 'No se pudo descargar el PDF: $e');
    }
  }

  Future<void> _previsualizarPdf(
    BuildContext context,
    NotificationReport reporte,
    FirestoreService service,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final Uint8List? bytes = await _obtenerPdfBytes(reporte, service);
    if (bytes == null) {
      _mostrarSnack(
        context,
        'Este informe no tiene PDF adjunto disponible.',
      );
      return;
    }

    final String prefijo = reporte.identificacionTecnica.trim().isEmpty
        ? 'u${reporte.ubicacionId}'
        : reporte.identificacionTecnica.toLowerCase();
    final String fileName = 'informe_${prefijo}_${_fileDate(reporte.fechaHora)}.pdf';

    try {
      await Printing.layoutPdf(
        name: fileName,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      _mostrarSnack(context, 'No se pudo previsualizar el PDF: $e');
    }
  }

  Future<Uint8List?> _obtenerPdfBytes(
    NotificationReport reporte,
    FirestoreService service,
  ) async {
    final Uint8List? cached = reporte.pdfBytes;
    final bool cachedEsPdf =
        cached != null && cached.isNotEmpty && PdfBytesParser.looksLikePdf(cached);

    final Uint8List? bytes = cachedEsPdf
        ? cached
        : await service.getNotificationReportPdfBytes(
            reporte.id,
            knownPdfDownloadUrl: reporte.pdfDownloadUrl,
            knownPdfStoragePath: reporte.pdfStoragePath,
          );
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return bytes;
  }

  void _mostrarSnack(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<bool> _confirmarEliminacion(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar informe'),
          content: const Text(
            'Esta accion elimina el PDF y el informe de la base de datos. No se puede deshacer.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

}

Widget _linea(String titulo, String valor) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: <InlineSpan>[
          TextSpan(
            text: '$titulo: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: valor.isEmpty ? '-' : valor),
        ],
      ),
    ),
  );
}

String _formatDateTime(DateTime dateTime) {
  return '${dateTime.day.toString().padLeft(2, '0')}/'
      '${dateTime.month.toString().padLeft(2, '0')}/'
      '${dateTime.year.toString().padLeft(4, '0')} '
      '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

String _capitalize(String text) {
  if (text.isEmpty) {
    return '-';
  }
  return text[0].toUpperCase() + text.substring(1).replaceAll('_', ' ');
}

String _fileDate(DateTime dateTime) {
  return '${dateTime.year.toString().padLeft(4, '0')}'
      '${dateTime.month.toString().padLeft(2, '0')}'
      '${dateTime.day.toString().padLeft(2, '0')}_'
      '${dateTime.hour.toString().padLeft(2, '0')}'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

class _DetalleInformeContent extends StatelessWidget {
  const _DetalleInformeContent({
    required this.reporte,
    required this.onCerrar,
    required this.onEliminar,
    this.onDescargarPdf,
    this.onPrevisualizarPdf,
  });

  final NotificationReport reporte;
  final VoidCallback onCerrar;
  final Future<void> Function() onEliminar;
  final VoidCallback? onDescargarPdf;
  final VoidCallback? onPrevisualizarPdf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              reporte.nombreUbicacion.isEmpty
                  ? 'Informe U-${reporte.ubicacionId}'
                  : 'Informe ${reporte.nombreUbicacion}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _linea('Notificador', reporte.notificadorNombre),
            _linea('Email', reporte.notificadorEmail),
            _linea('Tipo', _capitalize(reporte.tipoNotificacion)),
            _linea('Persona', _capitalize(reporte.personaNotificada)),
            _linea('Identificacion tecnica', reporte.identificacionTecnica),
            _linea('Direccion', reporte.direccion),
            _linea('Coordenadas', '${reporte.lat.toStringAsFixed(6)}, ${reporte.lng.toStringAsFixed(6)}'),
            _linea('Fecha', _formatDateTime(reporte.fechaHora)),
            if (reporte.descripcionDiligencia.isNotEmpty) _linea('Descripcion de la diligencia', reporte.descripcionDiligencia),
            if ((reporte.nombreFamiliarTrabajador ?? '').trim().isNotEmpty) ...<Widget>[
              _linea('Nombre Familiar/Trabajador', reporte.nombreFamiliarTrabajador ?? ''),
              _linea('Cedula Familiar/Trabajador', reporte.cedulaFamiliarTrabajador ?? ''),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (onPrevisualizarPdf != null)
                  OutlinedButton.icon(
                    onPressed: onPrevisualizarPdf,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Previsualizar PDF'),
                  ),
                if (onDescargarPdf != null)
                  OutlinedButton.icon(
                    onPressed: onDescargarPdf,
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar PDF'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    unawaited(onEliminar());
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar informe'),
                ),
                TextButton(
                  onPressed: onCerrar,
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

