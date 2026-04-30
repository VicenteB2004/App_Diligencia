import 'package:flutter/material.dart';
import 'package:notificador/features/operacion/domain/entities/parada.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';

class PanelControlWidget extends StatelessWidget {
  const PanelControlWidget({
    super.key,
    required this.rolActivo,
    required this.total,
    required this.pendientes,
    required this.totalReportes,
    required this.rutaIds,
    required this.paradas,
    required this.modoMarcadoEnMapa,
    required this.distanciaDesdeMiPosicion,
    required this.onModoMarcadoChanged,
    required this.onLimpiar,
    required this.onOptimizarRuta,
    required this.onCentrar,
    required this.onVerReporte,
    required this.onTapParada,
    this.scrollController,
    this.esPanelFijo = false,
    this.mostrarEncabezado = true,
    this.mostrarHandleArrastre = true,
  });

  final RolApp rolActivo;
  final int total;
  final int pendientes;
  final int totalReportes;
  final List<int> rutaIds;
  final Map<int, Parada> paradas;
  final bool modoMarcadoEnMapa;
  final double? Function(int paradaId) distanciaDesdeMiPosicion;

  final ValueChanged<bool> onModoMarcadoChanged;
  final VoidCallback onLimpiar;
  final VoidCallback onOptimizarRuta;
  final VoidCallback onCentrar;
  final VoidCallback onVerReporte;
  final ValueChanged<int> onTapParada;
  final ScrollController? scrollController;
  final bool esPanelFijo;
  final bool mostrarEncabezado;
  final bool mostrarHandleArrastre;

  @override
  Widget build(BuildContext context) {
    final bool esAbogado = rolActivo == RolApp.abogado;
    final int completadas = total - pendientes;
    final double progreso = total == 0 ? 0 : completadas / total;
    final Color colorRol = esAbogado ? Colors.indigo : Colors.teal;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: esPanelFijo
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: esPanelFijo
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2)),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (mostrarHandleArrastre) ...<Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (mostrarEncabezado) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(esAbogado ? Icons.gavel : Icons.route, color: colorRol),
                  const SizedBox(width: 8),
                  Text(
                    esAbogado ? 'Panel abogado' : 'Panel notificador',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Text(
                esAbogado
                    ? 'Aqui creas y administras ubicaciones para tu grupo.'
                    : 'Aqui gestionas tu ruta y visitas pendientes.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
            ],
            const _SectionTitle(icon: Icons.insights, text: 'Estado'),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _statCard(
                    icon: Icons.place,
                    titulo: 'Total',
                    valor: total.toString(),
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    icon: Icons.pending_actions,
                    titulo: 'Pendientes',
                    valor: pendientes.toString(),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    icon: Icons.fact_check,
                    titulo: 'Reportes',
                    valor: totalReportes.toString(),
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(colorRol),
              ),
            ),
            const SizedBox(height: 10),
            const _SectionTitle(icon: Icons.lightbulb_outline, text: 'Que hacer ahora'),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorRol.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                esAbogado
                    ? (modoMarcadoEnMapa
                        ? '1) Toca el mapa para crear ubicaciones.\n2) Usa "Limpiar" si necesitas empezar de nuevo.'
                                : '1) Busca un destino arriba.\n2) Veras el punto exacto y podras decidir si marcarlo.')
                    : '1) Pulsa "Optimizar ruta".\n2) Toca una parada para abrir la navegacion en Google Maps.',
              ),
            ),
            const SizedBox(height: 10),
            const _SectionTitle(icon: Icons.touch_app, text: 'Acciones'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (esAbogado)
                  FilterChip(
                    avatar: Icon(
                      modoMarcadoEnMapa ? Icons.gps_fixed : Icons.gps_not_fixed,
                      size: 18,
                    ),
                    label: Text(modoMarcadoEnMapa ? 'Marcar en mapa: ON' : 'Marcar en mapa: OFF'),
                    selected: modoMarcadoEnMapa,
                    onSelected: onModoMarcadoChanged,
                    selectedColor: Colors.indigo.withValues(alpha: 0.18),
                  ),
                if (esAbogado)
                  FilledButton.tonalIcon(
                    onPressed: onLimpiar,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Limpiar ubicaciones'),
                  ),
                if (!esAbogado)
                  FilledButton.icon(
                    onPressed: onOptimizarRuta,
                    icon: const Icon(Icons.route),
                    label: const Text('Optimizar ruta'),
                  ),
                if (!esAbogado)
                  OutlinedButton.icon(
                    onPressed: onCentrar,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Centrar en mi ubicacion'),
                  ),
                if (!esAbogado)
                  OutlinedButton.icon(
                    onPressed: onVerReporte,
                    icon: const Icon(Icons.description),
                    label: const Text('Ver reporte'),
                  ),
              ],
            ),
            if (!esAbogado) ...<Widget>[
              const SizedBox(height: 10),
              const _SectionTitle(icon: Icons.format_list_numbered, text: 'Paradas en orden'),
              const SizedBox(height: 6),
              if (rutaIds.isEmpty)
                const Row(
                  children: <Widget>[
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 6),
                    Expanded(child: Text('Aun no hay ruta. Pulsa "Optimizar ruta" para generarla.')),
                  ],
                )
              else
                Column(
                  children: rutaIds.asMap().entries.map((MapEntry<int, int> item) {
                    final Parada? parada = paradas[item.value];
                    if (parada == null) {
                      return const SizedBox.shrink();
                    }
                    final double? distancia = distanciaDesdeMiPosicion(parada.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(radius: 13, child: Text('${item.key + 1}')),
                        title: Text('U-${parada.id}'),
                        subtitle: Text(
                          distancia == null
                              ? 'Distancia no disponible'
                              : '${distancia.toStringAsFixed(0)} m desde tu posicion',
                        ),
                        trailing: const Icon(Icons.navigation),
                        onTap: () => onTapParada(parada.id),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: Colors.black87),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
