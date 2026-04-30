import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/features/operacion/domain/entities/encuesta_llegada.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';
import 'package:notificador/features/operacion/domain/entities/sugerencia_destino.dart';
import 'package:notificador/features/operacion/presentation/controllers/operacion_controller.dart';
import 'package:notificador/features/operacion/presentation/pages/informes_abogado_page.dart';
import 'package:notificador/features/operacion/presentation/widgets/encuesta_llegada_modal.dart';
import 'package:notificador/features/operacion/presentation/widgets/panel_control_widget.dart';
import 'package:notificador/features/operacion/presentation/widgets/ruta_completada_modal.dart';
import 'package:notificador/features/operacion/presentation/widgets/registro_ubicacion_modal.dart';
import 'package:notificador/features/operacion/presentation/widgets/reporte_bottom_sheet.dart';
import 'package:notificador/features/settings/presentation/pages/ajustes_page.dart';

class OperacionMapaPage extends StatefulWidget {
  const OperacionMapaPage({
    super.key,
    required this.title,
    required this.usuario,
    required this.onLogout,
    required this.onUserUpdated,
  });

  final String title;
  final Usuario usuario;
  final VoidCallback onLogout;
  final ValueChanged<Usuario> onUserUpdated;

  @override
  State<OperacionMapaPage> createState() => _OperacionMapaPageState();
}

class _OperacionMapaPageState extends State<OperacionMapaPage> {
  static const double _desktopBreakpoint = 1100;

  late final OperacionController _controller;
  final TextEditingController _destinoCtrl = TextEditingController();
  final fm.MapController _flutterMapController = fm.MapController();
  bool _mostrandoModalRutaCompletada = false;
  bool _modalRutaCompletadaCerradoPorNotificador = false;
  Timer? _temporizadorModalRutaCompletada;
  String? _errorInicializacion;

  @override
  void initState() {
    super.initState();
    _controller = OperacionController(usuarioActual: widget.usuario);
    _controller.setMessageHandler(_mostrarMensaje);
    _controller.setFlutterMapController(_flutterMapController);
    _destinoCtrl.addListener(_rebuildOnDestinoChange);
    _controller.setEncuestaLlegadaHandler(({
      required int paradaId,
      required double distanciaMetros,
    }) {
      if (!mounted) {
        return Future<EncuestaLlegada?>.value(null);
      }
      return mostrarEncuestaLlegadaModal(
        context: context,
        paradaId: paradaId,
        distanciaMetros: distanciaMetros,
      );
    });
    _controller.setRegistroUbicacionHandler(({
      required String nombreSugerido,
      required String? direccionSugerida,
    }) async {
      if (!mounted) {
        return null;
      }

      final RegistroUbicacionResult? result = await mostrarRegistroUbicacionModal(
        context: context,
        nombreSugerido: nombreSugerido,
        direccionSugerida: direccionSugerida,
      );
      if (result == null) {
        return null;
      }
      return RegistroUbicacionData(
        nombreUbicacion: result.nombreUbicacion,
        identificacionTecnica: result.identificacionTecnica,
        esSegundaNotificacion: result.esSegundaNotificacion,
        razonSocial: result.razonSocial,
        ruc: result.ruc,
        representanteLegal: result.representanteLegal,
        nombreNotificador: result.nombreNotificador,
        cedulaNotificador: result.cedulaNotificador,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_inicializarControllerSeguro());
    });
  }

