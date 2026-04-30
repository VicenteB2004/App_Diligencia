import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/material.dart' show EdgeInsets;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:notificador/data/models/group_location.dart';
import 'package:notificador/data/models/notification_report.dart';
import 'package:notificador/data/models/ubicacion.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/data/repositories/ubicaciones_repository.dart';
import 'package:notificador/data/services/firestore_service.dart';
import 'package:notificador/data/services/map_snapshot_service.dart';
import 'package:notificador/data/services/reporte_pdf_service.dart';
import 'package:notificador/features/operacion/domain/entities/encuesta_llegada.dart';
import 'package:notificador/features/operacion/domain/entities/parada.dart';
import 'package:notificador/features/operacion/domain/entities/reporte_llegada.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';
import 'package:notificador/features/operacion/domain/entities/resultado_busqueda_destino.dart';
import 'package:notificador/features/operacion/domain/entities/sugerencia_destino.dart';
import 'package:notificador/features/operacion/domain/services/busqueda_destino_service.dart';
import 'package:notificador/features/operacion/domain/services/geocoding_service.dart';
import 'package:notificador/features/operacion/domain/services/navigation_service.dart';
import 'package:notificador/features/operacion/domain/services/optimizador_ruta_service.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

const String _kStaticMapsApiKey = String.fromEnvironment(
  'GOOGLE_STATIC_MAPS_API_KEY',
  defaultValue: String.fromEnvironment('GOOGLE_PLACES_API_KEY'),
);

class RegistroUbicacionData {
  const RegistroUbicacionData({
    required this.nombreUbicacion,
    required this.identificacionTecnica,
    required this.esSegundaNotificacion,
    required this.razonSocial,
    required this.ruc,
    required this.representanteLegal,
    required this.nombreNotificador,
    required this.cedulaNotificador,
  });

  final String nombreUbicacion;
  final String identificacionTecnica;
  final bool esSegundaNotificacion;
  final String razonSocial;
  final String ruc;
  final String representanteLegal;
  final String nombreNotificador;
  final String cedulaNotificador;
}

class OperacionController extends ChangeNotifier {
  OperacionController({
    required this.usuarioActual,
    UbicacionesRepository? ubicacionesRepository,
    BusquedaDestinoService? busquedaDestinoService,
    GeocodingService? geocodingService,
    OptimizadorRutaService? optimizadorRutaService,
    NavigationService? navigationService,
    FirestoreService? firestoreService,
    MapSnapshotService? mapSnapshotService,
    ReportePdfService? reportePdfService,
  })  : _ubicacionesRepository = ubicacionesRepository ?? UbicacionesRepository(),
        _busquedaDestinoService = busquedaDestinoService ?? const BusquedaDestinoService(),
        _geocodingService = geocodingService ?? const GeocodingService(),
        _optimizadorRutaService = optimizadorRutaService ?? const OptimizadorRutaService(),
        _navigationService = navigationService ?? const NavigationService(),
        _firestoreService = firestoreService ?? FirestoreService(),
        _mapSnapshotService = mapSnapshotService ??
            MapSnapshotService(
              staticMapsApiKey: _kStaticMapsApiKey,
            ),
        _reportePdfService = reportePdfService ?? ReportePdfService();

  final UbicacionesRepository _ubicacionesRepository;
  final BusquedaDestinoService _busquedaDestinoService;
  final GeocodingService _geocodingService;
  final OptimizadorRutaService _optimizadorRutaService;
  final NavigationService _navigationService;
  final FirestoreService _firestoreService;
  final MapSnapshotService _mapSnapshotService;
  final ReportePdfService _reportePdfService;
  final Usuario usuarioActual;

  static const double umbralLlegadaMetros = 40;
  static const Duration _kIntervaloVerificacionLlegadaNotificador = Duration(seconds: 3);
  static const Duration _kCooldownEncuestaCancelada = Duration(seconds: 20);

  GoogleMapController? _mapController;
  fm.MapController? _flutterMapController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<GroupLocation>>? _remoteLocationSubscription;
  StreamSubscription<List<NotificationReport>>? _remoteReportsSubscription;
  Timer? _remotePollingTimer;
  Timer? _verificacionLlegadaTimer;
  void Function(String message)? _messageHandler;
  Future<EncuestaLlegada?> Function({
    required int paradaId,
    required double distanciaMetros,
  })?
  _encuestaLlegadaHandler;
  Future<RegistroUbicacionData?> Function({
    required String nombreSugerido,
    required String? direccionSugerida,
  })?
  _registroUbicacionHandler;

  LatLng? _miUbicacion;
  late final RolApp _rolActivo = usuarioActual.rol;
  bool _modoMarcadoEnMapa = false;
  String _destinoBusqueda = '';
  LatLng? _puntoBusquedaActual;
  String? _descripcionBusquedaActual;
  bool _cargandoSugerenciasDestino = false;
  List<SugerenciaDestino> _sugerenciasDestino = const <SugerenciaDestino>[];
  Timer? _debounceSugerenciasDestino;
  int _requestIdSugerenciasDestino = 0;

  final Map<int, Parada> _paradas = <int, Parada>{};
  final List<int> _rutaIds = <int>[];
  final List<ReporteLlegada> _reportes = <ReporteLlegada>[];
  Set<Marker> _markersParadas = <Marker>{};
  Set<Polyline> _polylinesRuta = <Polyline>{};
  Polyline? _polylineReferenciaBusqueda;
  bool _procesandoLlegada = false;
  bool _procesandoRegistroUbicacion = false;
  int _totalReportesRemotos = 0;
  final Set<int> _ubicacionesCompletadasPorReportes = <int>{};
  final Set<int> _ubicacionesEsperadasPorReportes = <int>{};
  final Map<int, bool> _paradaDentroRadioLlegada = <int, bool>{};
  int? _paradaCanceladaId;
  DateTime? _paradaCanceladaHasta;

  bool _isDisposed = false;

  LatLng? get miUbicacion => _miUbicacion;
  RolApp get rolActivo => _rolActivo;
  bool get modoMarcadoEnMapa => _modoMarcadoEnMapa;
  String get destinoBusqueda => _destinoBusqueda;
  LatLng? get puntoBusquedaActual => _puntoBusquedaActual;
  String? get descripcionBusquedaActual => _descripcionBusquedaActual;
  bool get cargandoSugerenciasDestino => _cargandoSugerenciasDestino;
  List<SugerenciaDestino> get sugerenciasDestino => _sugerenciasDestino;
  Map<int, Parada> get paradas => _paradas;
  List<int> get rutaIds => _rutaIds;
  List<ReporteLlegada> get reportes => _reportes;
  Set<Marker> get markersParadas => _markersParadas;
  Set<Polyline> get polylines {
    final Set<Polyline> activas = <Polyline>{..._polylinesRuta};
    final Polyline? referencia = _polylineReferenciaBusqueda;
    if (referencia != null) {
      activas.add(referencia);
    }
    return activas;
  }

