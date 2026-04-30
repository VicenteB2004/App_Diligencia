import 'package:flutter/material.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';

Future<void> mostrarRutaCompletadaModal({
  required BuildContext context,
  required RolApp rolActivo,
  required int totalParadas,
  required int paradasCompletadas,
  required int totalReportes,
  Future<void> Function()? onVerReportes,
}) {
  final bool esEscritorio = MediaQuery.of(context).size.width >= 720;
  final Widget content = _RutaCompletadaContent(
    rolActivo: rolActivo,
    totalParadas: totalParadas,
    paradasCompletadas: paradasCompletadas,
    totalReportes: totalReportes,
    onVerReportes: onVerReportes,
  );

  if (esEscritorio) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: content,
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext bottomContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(bottomContext).viewInsets.bottom),
        child: content,
      );
    },
  );
}

class _RutaCompletadaContent extends StatelessWidget {
  const _RutaCompletadaContent({
    required this.rolActivo,
    required this.totalParadas,
    required this.paradasCompletadas,
    required this.totalReportes,
    required this.onVerReportes,
  });

  final RolApp rolActivo;
  final int totalParadas;
  final int paradasCompletadas;
  final int totalReportes;
  final Future<void> Function()? onVerReportes;

  @override
  Widget build(BuildContext context) {
    final bool esAbogado = rolActivo == RolApp.abogado;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String titulo = esAbogado
        ? 'Ruta terminada y lista para revisión'
        : 'Rutas completadas correctamente';
    final String descripcion = esAbogado
        ? 'Todas las ubicaciones del grupo quedaron marcadas como completadas. Ya puedes revisar la bandeja de reportes y validar que toda la gestión quedó registrada.'
        : 'Has completado todas las ubicaciones asignadas. La información quedó sincronizada y la ruta ya puede considerarse finalizada.';
    final String accionPrincipal = esAbogado ? 'Ir a reportes' : 'Entendido';
    final IconData icono = esAbogado ? Icons.fact_check_rounded : Icons.verified_rounded;
    final Color colorPrincipal = esAbogado ? colorScheme.primary : colorScheme.tertiary;

    final List<Widget> estadisticas = <Widget>[
      _DatoRuta(
        icono: Icons.location_on_outlined,
        etiqueta: 'Ubicaciones totales',
        valor: totalParadas.toString(),
      ),
      _DatoRuta(
        icono: Icons.check_circle_outline,
        etiqueta: 'Completadas',
        valor: paradasCompletadas.toString(),
      ),
      _DatoRuta(
        icono: Icons.pending_actions_outlined,
        etiqueta: 'Pendientes',
        valor: (totalParadas - paradasCompletadas).clamp(0, totalParadas).toString(),
      ),
      _DatoRuta(
        icono: Icons.assignment_outlined,
        etiqueta: 'Reportes visibles',
        valor: totalReportes.toString(),
      ),
    ];

    final Widget body = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  label: esAbogado ? 'Ruta finalizada' : 'Ruta completada',
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colorPrincipal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icono, color: colorPrincipal, size: 30),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        descripcion,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.black87,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.done_all_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      esAbogado
                          ? 'Se completaron todas las ubicaciones y los reportes ya quedaron sincronizados. La bandeja está lista para revision.'
                          : 'La ruta quedo cerrada correctamente y toda la informacion fue enviada. Puedes continuar con normalidad.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: estadisticas,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    esAbogado ? 'Siguiente paso recomendado' : 'Estado final del proceso',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    esAbogado
                        ? 'Revisa los informes recibidos, valida las observaciones y confirma que la diligencia quedó lista para seguimiento.'
                        : 'Puedes continuar usando la app con normalidad; la ruta quedó cerrada y el historial permanece guardado para consulta posterior.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: <Widget>[
                if (esAbogado && onVerReportes != null)
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onVerReportes?.call();
                    },
                    icon: const Icon(Icons.assignment_turned_in_outlined),
                    label: Text(accionPrincipal),
                  )
                else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(accionPrincipal),
                  ),
                if (esAbogado && onVerReportes != null)
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (MediaQuery.of(context).size.width >= 720) {
      return body;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: body,
    );
  }
}

class _DatoRuta extends StatelessWidget {
  const _DatoRuta({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icono, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    etiqueta,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