  Future<void> _inicializarControllerSeguro() async {
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorInicializacion = null;
      });
      await _controller.inicializar();
      if (!mounted) {
        return;
      }
      setState(() {
        _errorInicializacion = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorInicializacion = e.toString();
      });
      _mostrarMensaje('No se pudo iniciar el mapa: $e');
    }
  }

  @override
  void dispose() {
    _temporizadorModalRutaCompletada?.cancel();
    _controller.setMessageHandler(null);
    _controller.setEncuestaLlegadaHandler(null);
    _controller.setRegistroUbicacionHandler(null);
    _controller.dispose();
    _destinoCtrl.removeListener(_rebuildOnDestinoChange);
    _destinoCtrl.dispose();
    super.dispose();
  }

  void _rebuildOnDestinoChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _buscarDestino() {
    FocusScope.of(context).unfocus();
    _controller.limpiarSugerenciasDestino(notify: false);
    unawaited(_controller.buscarDestinoYEnfocar(_destinoCtrl.text));
  }

  void _seleccionarSugerencia(SugerenciaDestino sugerencia) {
    _destinoCtrl.value = TextEditingValue(
      text: sugerencia.descripcion,
      selection: TextSelection.collapsed(offset: sugerencia.descripcion.length),
    );
    FocusScope.of(context).unfocus();
    _controller.limpiarSugerenciasDestino(notify: false);
    unawaited(_controller.seleccionarSugerenciaYBuscar(sugerencia));
  }

  void _mostrarMensaje(String texto) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  bool _debeMostrarModalRutaCompletada() {
    final int totalParadas = _controller.totalParadas;
    if (totalParadas <= 0) {
      return false;
    }

    if (_controller.esAbogado) {
      return _controller.rutaCompletadaPorReportes;
    }

    if (_modalRutaCompletadaCerradoPorNotificador) {
      return false;
    }

    return _controller.paradasPendientes == 0;
  }

  Future<void> _mostrarReporte() async {
    final String reporte = _controller.textoReporte();
    if (!mounted) {
      return;
    }

    await mostrarReporteBottomSheet(
      context: context,
      reporte: reporte,
      onReporteCopiado: () => _mostrarMensaje('Reporte copiado al portapapeles.'),
    );
  }

  Future<void> _abrirAjustes() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => AjustesPage(
          usuario: widget.usuario,
          onUsuarioActualizado: widget.onUserUpdated,
        ),
      ),
    );
  }

  Future<void> _abrirInformesAbogado() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const InformesAbogadoPage(),
      ),
    );
  }

  void _evaluarCierreDeRutaYMostrarModal() {
    if (_mostrandoModalRutaCompletada) {
      return;
    }

    if (!_controller.esAbogado) {
      final bool rutaCompleta =
          _controller.totalParadas > 0 && _controller.paradasPendientes == 0;
      if (!rutaCompleta) {
        _modalRutaCompletadaCerradoPorNotificador = false;
      }
    }

    if (!_debeMostrarModalRutaCompletada()) {
      _temporizadorModalRutaCompletada?.cancel();
      _temporizadorModalRutaCompletada = null;
      return;
    }

    _temporizadorModalRutaCompletada?.cancel();
    _temporizadorModalRutaCompletada = Timer(const Duration(milliseconds: 900), () async {
      _temporizadorModalRutaCompletada = null;
      if (!mounted) {
        return;
      }

      if (_mostrandoModalRutaCompletada || !_debeMostrarModalRutaCompletada()) {
        return;
      }

      _mostrandoModalRutaCompletada = true;

      try {
        await mostrarRutaCompletadaModal(
          context: context,
          rolActivo: _controller.rolActivo,
          totalParadas: _controller.totalParadas,
          paradasCompletadas: _controller.paradasCompletadas,
          totalReportes: _controller.totalReportesVisibles,
          onVerReportes: _controller.esAbogado ? _abrirInformesAbogado : null,
        );

        if (mounted && !_controller.esAbogado) {
          _modalRutaCompletadaCerradoPorNotificador = true;
        }

        if (mounted && _controller.esAbogado) {
          await _controller.limpiarParadas();
        }
      } finally {
        _mostrandoModalRutaCompletada = false;
      }
    });
  }

  Widget _buildDestinoSearch({required bool desktop}) {
    return Material(
      elevation: desktop ? 0 : 4,
      borderRadius: BorderRadius.circular(desktop ? 18 : 28),
      color: Colors.white,
      child: TextField(
        controller: _destinoCtrl,
        textInputAction: TextInputAction.search,
        onChanged: _controller.programarBusquedaSugerenciasDestino,
        onSubmitted: (_) => _buscarDestino(),
        decoration: InputDecoration(
          hintText: _controller.esAbogado
              ? 'Buscar direccion o calle (muestra punto exacto y pregunta si marcar)'
              : 'Buscar direccion, lugar o coordenadas',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Buscar',
            onPressed: _buscarDestino,
            icon: const Icon(Icons.arrow_forward),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(desktop ? 18 : 28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSugerenciasDestino({required bool desktop}) {
    final bool mostrarSugerencias = _controller.esAbogado &&
        (_controller.cargandoSugerenciasDestino || _controller.sugerenciasDestino.isNotEmpty) &&
        _destinoCtrl.text.trim().isNotEmpty;

    if (!mostrarSugerencias) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: desktop ? 0 : 4,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: desktop ? 260 : 220),
        child: _controller.cargandoSugerenciasDestino
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _controller.sugerenciasDestino.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final SugerenciaDestino sugerencia = _controller.sugerenciasDestino[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      sugerencia.textoPrincipal.isNotEmpty
                          ? sugerencia.textoPrincipal
                          : sugerencia.descripcion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: (sugerencia.textoSecundario ?? '').trim().isNotEmpty
                        ? Text(
                            sugerencia.textoSecundario!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => _seleccionarSugerencia(sugerencia),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildMapa() {
    final LatLng miUbicacion = _controller.miUbicacion!;

    if (_esEscritorio) {
      return _buildMapaEscritorio(miUbicacion);
    }

    return GoogleMap(
      onMapCreated: _controller.setMapController,
      initialCameraPosition: CameraPosition(target: miUbicacion, zoom: 15),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: <Marker>{
        if (_buildMarcadorBusquedaGoogle() != null) _buildMarcadorBusquedaGoogle()!,
        ..._controller.markersParadas,
      },
      polylines: _controller.polylines,
      onTap: (_controller.esAbogado && _controller.modoMarcadoEnMapa && !_controller.procesandoRegistroUbicacion)
          ? (LatLng pos) {
              unawaited(_controller.marcarDesdeToqueMapa(pos));
            }
          : null,
    );
  }

  Widget _buildMapaEscritorio(LatLng miUbicacion) {
    final List<fm.Marker> markers = <fm.Marker>[
      fm.Marker(
        width: 20,
        height: 20,
        point: ll.LatLng(miUbicacion.latitude, miUbicacion.longitude),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
      if (_buildMarcadorBusquedaFlutter() != null) _buildMarcadorBusquedaFlutter()!,
      ..._controller.paradas.values.map((parada) {
        final Color color = parada.completada ? Colors.green : Colors.lightBlue;

        return fm.Marker(
          width: 44,
          height: 44,
          point: ll.LatLng(parada.posicion.latitude, parada.posicion.longitude),
          child: Tooltip(
            message: parada.nombreUbicacion?.trim().isNotEmpty == true
                ? parada.nombreUbicacion!.trim()
                : 'U-${parada.id}',
            child: Icon(Icons.location_on, color: color, size: 34),
          ),
        );
      }),
    ];

    final List<fm.Polyline> polylines = _controller.polylines
        .map(
          (Polyline p) => fm.Polyline(
            points: p.points.map((LatLng e) => ll.LatLng(e.latitude, e.longitude)).toList(),
            color: p.color,
            strokeWidth: p.width.toDouble(),
          ),
        )
        .toList();

    return Stack(
      children: <Widget>[
        fm.FlutterMap(
          mapController: _flutterMapController,
          options: fm.MapOptions(
            initialCenter: ll.LatLng(miUbicacion.latitude, miUbicacion.longitude),
            initialZoom: 15,
            interactionOptions: const fm.InteractionOptions(flags: fm.InteractiveFlag.all),
            onTap: (_controller.esAbogado &&
                    _controller.modoMarcadoEnMapa &&
                    !_controller.procesandoRegistroUbicacion)
                ? (_, ll.LatLng point) {
                    unawaited(
                      _controller.marcarDesdeToqueMapa(
                        LatLng(point.latitude, point.longitude),
                      ),
                    );
                  }
                : null,
          ),
          children: <Widget>[
            fm.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.notificador.app',
            ),
            fm.PolylineLayer(polylines: polylines),
            fm.MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          right: 14,
          bottom: 14,
          child: FloatingActionButton.small(
            heroTag: 'btn_centrar_mapa_windows',
            onPressed: () {
              unawaited(_controller.centrarEnMiUbicacion());
            },
            tooltip: 'Centrar en mi ubicacion',
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Marker? _buildMarcadorBusquedaGoogle() {
    final LatLng? posicion = _controller.puntoBusquedaActual;
    if (posicion == null) {
      return null;
    }

    return Marker(
      markerId: const MarkerId('busqueda_actual'),
      position: posicion,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: 'Ubicacion buscada',
        snippet: _controller.descripcionBusquedaActual ?? _controller.destinoBusqueda,
      ),
      onTap: _onTapMarcadorBusqueda,
    );
  }

  fm.Marker? _buildMarcadorBusquedaFlutter() {
    final LatLng? posicion = _controller.puntoBusquedaActual;
    if (posicion == null) {
      return null;
    }

    return fm.Marker(
      width: 48,
      height: 48,
      point: ll.LatLng(posicion.latitude, posicion.longitude),
      child: Tooltip(
        message: _controller.descripcionBusquedaActual ?? _controller.destinoBusqueda,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTapMarcadorBusqueda,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
        ),
      ),
    );
  }

  Future<void> _onTapMarcadorBusqueda() async {
    if (!mounted) {
      return;
    }

    final LatLng? posicion = _controller.puntoBusquedaActual;
    if (posicion == null) {
      return;
    }

    if (!_controller.esAbogado) {
      _mostrarMensaje('Solo el abogado puede marcar ubicaciones.');
      return;
    }

    await _controller.marcarUbicacionDesdeBusqueda(
      posicion: posicion,
      destinoBusqueda: _controller.destinoBusqueda,
    );
  }

  Widget _buildCapaCarga() {
    if (!_controller.procesandoRegistroUbicacion) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text('Guardando ubicacion...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _esEscritorio =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Widget _buildPanelControl({ScrollController? scrollController, bool esEscritorio = false}) {
    return PanelControlWidget(
      scrollController: scrollController,
      esPanelFijo: esEscritorio,
      mostrarEncabezado: !esEscritorio,
      mostrarHandleArrastre: !esEscritorio,
      rolActivo: _controller.rolActivo,
      total: _controller.totalParadas,
      pendientes: _controller.paradasPendientes,
      totalReportes: _controller.totalReportesVisibles,
      rutaIds: _controller.rutaIds,
      paradas: _controller.paradas,
      modoMarcadoEnMapa: _controller.modoMarcadoEnMapa,
      distanciaDesdeMiPosicion: _controller.distanciaDesdeMiPosicion,
      onModoMarcadoChanged: _controller.cambiarModoMarcado,
      onLimpiar: () {
        unawaited(_controller.limpiarParadas());
      },
      onOptimizarRuta: () {
        unawaited(_controller.recalcularRuta());
      },
      onCentrar: () {
        unawaited(_controller.centrarEnMiUbicacion());
      },
      onVerReporte: _mostrarReporte,
      onTapParada: (int paradaId) {
        unawaited(_controller.navegarAParada(paradaId));
      },
    );
  }

  Widget _buildMobileBody() {
    return Stack(
      children: <Widget>[
        _buildMapa(),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: _buildDestinoSearch(desktop: false),
          ),
        ),
        if (_controller.esAbogado)
          Positioned(
            top: 76,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: _buildSugerenciasDestino(desktop: false),
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize: 0.24,
          minChildSize: 0.14,
          maxChildSize: 0.68,
          snap: true,
          snapSizes: const <double>[0.14, 0.24, 0.68],
          builder: (BuildContext context, ScrollController scrollController) {
            return SafeArea(
              top: false,
              child: _buildPanelControl(scrollController: scrollController),
            );
          },
        ),
        _buildCapaCarga(),
      ],
    );
  }

  Widget _buildDesktopBody(BoxConstraints constraints) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              _buildMapa(),
              _buildCapaCarga(),
            ],
          ),
        ),
        Container(
          width: constraints.maxWidth.clamp(380.0, 460.0).toDouble(),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            border: Border(left: BorderSide(color: Colors.blueGrey.shade100)),
          ),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            _controller.rolActivo == RolApp.abogado ? Icons.gavel : Icons.route,
                            color: _controller.rolActivo == RolApp.abogado ? Colors.indigo : Colors.teal,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _controller.rolActivo == RolApp.abogado ? 'Panel abogado' : 'Panel notificador',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildDestinoSearch(desktop: true),
                      const SizedBox(height: 8),
                      _buildSugerenciasDestino(desktop: true),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildPanelControl(esEscritorio: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        _evaluarCierreDeRutaYMostrarModal();
        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.title} - ${widget.usuario.nombre}'),
            actions: <Widget>[
              if (_controller.rolActivo == RolApp.abogado)
                IconButton(
                  tooltip: 'Informes',
                  onPressed: _abrirInformesAbogado,
                  icon: const Icon(Icons.assignment),
                ),
              IconButton(
                tooltip: 'Ajustes',
                onPressed: _abrirAjustes,
                icon: const Icon(Icons.settings),
              ),
              IconButton(
                tooltip: 'Cerrar sesion',
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout),
              ),
              if (_controller.rolActivo == RolApp.notificador)
                IconButton(
                  tooltip: 'Encuadrar ruta',
                  onPressed: () {
                    unawaited(_controller.encuadrarRuta());
                  },
                  icon: const Icon(Icons.fit_screen),
                ),
              if (_controller.rolActivo == RolApp.notificador)
                IconButton(
                  tooltip: 'Ver reporte',
                  onPressed: _mostrarReporte,
                  icon: const Icon(Icons.summarize),
                ),
            ],
          ),
          body: _errorInicializacion != null
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.warning_amber_rounded, size: 54),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo abrir el mapa',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorInicializacion ?? 'Ocurrio un error al iniciar el mapa.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _inicializarControllerSeguro,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _controller.miUbicacion == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        if (constraints.maxWidth >= _desktopBreakpoint) {
                          return _buildDesktopBody(constraints);
                        }
                        return _buildMobileBody();
                      },
                    ),
        );
      },
    );
  }
}