  int get totalParadas => _paradas.length;
  int get paradasPendientes => _paradas.values.where((Parada p) => !p.completada).length;
  int get paradasCompletadas => _paradas.values.where((Parada p) => p.completada).length;
  int get totalReportesVisibles => _totalReportesRemotos > _reportes.length ? _totalReportesRemotos : _reportes.length;
  bool get rutaCompletadaPorReportes {
    if (_ubicacionesEsperadasPorReportes.isEmpty) {
      return false;
    }

    final Set<int> reportesActivos = _reportes
        .map((ReporteLlegada reporte) => reporte.paradaId)
        .toSet();

    return _ubicacionesEsperadasPorReportes.every(reportesActivos.contains);
  }

  bool get esAbogado => _rolActivo == RolApp.abogado;
  bool get _esNotificador => !esAbogado;
  bool get procesandoRegistroUbicacion => _procesandoRegistroUbicacion;

  LocationAccuracy get _accuracySeguimiento =>
      _esNotificador ? LocationAccuracy.bestForNavigation : LocationAccuracy.high;

  int get _distanceFilterSeguimientoMetros => _esNotificador ? 1 : 3;

  void setMessageHandler(void Function(String message)? handler) {
    _messageHandler = handler;
  }

  void setEncuestaLlegadaHandler(
    Future<EncuestaLlegada?> Function({required int paradaId, required double distanciaMetros})?
    handler,
  ) {
    _encuestaLlegadaHandler = handler;
  }

  void setRegistroUbicacionHandler(
    Future<RegistroUbicacionData?> Function({
      required String nombreSugerido,
      required String? direccionSugerida,
    })?
    handler,
  ) {
    _registroUbicacionHandler = handler;
  }

  void setMapController(GoogleMapController controller) {
    _mapController = controller;
  }

  void setFlutterMapController(fm.MapController controller) {
    _flutterMapController = controller;
  }

  bool get tieneControladorMapa => _mapController != null || _flutterMapController != null;

  Future<void> _animarCamaraPunto(LatLng target, double zoom) async {
    final GoogleMapController? mapController = _mapController;
    if (mapController != null) {
      await mapController.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
      return;
    }

    final fm.MapController? flutterMapController = _flutterMapController;
    if (flutterMapController != null) {
      flutterMapController.move(ll.LatLng(target.latitude, target.longitude), zoom);
    }
  }

