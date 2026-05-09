import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:notificador/features/operacion/domain/entities/encuesta_llegada.dart';

Future<EncuestaLlegada?> mostrarEncuestaLlegadaModal({
  required BuildContext context,
  required int paradaId,
  required double distanciaMetros,
  String? referenciaUbicacion,
}) {
  final bool esEscritorio = MediaQuery.of(context).size.width >= 720;
  if (esEscritorio) {
    return showDialog<EncuestaLlegada>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) {
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
              child: _EncuestaLlegadaModal(
                paradaId: paradaId,
                distanciaMetros: distanciaMetros,
                referenciaUbicacion: referenciaUbicacion,
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<EncuestaLlegada>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _EncuestaLlegadaModal(
        paradaId: paradaId,
        distanciaMetros: distanciaMetros,
        referenciaUbicacion: referenciaUbicacion,
      ),
    ),
  );
}

class _EncuestaLlegadaModal extends StatefulWidget {
  const _EncuestaLlegadaModal({
    required this.paradaId,
    required this.distanciaMetros,
    this.referenciaUbicacion,
  });

  final int paradaId;
  final double distanciaMetros;
  final String? referenciaUbicacion;

  @override
  State<_EncuestaLlegadaModal> createState() => _EncuestaLlegadaModalState();
}

class _EncuestaLlegadaModalState extends State<_EncuestaLlegadaModal> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _nombreFamCtrl = TextEditingController();
  final TextEditingController _cedulaFamCtrl = TextEditingController();

  TipoNotificacion _tipo = TipoNotificacion.personal;
  PersonaNotificada _persona = PersonaNotificada.personaNatural;
  Uint8List? _fotoRegistro1Bytes;
  Uint8List? _fotoRegistro2Bytes;
  bool _guardando = false;

  bool get _esEscritorio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void dispose() {
    _descCtrl.dispose();
    _nombreFamCtrl.dispose();
    _cedulaFamCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFotoRegistro({required bool esFoto2}) async {
    try {
      final XFile? foto = _esEscritorio
          ? await openFile(
              acceptedTypeGroups: <XTypeGroup>[
                const XTypeGroup(
                  label: 'Imagenes',
                  extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
                ),
              ],
            )
          : await _picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 45,
              maxWidth: 960,
            );
      if (foto == null || !mounted) {
        return;
      }
      final Uint8List bytes = await foto.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Archivo de imagen vacio.');
      }
      setState(() {
        if (esFoto2) {
          _fotoRegistro2Bytes = bytes;
        } else {
          _fotoRegistro1Bytes = bytes;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _esEscritorio
                ? 'No se pudo seleccionar la imagen. Intentalo nuevamente.'
                : 'No se pudo abrir la camara. Verifica permisos.',
          ),
        ),
      );
    }
  }

  Future<void> _enviar() async {
    final Uint8List? fotoRegistro1 = _fotoRegistro1Bytes;
    final Uint8List? fotoRegistro2 = _fotoRegistro2Bytes;
    if (fotoRegistro1 == null || fotoRegistro2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes tomar las 2 fotos de registro para generar el informe.')),
      );
      return;
    }

    // Validar campos de familiar/trabajador si aplica
    if (_persona == PersonaNotificada.familiar || _persona == PersonaNotificada.trabajador) {
      if (_nombreFamCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes ingresar el nombre del familiar/trabajador.')),
        );
        return;
      }
      if (_cedulaFamCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes ingresar la cédula del familiar/trabajador.')),
        );
        return;
      }
    }

    setState(() {
      _guardando = true;
    });

    try {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        EncuestaLlegada(
          tipoNotificacion: _tipo,
          personaNotificada: _persona,
          descripcionDiligencia: _descCtrl.text.trim(),
          fotoRegistroBytes: fotoRegistro1,
          fotoRegistroSecundariaBytes: fotoRegistro2,
          nombreFamiliarTrabajador: (_persona == PersonaNotificada.familiar || _persona == PersonaNotificada.trabajador)
              ? _nombreFamCtrl.text.trim()
              : null,
          cedulaFamiliarTrabajador: (_persona == PersonaNotificada.familiar || _persona == PersonaNotificada.trabajador)
              ? _cedulaFamCtrl.text.trim()
              : null,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets keyboardPadding = EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    );

    return Padding(
      padding: keyboardPadding,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
           children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.assignment_turned_in, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Llegada en U-${widget.paradaId}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text('${widget.distanciaMetros.toStringAsFixed(1)} m'),
              ],
            ),
            if ((widget.referenciaUbicacion ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Referencia',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.referenciaUbicacion!.trim(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<TipoNotificacion>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Tipo de notificacion',
              ),
              items: TipoNotificacion.values
                  .map(
                    (TipoNotificacion t) => DropdownMenuItem<TipoNotificacion>(
                      value: t,
                      child: Text(t.label),
                    ),
                  )
                  .toList(),
              onChanged: _guardando
                  ? null
                  : (TipoNotificacion? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _tipo = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PersonaNotificada>(
              initialValue: _persona,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Persona notificada',
              ),
              items: PersonaNotificada.values
                  .map(
                    (PersonaNotificada p) => DropdownMenuItem<PersonaNotificada>(
                      value: p,
                      child: Text(p.label),
                    ),
                  )
                  .toList(),
              onChanged: _guardando
                  ? null
                  : (PersonaNotificada? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _persona = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              minLines: 2,
              maxLines: 4,
              enabled: !_guardando,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Descripcion de la diligencia',
                hintText: 'Ej: Se notifico en puerta principal...',
              ),
            ),
            // Campos condicionales para familiar/trabajador
            if (_persona == PersonaNotificada.familiar || _persona == PersonaNotificada.trabajador) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _nombreFamCtrl,
                enabled: !_guardando,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Nombre del Familiar/Trabajador',
                  hintText: 'Ej: Juan Pérez',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cedulaFamCtrl,
                enabled: !_guardando,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Cédula del Familiar/Trabajador',
                  hintText: 'Ej: 1234567890',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _guardando ? null : () => _tomarFotoRegistro(esFoto2: false),
                    icon: const Icon(Icons.photo_camera),
                    label: Text(
                      _fotoRegistro1Bytes == null
                          ? (_esEscritorio ? 'Seleccionar foto 1 de registro' : 'Tomar foto 1 de registro')
                          : 'Repetir foto 1',
                    ),
                  ),
                ),
              ],
            ),
            if (_fotoRegistro1Bytes != null) ...<Widget>[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_fotoRegistro1Bytes!, height: 160, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _guardando ? null : () => _tomarFotoRegistro(esFoto2: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      _fotoRegistro2Bytes == null
                          ? (_esEscritorio ? 'Seleccionar foto 2 de registro' : 'Tomar foto 2 de registro')
                          : 'Repetir foto 2',
                    ),
                  ),
                ),
              ],
            ),
            if (_fotoRegistro2Bytes != null) ...<Widget>[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_fotoRegistro2Bytes!, height: 160, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _guardando ? null : _enviar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(_guardando ? 'Generando informe...' : 'Enviar informe'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



