import 'package:flutter/material.dart';

class RegistroUbicacionResult {
  const RegistroUbicacionResult({
    required this.nombreUbicacion,
    required this.referenciaUbicacion,
    required this.identificacionTecnica,
    required this.esSegundaNotificacion,
    required this.razonSocial,
    required this.ruc,
    required this.representanteLegal,
    required this.nombreNotificador,
    required this.cedulaNotificador,
  });

  final String nombreUbicacion;
  final String referenciaUbicacion;
  final String identificacionTecnica;
  final bool esSegundaNotificacion;
  final String razonSocial;
  final String ruc;
  final String representanteLegal;
  final String nombreNotificador;
  final String cedulaNotificador;
}

Future<RegistroUbicacionResult?> mostrarRegistroUbicacionModal({
  required BuildContext context,
  required String nombreSugerido,
  String? direccionSugerida,
}) async {
  return showDialog<RegistroUbicacionResult>(
    context: context,
    builder: (BuildContext dialogContext) => _RegistroUbicacionDialog(
      nombreSugerido: nombreSugerido,
      direccionSugerida: direccionSugerida,
    ),
  );
}

class _RegistroUbicacionDialog extends StatefulWidget {
  const _RegistroUbicacionDialog({
    required this.nombreSugerido,
    this.direccionSugerida,
  });

  final String nombreSugerido;
  final String? direccionSugerida;

  @override
  State<_RegistroUbicacionDialog> createState() => _RegistroUbicacionDialogState();
}

class _RegistroUbicacionDialogState extends State<_RegistroUbicacionDialog> {
  late final TextEditingController _nombreCtrl = TextEditingController(
    text: widget.nombreSugerido.trim().isEmpty
        ? 'Ubicacion legal'
        : widget.nombreSugerido.trim(),
  );
  String _identificacion = 'RPV';
  bool _esSegundaNotificacion = false;
  final TextEditingController _razonSocialCtrl = TextEditingController();
  final TextEditingController _rucCtrl = TextEditingController();
  final TextEditingController _representanteCtrl = TextEditingController();
  final TextEditingController _referenciaCtrl = TextEditingController();
  final TextEditingController _nombreNotificadorCtrl = TextEditingController();
  final TextEditingController _cedulaNotificadorCtrl = TextEditingController();

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _razonSocialCtrl.dispose();
    _rucCtrl.dispose();
    _representanteCtrl.dispose();
    _referenciaCtrl.dispose();
    _nombreNotificadorCtrl.dispose();
    _cedulaNotificadorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      scrollable: true,
      title: const Text('Nueva ubicacion legal'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de la ubicacion',
                hintText: 'Ej. Calle 10 # 25-30',
              ),
            ),
            const SizedBox(height: 10),
            if ((widget.direccionSugerida ?? '').trim().isNotEmpty)
              Text(
                'Direccion detectada: ${widget.direccionSugerida!.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _referenciaCtrl,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Referencia de ubicacion',
                hintText: 'Ej. junto al parque, frente al banco, color azul',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Identificacion tecnica',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('RPV'),
              value: 'RPV',
              groupValue: _identificacion,
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _identificacion = value;
                });
              },
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('OPI'),
              value: 'OPI',
              groupValue: _identificacion,
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _identificacion = value;
                });
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Tipo de notificacion',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Primera notificacion'),
              value: false,
              groupValue: _esSegundaNotificacion,
              onChanged: (bool? value) {
                if (value == null) return;
                setState(() => _esSegundaNotificacion = value);
              },
            ),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Segunda notificacion'),
              value: true,
              groupValue: _esSegundaNotificacion,
              onChanged: (bool? value) {
                if (value == null) return;
                setState(() => _esSegundaNotificacion = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _razonSocialCtrl,
              decoration: const InputDecoration(
                labelText: 'Razon social',
                hintText: 'Ej. Bufete Juridico ABC',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rucCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'RUC',
                hintText: 'Ej. 1790012345001',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _representanteCtrl,
              decoration: const InputDecoration(
                labelText: 'Representante legal',
                hintText: 'Nombre completo',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nombreNotificadorCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del notificador',
                hintText: 'Nombre completo',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cedulaNotificadorCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cedula del notificador',
                hintText: 'Ej. 0102030405',
              ),
            ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final String nombre = _nombreCtrl.text.trim();
            if (nombre.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              RegistroUbicacionResult(
                nombreUbicacion: nombre,
                referenciaUbicacion: _referenciaCtrl.text.trim(),
                identificacionTecnica: _identificacion,
                esSegundaNotificacion: _esSegundaNotificacion,
                razonSocial: _razonSocialCtrl.text.trim(),
                ruc: _rucCtrl.text.trim(),
                representanteLegal: _representanteCtrl.text.trim(),
                nombreNotificador: _nombreNotificadorCtrl.text.trim(),
                cedulaNotificador: _cedulaNotificadorCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Guardar ubicacion'),
        ),
      ],
    );
  }
}