  Future<void> _animarCamaraBounds(List<LatLng> puntos, {double padding = 80}) async {
    if (puntos.isEmpty) {
      return;
    }

    final GoogleMapController? mapController = _mapController;
    if (mapController != null) {
      await mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
          _optimizadorRutaService.calcularBounds(puntos),
          padding,
        ),
      );
      return;
    }

    final fm.MapController? flutterMapController = _flutterMapController;
    if (flutterMapController != null) {
      flutterMapController.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(
            puntos.map((LatLng p) => ll.LatLng(p.latitude, p.longitude)).toList(),
          ),
          padding: EdgeInsets.all(padding),
        ),
      );
    }
  }

  Future<void> inicializar() async {
    try {
      await _iniciarUbicacion();
    } catch (e) {
      _emitMessage('No se pudo iniciar ubicacion: $e');
    }

    try {
      await _cargarUbicacionesPersistidas();
      await _verificarLlegadaConUbicacionActual();
    } catch (e) {
      _emitMessage('No se pudieron cargar ubicaciones locales: $e');
    }

    try {
      _iniciarSincronizacionRemota();
    } catch (e) {
      _emitMessage('No se pudo iniciar sincronizacion: $e');
    }
  }

  void _iniciarSincronizacionRemota() {
    _remoteLocationSubscription?.cancel();
    _remoteReportsSubscription?.cancel();

    if (!_tieneGrupoAsignado) {
      _remotePollingTimer?.cancel();
      _remotePollingTimer = null;
      _limpiarDatosRemotos();
      return;
    }

    // En plataformas nativas usamos polling para evitar cierres por errores de hilos
    // reportados por algunos plugins en canales de snapshots.
    final bool usarPollingNativo = !kIsWeb;
    if (usarPollingNativo) {
      _remotePollingTimer?.cancel();
      unawaited(_sincronizarRemotoPorConsulta());
      _remotePollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_sincronizarRemotoPorConsulta());
      });
      return;
    }

    _remoteLocationSubscription = _firestoreService
        .streamLocationsByCurrentUserGroup()
        .listen((List<GroupLocation> remotas) {
          _sincronizarParadasDesdeNube(remotas);
        }, onError: (Object e) {
          _emitMessage('No se pudo sincronizar ubicaciones en tiempo real: $e');
        });

    _remoteReportsSubscription = _firestoreService
        .streamNotificationReportsByCurrentUserGroup(limit: 200)
        .listen((List<NotificationReport> reportesRemotos) {
          _totalReportesRemotos = reportesRemotos.length;
          _reportes
            ..clear()
            ..addAll(
              reportesRemotos.map(
                (NotificationReport r) => ReporteLlegada(
                  paradaId: r.ubicacionId,
                  fechaHora: r.fechaHora,
                  distanciaLlegadaMetros: _miUbicacion == null
                      ? 0
                      : _optimizadorRutaService.distanciaMetros(
                          _miUbicacion!,
                          LatLng(r.lat, r.lng),
                        ),
                  ubicacionLlegada: LatLng(r.lat, r.lng),
                  tipoNotificacion: r.tipoNotificacion.isEmpty ? null : r.tipoNotificacion,
                  personaNotificada: r.personaNotificada.isEmpty ? null : r.personaNotificada,
                  descripcionDiligencia: r.descripcionDiligencia.isEmpty ? null : r.descripcionDiligencia,
                  reporteFirestoreId: r.id,
                ),
              ),
            );
          _aplicarEstadosCompletadosDesdeReportes();
          unawaited(recalcularRuta());
          unawaited(_verificarLlegadaConUbicacionActual(timeLimit: const Duration(seconds: 2)));
          _safeNotify();
        }, onError: (Object e) {
          _emitMessage('No se pudo sincronizar reportes en tiempo real: $e');
        });
  }

  Future<void> _sincronizarRemotoPorConsulta() async {
    if (!_tieneGrupoAsignado) {
      _limpiarDatosRemotos();
      return;
    }

    try {
      final List<GroupLocation> remotas = await _firestoreService.getLocationsByCurrentUserGroup();
      _sincronizarParadasDesdeNube(remotas);
    } on FirestoreServiceException catch (e) {
      if (_esErrorDeUsuarioSinGrupo(e)) {
        _limpiarDatosRemotos();
        return;
      }
      _emitMessage('No se pudo sincronizar ubicaciones: $e');
    } catch (e) {
      _emitMessage('No se pudo sincronizar ubicaciones: $e');
    }

    try {
      final List<NotificationReport> reportesRemotos =
          await _firestoreService.getNotificationReportsByCurrentUserGroup(limit: 200);
      _totalReportesRemotos = reportesRemotos.length;
      _reportes
        ..clear()
        ..addAll(
          reportesRemotos.map(
            (NotificationReport r) => ReporteLlegada(
              paradaId: r.ubicacionId,
              fechaHora: r.fechaHora,
              distanciaLlegadaMetros: _miUbicacion == null
                  ? 0
                  : _optimizadorRutaService.distanciaMetros(
                      _miUbicacion!,
                      LatLng(r.lat, r.lng),
                    ),
              ubicacionLlegada: LatLng(r.lat, r.lng),
              tipoNotificacion: r.tipoNotificacion.isEmpty ? null : r.tipoNotificacion,
              personaNotificada: r.personaNotificada.isEmpty ? null : r.personaNotificada,
              descripcionDiligencia: r.descripcionDiligencia.isEmpty ? null : r.descripcionDiligencia,
              reporteFirestoreId: r.id,
            ),
          ),
        );
      _aplicarEstadosCompletadosDesdeReportes();
      await recalcularRuta();
      _safeNotify();
      await _verificarLlegadaConUbicacionActual(timeLimit: const Duration(seconds: 2));
    } on FirestoreServiceException catch (e) {
      if (_esErrorDeUsuarioSinGrupo(e)) {
        _limpiarDatosRemotos();
        return;
      }
      _emitMessage('No se pudo sincronizar reportes: $e');
    } catch (e) {
      _emitMessage('No se pudo sincronizar reportes: $e');
    }
  }

  void _sincronizarParadasDesdeNube(List<GroupLocation> remotas) {
    if (remotas.isEmpty) {
      // En abogado, mantener el estado local evita que una respuesta vacia
      // temporal de la nube borre una ubicacion recien marcada.
      if (esAbogado && _paradas.isNotEmpty) {
        return;
      }

      if (_paradas.isNotEmpty ||
          _rutaIds.isNotEmpty ||
          _polylinesRuta.isNotEmpty ||
          _polylineReferenciaBusqueda != null ||
          _paradaDentroRadioLlegada.isNotEmpty) {
        _paradas.clear();
        _markersParadas = <Marker>{};
        _rutaIds.clear();
        _polylinesRuta = <Polyline>{};
        _polylineReferenciaBusqueda = null;
        _ubicacionesEsperadasPorReportes.clear();
        _paradaDentroRadioLlegada.clear();
        _safeNotify();
      }
      return;
    }

    _paradas
      ..clear()
      ..addEntries(
        remotas.map((GroupLocation item) {
          final int id = item.ubicacionId ?? _idEstableDesdeDoc(item.id);
          final String identificacion = (item.identificacionTecnica ?? '').trim().toUpperCase();
          return MapEntry<int, Parada>(
            id,
            Parada(
              id: id,
              posicion: LatLng(item.lat, item.lng),
              nombreUbicacion: (item.nombreUbicacion ?? '').trim().isEmpty ? 'U-$id' : item.nombreUbicacion,
              identificacionTecnica: identificacion.isEmpty ? null : identificacion,
              esSegundaNotificacion: item.esSegundaNotificacion,
              razonSocial: item.razonSocial,
              ruc: item.ruc,
              representanteLegal: item.representanteLegal,
              nombreNotificador: item.nombreNotificador,
              cedulaNotificador: item.cedulaNotificador,
              completada: (item.estado ?? '').trim().toLowerCase() == 'completada',
            ),
          );
        }),
      );

    _paradaDentroRadioLlegada.removeWhere((int paradaId, bool _) => !_paradas.containsKey(paradaId));
    _reconstruirMarkersParadas();

    _actualizarUbicacionesEsperadasPorReportes();

    _aplicarEstadosCompletadosDesdeReportes();
    unawaited(recalcularRuta());
    unawaited(_verificarLlegadaConUbicacionActual());
    _safeNotify();
  }

  void _aplicarEstadosCompletadosDesdeReportes() {
    if (_paradas.isEmpty) {
      _ubicacionesCompletadasPorReportes.clear();
      return;
    }

    _ubicacionesCompletadasPorReportes
      ..clear()
      ..addAll(_reportes.map((ReporteLlegada reporte) => reporte.paradaId));

    for (final Parada parada in _paradas.values) {
      parada.completada = _ubicacionesCompletadasPorReportes.contains(parada.id);
    }

    _paradaDentroRadioLlegada.removeWhere((int paradaId, bool _) => !_paradas.containsKey(paradaId));
    _reconstruirMarkersParadas();
  }

  bool _paradaYaTieneInforme(int paradaId) {
    if (_ubicacionesCompletadasPorReportes.contains(paradaId)) {
      return true;
    }
    if (_reportes.any((ReporteLlegada r) => r.paradaId == paradaId)) {
      return true;
    }
    return _paradas[paradaId]?.completada == true;
  }

  void _actualizarUbicacionesEsperadasPorReportes() {
    _ubicacionesEsperadasPorReportes
      ..clear()
      ..addAll(_paradas.keys);
  }

  int _idEstableDesdeDoc(String docId) {
    int hash = 0;
    for (final int code in docId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  void cambiarModoMarcado(bool activo) {
    _modoMarcadoEnMapa = activo;
    _safeNotify();
  }

  void _establecerPuntoBusqueda({required LatLng? posicion, String? descripcion}) {
    _puntoBusquedaActual = posicion;
    _descripcionBusquedaActual = posicion == null ? null : descripcion;
  }

  Future<void> buscarDestinoYEnfocar(String destino) async {
    limpiarSugerenciasDestino(notify: false);
    _establecerPuntoBusqueda(posicion: null);

    ResultadoBusquedaDestino resultado = await _busquedaDestinoService.resolverDestino(
      destino,
      busquedaExacta: esAbogado,
    );

    if (!resultado.exito && esAbogado) {
      final ResultadoBusquedaDestino tolerante = await _busquedaDestinoService.resolverDestino(
        destino,
        busquedaExacta: false,
      );
      final LatLng? posicionTolerante = tolerante.posicion;
      if (tolerante.exito && posicionTolerante != null) {
        resultado = ResultadoBusquedaDestino.ok(
          posicion: posicionTolerante,
          fueCoordenada: tolerante.fueCoordenada,
          mensajeInfo:
              'No hubo coincidencia exacta. Se mostro el punto mas cercano disponible.',
          trazadoReferencia: tolerante.trazadoReferencia,
        );
      }
    }

    if (!resultado.exito || resultado.posicion == null) {
      _polylineReferenciaBusqueda = null;
      _establecerPuntoBusqueda(posicion: null);
      _emitMessage(resultado.mensajeError ?? 'No se pudo ubicar el destino.');
      _safeNotify();
      return;
    }

    _polylineReferenciaBusqueda = _construirPolylineReferencia(resultado.trazadoReferencia);

    final LatLng posicionSeleccionada = resultado.posicion!;
    _establecerPuntoBusqueda(posicion: posicionSeleccionada, descripcion: destino.trim());

    final List<LatLng> puntosEnfoque = <LatLng>[posicionSeleccionada, ...resultado.trazadoReferencia];
    if (puntosEnfoque.length >= 2) {
      await _animarCamaraBounds(puntosEnfoque, padding: 90);
    } else {
      await _animarCamaraPunto(posicionSeleccionada, 16);
    }

    _destinoBusqueda = destino.trim();
    _safeNotify();

    _emitMessage(
      esAbogado
          ? 'Mapa centrado en $_destinoBusqueda. Toca el punto rojo para marcar o registrar la ubicacion.'
          : 'Mapa centrado en $_destinoBusqueda.',
    );

    if (_polylineReferenciaBusqueda != null) {
      _emitMessage('La linea roja marca el tramo estimado de la calle para mayor precision.');
    }

    final String? mensajeInfo = resultado.mensajeInfo?.trim();
    if (mensajeInfo != null && mensajeInfo.isNotEmpty) {
      _emitMessage(mensajeInfo);
    }
  }

  void programarBusquedaSugerenciasDestino(String texto) {
    if (!esAbogado) {
      return;
    }

    _debounceSugerenciasDestino?.cancel();
    final String consulta = texto.trim();

    if (consulta.length < 3) {
      limpiarSugerenciasDestino();
      return;
    }

    _debounceSugerenciasDestino = Timer(const Duration(milliseconds: 350), () {
      unawaited(_buscarSugerenciasDestino(consulta));
    });
  }

  Future<void> seleccionarSugerenciaYBuscar(SugerenciaDestino sugerencia) async {
    await buscarDestinoYEnfocar(sugerencia.descripcion);
  }

  void limpiarSugerenciasDestino({bool notify = true}) {
    _debounceSugerenciasDestino?.cancel();
    _debounceSugerenciasDestino = null;
    _requestIdSugerenciasDestino++;

    final bool cambio =
        _cargandoSugerenciasDestino || _sugerenciasDestino.isNotEmpty;
    _cargandoSugerenciasDestino = false;
    _sugerenciasDestino = const <SugerenciaDestino>[];

    if (notify && cambio) {
      _safeNotify();
    }
  }

  Future<void> _buscarSugerenciasDestino(String consulta) async {
    final int requestId = ++_requestIdSugerenciasDestino;
    _cargandoSugerenciasDestino = true;
    _safeNotify();

    try {
      final List<SugerenciaDestino> sugerencias =
          await _busquedaDestinoService.buscarSugerencias(consulta);

      if (_isDisposed || requestId != _requestIdSugerenciasDestino) {
        return;
      }

      _cargandoSugerenciasDestino = false;
      _sugerenciasDestino = sugerencias;
      _safeNotify();
    } catch (_) {
      if (_isDisposed || requestId != _requestIdSugerenciasDestino) {
        return;
      }
      _cargandoSugerenciasDestino = false;
      _sugerenciasDestino = const <SugerenciaDestino>[];
      _safeNotify();
    }
  }

  Future<void> marcarDesdeToqueMapa(LatLng posicion) async {
    if (!esAbogado) {
      _emitMessage('Solo el abogado puede crear ubicaciones.');
      return;
    }

    if (!_modoMarcadoEnMapa) {
      _emitMessage('Primero busca un destino para activar el marcado.');
      return;
    }

    if (_procesandoRegistroUbicacion) {
      return;
    }
    _procesandoRegistroUbicacion = true;
    _safeNotify();

    try {
      final bool guardado = await _registrarUbicacionDesdePosicion(
        posicion: posicion,
        destinoBusqueda: _destinoBusqueda,
      );
      if (guardado) {
        _emitMessage('Ubicacion marcada en el mapa.');
      }
    } finally {
      _procesandoRegistroUbicacion = false;
      _safeNotify();
    }
  }

  Future<void> marcarUbicacionDesdeBusqueda({
    required LatLng posicion,
    required String destinoBusqueda,
  }) async {
    if (!esAbogado) {
      return;
    }

    if (_procesandoRegistroUbicacion) {
      return;
    }

    _procesandoRegistroUbicacion = true;
    _safeNotify();

    try {
      final bool guardado = await _registrarUbicacionDesdePosicion(
        posicion: posicion,
        destinoBusqueda: destinoBusqueda,
      );
      if (guardado) {
        _establecerPuntoBusqueda(posicion: null);
        _emitMessage('Ubicacion de la busqueda marcada para el notificador.');
      }
    } finally {
      _procesandoRegistroUbicacion = false;
      _safeNotify();
    }
  }

  Future<bool> _registrarUbicacionDesdePosicion({
    required LatLng posicion,
    required String destinoBusqueda,
  }) async {
    final String? direccion = await _geocodingService.direccionDesdeCoordenadas(posicion);
    final String nombreSugerido = _nombreUbicacionSugerido(
      direccion: direccion,
      destinoBusqueda: destinoBusqueda,
    );
    final handler = _registroUbicacionHandler;
    if (handler == null) {
      _emitMessage('No se pudo abrir el formulario de la ubicacion.');
      return false;
    }

    final RegistroUbicacionData? registro = await handler(
      nombreSugerido: nombreSugerido,
      direccionSugerida: direccion,
    );
    if (registro == null) {
      _emitMessage('Registro de ubicacion cancelado.');
      return false;
    }

    await _agregarParadaPersistida(
      posicion,
      direccion: direccion,
      descripcion: destinoBusqueda.isEmpty ? 'Punto legal asignado' : 'Punto legal en $destinoBusqueda',
      nombreUbicacion: registro.nombreUbicacion,
      identificacionTecnica: registro.identificacionTecnica,
      esSegundaNotificacion: registro.esSegundaNotificacion,
      razonSocial: registro.razonSocial,
      ruc: registro.ruc,
      representanteLegal: registro.representanteLegal,
      nombreNotificador: registro.nombreNotificador,
      cedulaNotificador: registro.cedulaNotificador,
    );

    return true;
  }

  Future<void> limpiarParadas() async {
    if (!esAbogado) {
      _emitMessage('Solo el abogado puede limpiar ubicaciones.');
      return;
    }

    try {
      await _firestoreService.deleteLocationsByCurrentUserGroup();
      if (usuarioActual.id != null) {
        await _ubicacionesRepository.borrarUbicacionesPorAbogado(usuarioActual.id!);
      }
    } catch (e) {
      _emitMessage('No se pudieron borrar algunas ubicaciones guardadas: $e');
    } finally {
      _paradas.clear();
      _markersParadas = <Marker>{};
      _rutaIds.clear();
      _polylinesRuta = <Polyline>{};
      _polylineReferenciaBusqueda = null;
      _establecerPuntoBusqueda(posicion: null);
      _reportes.clear();
      _ubicacionesCompletadasPorReportes.clear();
      _totalReportesRemotos = 0;
      _ubicacionesEsperadasPorReportes.clear();
      _paradaDentroRadioLlegada.clear();
      _paradaCanceladaId = null;
      _paradaCanceladaHasta = null;
      _safeNotify();
    }

    _emitMessage('Rutas y ubicaciones limpiadas.');
  }

  Future<void> recalcularRuta() async {
    final LatLng? miUbicacionActual = _miUbicacion;
    if (miUbicacionActual == null) {
      return;
    }

    final ResultadoRuta resultado = _optimizadorRutaService.recalcularRuta(
      miUbicacion: miUbicacionActual,
      paradas: _paradas.values,
    );

    _rutaIds
      ..clear()
      ..addAll(resultado.rutaIds);
    _polylinesRuta = resultado.polylines;
    _safeNotify();
  }

  Polyline? _construirPolylineReferencia(List<LatLng> puntos) {
    if (puntos.length < 2) {
      return null;
    }

    return Polyline(
      polylineId: const PolylineId('referencia_calle_busqueda'),
      points: puntos,
      color: const Color(0xFFE53935),
      width: 6,
      zIndex: 5,
      patterns: <PatternItem>[
        PatternItem.dash(24),
        PatternItem.gap(10),
      ],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
  }

  Future<void> centrarEnMiUbicacion() async {
    if (!_debeUsarStreamDeUbicacion) {
      final Position? posicionActual = await _obtenerPosicionActualConFallback();
      if (posicionActual != null) {
        _miUbicacion = LatLng(posicionActual.latitude, posicionActual.longitude);
        _safeNotify();
        await recalcularRuta();
      }
    }

    final LatLng? miUbicacionActual = _miUbicacion;
    if (miUbicacionActual == null) {
      return;
    }

    await _animarCamaraPunto(miUbicacionActual, 15);
  }

  Future<void> enfocarParada(int paradaId) async {
    final Parada? parada = _paradas[paradaId];
    if (parada == null) {
      return;
    }
    await _animarCamaraPunto(parada.posicion, 17);
  }

  Future<void> navegarAParada(int paradaId) async {
    final Parada? parada = _paradas[paradaId];
    if (parada == null) {
      _emitMessage('No se encontro la ubicacion seleccionada.');
      return;
    }

    final bool abierto = await _navigationService.abrirNavegacion(
      destino: parada.posicion,
      origen: _miUbicacion,
    );

    if (!abierto) {
      await enfocarParada(paradaId);
      _emitMessage('No se pudo abrir Google Maps. Se enfoco la parada en el mapa.');
      return;
    }

    final String nombre = parada.nombreUbicacion?.trim().isNotEmpty == true
        ? parada.nombreUbicacion!.trim()
        : 'U-$paradaId';
    _emitMessage('Abriendo navegacion exacta a $nombre.');
  }

  Future<void> encuadrarRuta() async {
    final LatLng? miUbicacionActual = _miUbicacion;
    if (miUbicacionActual == null || _rutaIds.isEmpty || !tieneControladorMapa) {
      return;
    }

    final List<LatLng> puntos = <LatLng>[miUbicacionActual];
    for (final int id in _rutaIds) {
      final Parada? parada = _paradas[id];
      if (parada != null) {
        puntos.add(parada.posicion);
      }
    }

    if (puntos.length == 1) {
      await centrarEnMiUbicacion();
      return;
    }

    await _animarCamaraBounds(puntos, padding: 70);
  }

  double? distanciaDesdeMiPosicion(int paradaId) {
    final LatLng? miUbicacionActual = _miUbicacion;
    final Parada? parada = _paradas[paradaId];
    if (miUbicacionActual == null || parada == null) {
      return null;
    }

    return _optimizadorRutaService.distanciaMetros(miUbicacionActual, parada.posicion);
  }

  String textoReporte() {
    if (_reportes.isEmpty) {
      return 'No hay llegadas registradas.';
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('Reporte de ruta');
    buffer.writeln('Total paradas: ${_paradas.length}');
    buffer.writeln('Paradas completadas: ${_reportes.length}');
    buffer.writeln('');

    for (final ReporteLlegada reporte in _reportes) {
      final String extra = reporte.tipoNotificacion == null
          ? ''
          : ' | tipo: ${reporte.tipoNotificacion} | persona: ${reporte.personaNotificada}';
      buffer.writeln(
        '${_paradas[reporte.paradaId]?.nombreUbicacion ?? 'U-${reporte.paradaId}'} | ${reporte.fechaHora.toIso8601String()} | '
        'dist: ${reporte.distanciaLlegadaMetros.toStringAsFixed(1)} m | '
        'lat: ${reporte.ubicacionLlegada.latitude.toStringAsFixed(6)} | '
        'lng: ${reporte.ubicacionLlegada.longitude.toStringAsFixed(6)}$extra',
      );
    }

    return buffer.toString();
  }

  void _reconstruirMarkersParadas() {
    _markersParadas = _paradas.values.map((Parada parada) {
      final BitmapDescriptor color = parada.completada
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

      return Marker(
        markerId: MarkerId('U-${parada.id}'),
        position: parada.posicion,
        icon: color,
        infoWindow: InfoWindow(
          title: parada.nombreUbicacion?.trim().isNotEmpty == true
              ? parada.nombreUbicacion!.trim()
              : 'U-${parada.id}',
          snippet: '${parada.identificacionTecnica ?? '-'} | ${parada.completada ? 'Completada' : 'Pendiente'}',
        ),
      );
    }).toSet();
  }

  Future<void> _iniciarUbicacion() async {
    final bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      _emitMessage('Activa el GPS para iniciar el seguimiento.');
      return;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      _emitMessage('Permiso de ubicacion denegado.');
      return;
    }

    if (permiso == LocationPermission.deniedForever) {
      _emitMessage('Permiso denegado para siempre. Abre ajustes.');
      return;
    }

    final Position? posicion = await _obtenerPosicionActualConFallback();
    if (posicion == null) {
      _emitMessage('No se pudo obtener tu ubicacion actual.');
      return;
    }

    _miUbicacion = LatLng(posicion.latitude, posicion.longitude);
    _safeNotify();

    if (!_debeUsarStreamDeUbicacion) {
      await recalcularRuta();
      await _verificarLlegadaConUbicacionActual();
      return;
    }

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: _accuracySeguimiento,
        distanceFilter: _distanceFilterSeguimientoMetros,
      ),
    ).listen((Position nuevaPosicion) async {
      try {
        _miUbicacion = LatLng(nuevaPosicion.latitude, nuevaPosicion.longitude);
        _safeNotify();
        await _verificarLlegada();
        await recalcularRuta();
      } catch (e) {
        _emitMessage('No se pudo procesar actualizacion de ubicacion: $e');
      }
    }, onError: (Object e) {
      _emitMessage('Error en el seguimiento de ubicacion: $e');
    });

    await recalcularRuta();
    await _verificarLlegadaConUbicacionActual();
    _iniciarVerificacionLlegadaPeriodica();
  }

  void _iniciarVerificacionLlegadaPeriodica() {
    if (!_debeUsarStreamDeUbicacion || !_esNotificador) {
      return;
    }

    _verificacionLlegadaTimer?.cancel();
    _verificacionLlegadaTimer = Timer.periodic(_kIntervaloVerificacionLlegadaNotificador, (_) {
      unawaited(_verificarLlegadaConUbicacionActual());
    });
  }

  Future<void> _verificarLlegadaConUbicacionActual({
    Duration timeLimit = const Duration(seconds: 4),
  }) async {
    if (_isDisposed || _procesandoLlegada || _paradas.isEmpty) {
      return;
    }

    final Position? posicion = await _obtenerPosicionActualConFallback(timeLimit: timeLimit);
    if (posicion == null) {
      return;
    }

    final LatLng ubicacionActual = LatLng(posicion.latitude, posicion.longitude);
    final LatLng? ubicacionAnterior = _miUbicacion;
    final bool cambioRelevante = ubicacionAnterior == null ||
        _optimizadorRutaService.distanciaMetros(ubicacionAnterior, ubicacionActual) >= 2;

    _miUbicacion = ubicacionActual;
    if (cambioRelevante) {
      _safeNotify();
      await recalcularRuta();
    }

    await _verificarLlegada();
  }

  Future<Position?> _obtenerPosicionActualConFallback({
    Duration timeLimit = const Duration(seconds: 10),
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: _accuracySeguimiento,
        timeLimit: timeLimit,
      );
    } on TimeoutException {
      // Si no hay fix inmediato, intentamos con la ultima posicion conocida.
    } catch (_) {
      // Cualquier error de lectura actual cae al fallback.
    }

    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  bool get _debeUsarStreamDeUbicacion =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);


  Future<void> _cargarUbicacionesPersistidas() async {
    if (!esAbogado) {
      _limpiarDatosRemotos();
      return;
    }

    final List<Ubicacion> rows = await _ubicacionesRepository.listarUbicaciones(
      abogadoId: esAbogado ? usuarioActual.id : null,
    );
    _paradas
      ..clear()
      ..addEntries(
        rows.where((Ubicacion row) => row.id != null).map(
              (Ubicacion row) => MapEntry<int, Parada>(
                row.id!,
                Parada(
                  id: row.id!,
                  posicion: LatLng(row.latitud, row.longitud),
                  nombreUbicacion: row.nombreUbicacion,
                  identificacionTecnica: row.identificacionTecnica,
                  esSegundaNotificacion: row.esSegundaNotificacion,
                  razonSocial: row.razonSocial,
                  ruc: row.ruc,
                  representanteLegal: row.representanteLegal,
                  nombreNotificador: row.nombreNotificador,
                  cedulaNotificador: row.cedulaNotificador,
                  completada: row.estado == 'completada',
                ),
              ),
            ),
      );

    _actualizarUbicacionesEsperadasPorReportes();
    _reconstruirMarkersParadas();

    _safeNotify();
    await recalcularRuta();
    unawaited(_verificarLlegadaConUbicacionActual());
  }

  Future<void> _agregarParadaPersistida(
    LatLng posicion, {
    String? direccion,
    String? descripcion,
    String? nombreUbicacion,
    String? identificacionTecnica,
    bool esSegundaNotificacion = false,
    String? razonSocial,
    String? ruc,
    String? representanteLegal,
    String? nombreNotificador,
    String? cedulaNotificador,
  }) async {
    final int? abogadoId = usuarioActual.id;
    if (abogadoId == null) {
      _emitMessage('No se pudo identificar el abogado autenticado.');
      return;
    }

    final int id = await _ubicacionesRepository.crearUbicacionAbogado(
      abogadoId: abogadoId,
      posicion: posicion,
      direccion: direccion,
      descripcion: descripcion ?? 'Punto legal asignado',
      nombreUbicacion: nombreUbicacion,
      identificacionTecnica: identificacionTecnica,
      esSegundaNotificacion: esSegundaNotificacion,
      razonSocial: razonSocial,
      ruc: ruc,
      representanteLegal: representanteLegal,
      nombreNotificador: nombreNotificador,
      cedulaNotificador: cedulaNotificador,
    );

    _paradas[id] = Parada(
      id: id,
      posicion: posicion,
      nombreUbicacion: nombreUbicacion,
      identificacionTecnica: identificacionTecnica,
      esSegundaNotificacion: esSegundaNotificacion,
      razonSocial: razonSocial,
      ruc: ruc,
      representanteLegal: representanteLegal,
      nombreNotificador: nombreNotificador,
      cedulaNotificador: cedulaNotificador,
    );
    _actualizarUbicacionesEsperadasPorReportes();
    _reconstruirMarkersParadas();
    _safeNotify();

    try {
      await _firestoreService.saveLocation(
        lat: posicion.latitude,
        lng: posicion.longitude,
        timestamp: DateTime.now(),
        ubicacionId: id,
        nombreUbicacion: nombreUbicacion,
        identificacionTecnica: identificacionTecnica,
        esSegundaNotificacion: esSegundaNotificacion,
        razonSocial: razonSocial,
        ruc: ruc,
        representanteLegal: representanteLegal,
        nombreNotificador: nombreNotificador,
        cedulaNotificador: cedulaNotificador,
        estado: 'pendiente',
      );
    } on FirestoreServiceException catch (e) {
      final String suffix = (e.code ?? '').trim().isEmpty ? '' : ' (codigo: ${e.code})';
      _emitMessage('Se guardo local, pero no se sincronizo con la nube: ${e.message}$suffix');
    } catch (_) {
      _emitMessage('Se guardo local, pero no se sincronizo con la nube.');
    }

    await recalcularRuta();
    await _animarCamaraPunto(posicion, 16);
  }

  Future<void> _verificarLlegada() async {
    final LatLng? miUbicacionActual = _miUbicacion;
    if (miUbicacionActual == null || _paradas.isEmpty || _procesandoLlegada) {
      return;
    }

    // El abogado solo crea/gestiona ubicaciones; no debe completar paradas ni generar reportes de llegada.
    if (esAbogado) {
      return;
    }

    final Iterable<int> ordenEvaluacion = _rutaIds.isEmpty ? _paradas.keys : _rutaIds;
    final List<Parada> pendientes = ordenEvaluacion
        .map((int id) => _paradas[id])
        .whereType<Parada>()
        .where((Parada p) => !p.completada && !_paradaYaTieneInforme(p.id))
        .toList();
    if (pendientes.isEmpty) {
      return;
    }

    _paradaDentroRadioLlegada.removeWhere((int paradaId, bool _) => !_paradas.containsKey(paradaId));

    final DateTime now = DateTime.now();
    final List<_CandidataLlegada> candidatasDentroRadio = <_CandidataLlegada>[];

    pendientes.sort(
      (Parada a, Parada b) => _optimizadorRutaService
          .distanciaMetros(miUbicacionActual, a.posicion)
          .compareTo(_optimizadorRutaService.distanciaMetros(miUbicacionActual, b.posicion)),
    );

    for (final Parada candidata in pendientes) {
      final double distanciaCandidata = _optimizadorRutaService.distanciaMetros(
        miUbicacionActual,
        candidata.posicion,
      );
      final bool dentroRadio = distanciaCandidata <= umbralLlegadaMetros;
      final bool estabaDentro = _paradaDentroRadioLlegada[candidata.id] ?? false;
      _paradaDentroRadioLlegada[candidata.id] = dentroRadio;

      if (!dentroRadio) {
        continue;
      }

      final bool enCooldown =
          _paradaCanceladaId == candidata.id &&
          _paradaCanceladaHasta != null &&
          now.isBefore(_paradaCanceladaHasta!);
      if (enCooldown) {
        continue;
      }

      candidatasDentroRadio.add(
        _CandidataLlegada(
          parada: candidata,
          distanciaMetros: distanciaCandidata,
          recienEntroAlRadio: !estabaDentro,
        ),
      );
    }

    if (candidatasDentroRadio.isEmpty) {
      return;
    }

    candidatasDentroRadio.sort((
      _CandidataLlegada a,
      _CandidataLlegada b,
    ) {
      if (a.recienEntroAlRadio != b.recienEntroAlRadio) {
        return a.recienEntroAlRadio ? -1 : 1;
      }
      return a.distanciaMetros.compareTo(b.distanciaMetros);
    });

    final _CandidataLlegada seleccion = candidatasDentroRadio.first;
    final Parada destino = seleccion.parada;
    final double distancia = seleccion.distanciaMetros;

    if (_paradaYaTieneInforme(destino.id)) {
      destino.completada = true;
      return;
    }

    _procesandoLlegada = true;

    try {
      EncuestaLlegada? encuesta;
      String? reporteFirestoreId;
      final DateTime fechaHoraReporte = DateTime.now();

      if (_paradaYaTieneInforme(destino.id)) {
        destino.completada = true;
        return;
      }

      if (!esAbogado) {
        final handler = _encuestaLlegadaHandler;
        if (handler == null) {
          _emitMessage('No se pudo abrir la encuesta de llegada.');
          return;
        }

        encuesta = await handler(paradaId: destino.id, distanciaMetros: distancia);
        if (encuesta == null) {
          _paradaCanceladaId = destino.id;
          _paradaCanceladaHasta = DateTime.now().add(_kCooldownEncuestaCancelada);
          _emitMessage('Encuesta cancelada. Vuelve a intentarlo al llegar al punto.');
          return;
        }

        if (_paradaYaTieneInforme(destino.id)) {
          destino.completada = true;
          _emitMessage('Esta ubicacion ya tiene informe registrado.');
          return;
        }

        final String direccion =
            (await _geocodingService.direccionDesdeCoordenadas(destino.posicion)) ??
            'Direccion no disponible';
        final Uint8List? mapaCoordenadasBytes = await _mapSnapshotService.obtenerMapaEstatico(
          lat: miUbicacionActual.latitude,
          lng: miUbicacionActual.longitude,
        );
        final Uint8List pdfBytes = await _reportePdfService.generarReporte(
          ReportePdfPayload(
            ubicacionId: destino.id,
            nombreUbicacion: destino.nombreUbicacion,
            fechaHora: fechaHoraReporte,
            tipoNotificacion: encuesta.tipoNotificacion.label,
            personaNotificada: encuesta.personaNotificada.label,
            direccion: direccion,
            latitud: miUbicacionActual.latitude,
            longitud: miUbicacionActual.longitude,
            notificadorNombre: usuarioActual.nombre,
            notificadorEmail: usuarioActual.email,
            descripcionDiligencia: encuesta.descripcionDiligencia,
            fotoMapaBytes: mapaCoordenadasBytes,
            fotoRegistroBytes: encuesta.fotoRegistroBytes,
            fotoRegistroSecundariaBytes: encuesta.fotoRegistroSecundariaBytes,
            esSegundaNotificacion: destino.esSegundaNotificacion,
            identificacionRpv: (destino.identificacionTecnica ?? '').toUpperCase() == 'RPV',
            identificacionOpi: (destino.identificacionTecnica ?? '').toUpperCase() == 'OPI',
            nombreFamiliarTrabajador: encuesta.nombreFamiliarTrabajador,
            cedulaFamiliarTrabajador: encuesta.cedulaFamiliarTrabajador,
            razonSocial: destino.razonSocial,
            ruc: destino.ruc,
            representanteLegal: destino.representanteLegal,
            nombreNotificadorAsignado: destino.nombreNotificador,
            cedulaNotificadorAsignado: destino.cedulaNotificador,
          ),
        );

        reporteFirestoreId = await _firestoreService.saveNotificationReport(
          ubicacionId: destino.id,
          lat: miUbicacionActual.latitude,
          lng: miUbicacionActual.longitude,
          direccion: direccion,
          tipoNotificacion: encuesta.tipoNotificacion.value,
          personaNotificada: encuesta.personaNotificada.value,
          descripcionDiligencia: encuesta.descripcionDiligencia,
          notificadorNombre: usuarioActual.nombre,
          notificadorEmail: usuarioActual.email,
          fechaHora: fechaHoraReporte,
          pdfBytes: pdfBytes,
          nombreUbicacion: destino.nombreUbicacion,
          identificacionTecnica: destino.identificacionTecnica,
          esSegundaNotificacion: destino.esSegundaNotificacion,
          nombreFamiliarTrabajador: encuesta.nombreFamiliarTrabajador,
          cedulaFamiliarTrabajador: encuesta.cedulaFamiliarTrabajador,
        );
      }

      final ReporteLlegada reporte = ReporteLlegada(
        paradaId: destino.id,
        fechaHora: fechaHoraReporte,
        distanciaLlegadaMetros: distancia,
        ubicacionLlegada: miUbicacionActual,
        tipoNotificacion: encuesta?.tipoNotificacion.label,
        personaNotificada: encuesta?.personaNotificada.label,
        descripcionDiligencia: encuesta?.descripcionDiligencia,
        reporteFirestoreId: reporteFirestoreId,
      );

      destino.completada = true;
      if (!_reportes.any((ReporteLlegada r) => r.paradaId == destino.id)) {
        _reportes.add(reporte);
        _totalReportesRemotos = _totalReportesRemotos + 1;
      }
      _ubicacionesCompletadasPorReportes.add(destino.id);
      _reconstruirMarkersParadas();
      _safeNotify();

      final int? notificadorId = usuarioActual.id;
      if (notificadorId == null) {
        _emitMessage('No se pudo identificar el notificador autenticado.');
        return;
      }

      final String observacion = encuesta == null
          ? 'Llegada registrada automaticamente (${distancia.toStringAsFixed(1)} m).'
          : 'Tipo: ${encuesta.tipoNotificacion.label} | Persona: ${encuesta.personaNotificada.label}'
              '${encuesta.descripcionDiligencia.trim().isEmpty ? '' : ' | Desc: ${encuesta.descripcionDiligencia.trim()}'}';

      try {
        await _ubicacionesRepository.registrarVisitaNotificador(
          ubicacionId: destino.id,
          notificadorId: notificadorId,
          ubicacionLlegada: miUbicacionActual,
          observacion: observacion,
        );
      } on DatabaseException catch (e) {
        // En notificador, la ubicacion puede no existir en SQLite local.
        // No bloqueamos el flujo si el informe remoto ya fue enviado.
        _emitMessage('Informe enviado. Aviso local: no se pudo guardar la visita en cache (${e.getResultCode()}).');
      }

      _emitMessage('Llegada registrada en U-${destino.id}. Informe PDF enviado al grupo.');
      await recalcularRuta();

      final bool todasCompletadas = _paradas.isNotEmpty &&
          _paradas.values.every((Parada p) => p.completada);
      if (todasCompletadas) {
        _emitMessage('Todas las ubicaciones fueron completadas. Abre el reporte.');
      }
    } on FirestoreServiceException catch (e) {
      final String suffix = (e.code ?? '').trim().isEmpty ? '' : ' (codigo: ${e.code})';
      _emitMessage('No se pudo enviar el informe PDF: ${e.message}$suffix');
    } catch (e) {
      _emitMessage('Error al registrar llegada: $e');
    } finally {
      _procesandoLlegada = false;
    }
  }

  String _nombreUbicacionSugerido({
    required String? direccion,
    required String destinoBusqueda,
  }) {
    final String direccionLimpia = (direccion ?? '').trim();
    if (direccionLimpia.isNotEmpty) {
      final List<String> partes = direccionLimpia.split(',');
      final String primera = partes.first.trim();
      if (primera.isNotEmpty) {
        return primera;
      }
    }

    final String destino = destinoBusqueda.trim();
    if (destino.isNotEmpty) {
      return destino;
    }

    return 'Ubicacion legal';
  }

  void _emitMessage(String message) {
    _messageHandler?.call(message);
  }

  bool get _tieneGrupoAsignado => usuarioActual.groupId.trim().isNotEmpty;

  bool _esErrorDeUsuarioSinGrupo(FirestoreServiceException e) {
    final String texto = '${e.message} ${e.code ?? ''}'.toLowerCase();
    return texto.contains('no tiene groupid asignado') ||
        texto.contains('no tiene grupo asignado') ||
        texto.contains('groupid vacio') ||
        texto.contains('groupid no puede estar vacio');
  }

  void _limpiarDatosRemotos() {
    if (_paradas.isEmpty &&
        _rutaIds.isEmpty &&
        _polylinesRuta.isEmpty &&
        _polylineReferenciaBusqueda == null &&
        _reportes.isEmpty &&
        _ubicacionesCompletadasPorReportes.isEmpty &&
        _ubicacionesEsperadasPorReportes.isEmpty &&
        _paradaDentroRadioLlegada.isEmpty &&
        _totalReportesRemotos == 0) {
      return;
    }

    _paradas.clear();
    _markersParadas = <Marker>{};
    _rutaIds.clear();
    _polylinesRuta = <Polyline>{};
    _polylineReferenciaBusqueda = null;
    _reportes.clear();
    _totalReportesRemotos = 0;
    _ubicacionesCompletadasPorReportes.clear();
    _ubicacionesEsperadasPorReportes.clear();
    _paradaDentroRadioLlegada.clear();
    _paradaCanceladaId = null;
    _paradaCanceladaHasta = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceSugerenciasDestino?.cancel();
    _positionSubscription?.cancel();
    _remoteLocationSubscription?.cancel();
    _remoteReportsSubscription?.cancel();
    _remotePollingTimer?.cancel();
    _verificacionLlegadaTimer?.cancel();
    _mapController?.dispose();
    _flutterMapController = null;
    super.dispose();
  }
}

class _CandidataLlegada {
  const _CandidataLlegada({
    required this.parada,
    required this.distanciaMetros,
    required this.recienEntroAlRadio,
  });

  final Parada parada;
  final double distanciaMetros;
  final bool recienEntroAlRadio;
}

