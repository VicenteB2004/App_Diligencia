import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> mostrarReporteBottomSheet({
  required BuildContext context,
  required String reporte,
  required VoidCallback onReporteCopiado,
}) async {
  final bool esEscritorio = MediaQuery.of(context).size.width >= 720;
  if (esEscritorio) {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
            child: _ReporteContent(
              reporte: reporte,
              onCerrar: () => Navigator.of(dialogContext).pop(),
              onCopiar: () async {
                await Clipboard.setData(ClipboardData(text: reporte));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                onReporteCopiado();
              },
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
    builder: (BuildContext bottomSheetContext) {
      return SafeArea(
        child: _ReporteContent(
          reporte: reporte,
          onCerrar: () => Navigator.of(bottomSheetContext).pop(),
          onCopiar: () async {
            await Clipboard.setData(ClipboardData(text: reporte));
            if (bottomSheetContext.mounted) {
              Navigator.of(bottomSheetContext).pop();
            }
            onReporteCopiado();
          },
        ),
      );
    },
  );
}

class _ReporteContent extends StatelessWidget {
  const _ReporteContent({
    required this.reporte,
    required this.onCerrar,
    required this.onCopiar,
  });

  final String reporte;
  final VoidCallback onCerrar;
  final Future<void> Function() onCopiar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.description_outlined),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reporte de llegadas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(reporte),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: () {
                  unawaited(onCopiar());
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar reporte'),
              ),
              TextButton(
                onPressed: onCerrar,
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

