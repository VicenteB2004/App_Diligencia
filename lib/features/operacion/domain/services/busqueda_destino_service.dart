import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:notificador/features/operacion/domain/entities/resultado_busqueda_destino.dart';
import 'package:notificador/features/operacion/domain/entities/sugerencia_destino.dart';

class BusquedaDestinoService {
  static const Duration _kHttpTimeout = Duration(seconds: 7);
  static const Map<String, String> _kNominatimHeaders = <String, String>{
    'User-Agent': 'notificador-windows-app/1.0',
  };

  const BusquedaDestinoService({
    this.googlePlacesApiKey = const String.fromEnvironment('GOOGLE_PLACES_API_KEY'),
  });

  final String googlePlacesApiKey;

  String normalizarEntrada(String raw) {
    final String normalizada = raw
        .replaceAll(RegExp(r'\s*&\s*'), ' y ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalizada;
  }

  LatLng? parseLatLng(String raw) {
    final RegExp regex = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[,;]\s*(-?\d+(?:\.\d+)?)\s*$',
    );
    final Match? match = regex.firstMatch(raw);
    if (match == null) {
      return null;
    }

    final double? lat = double.tryParse(match.group(1)!);
    final double? lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) {
      return null;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return null;
    }

    return LatLng(lat, lng);
  }

  Future<ResultadoBusquedaDestino> resolverDestino(
    String input, {
    bool busquedaExacta = false,
  }) async {
    final String consulta = normalizarEntrada(input);
    if (consulta.isEmpty) {
      return const ResultadoBusquedaDestino.error(
        'Escribe una direccion, lugar o coordenadas para enfocar el mapa.',
      );
    }

    final LatLng? coord = parseLatLng(consulta);
    if (coord != null) {
      return ResultadoBusquedaDestino.ok(
        posicion: coord,
        fueCoordenada: true,
      );
    }

    final _PlaceSearchMatch? lugarGoogle = await _buscarConGooglePlaces(consulta);
    if (lugarGoogle != null) {
      final List<geocoding.Location> resultadosReferencia =
          await _buscarUbicacionesTolerante(lugarGoogle.direccionConsulta);
      final List<LatLng> trazadoReferencia = _trazadoReferenciaDesdeResultados(
        resultados: resultadosReferencia,
        puntoSeleccionado: lugarGoogle.posicion,
      );

      return ResultadoBusquedaDestino.ok(
        posicion: lugarGoogle.posicion,
        fueCoordenada: false,
        mensajeInfo: lugarGoogle.mensajeInfo,
        trazadoReferencia: trazadoReferencia,
      );
    }

    final _PlaceSearchMatch? lugarNominatim = await _buscarConNominatim(consulta);
    if (lugarNominatim != null) {
      return ResultadoBusquedaDestino.ok(
        posicion: lugarNominatim.posicion,
        fueCoordenada: false,
        mensajeInfo: lugarNominatim.mensajeInfo,
      );
    }

    try {
      final List<geocoding.Location> resultados = await _buscarUbicacionesTolerante(consulta);
      if (resultados.isEmpty) {
        final String? pistaDesktop = googlePlacesApiKey.trim().isEmpty
            ? ' En desktop, activa GOOGLE_PLACES_API_KEY para mejorar resultados de direcciones complejas.'
            : null;
        return ResultadoBusquedaDestino.error(
          'No encontramos ese destino. Prueba con un termino mas especifico.${pistaDesktop ?? ''}',
        );
      }

      geocoding.Location seleccion = resultados.first;
      String? mensajeInfo;

      if (busquedaExacta && resultados.length > 1) {
        seleccion = await _elegirMejorCoincidencia(
          consulta: consulta,
          candidatos: resultados,
        );
        mensajeInfo = 'Mostrando la coincidencia mas cercana para "$consulta".';
      }

      if (busquedaExacta) {
        // Validamos contra la coincidencia seleccionada, no siempre contra el primer resultado.
        final geocoding.Placemark? placemark = await _placemarkSeguro(seleccion);
        final String direccionResuelta = _direccionCompacta(placemark).toLowerCase();
        final bool coincide = _tokensDireccion(consulta).every(
          (String token) => direccionResuelta.contains(token),
        );
        if (!coincide) {
          seleccion = await _elegirMejorCoincidencia(
            consulta: consulta,
            candidatos: resultados,
          );
          mensajeInfo = 'No fue exacta, pero te mostramos una ubicacion cercana.';
        }
      }

      final LatLng posicionSeleccionada = LatLng(seleccion.latitude, seleccion.longitude);
      final List<LatLng> trazadoReferencia = _trazadoReferenciaDesdeResultados(
        resultados: resultados,
        puntoSeleccionado: posicionSeleccionada,
      );

      return ResultadoBusquedaDestino.ok(
        posicion: posicionSeleccionada,
        fueCoordenada: false,
        mensajeInfo: mensajeInfo,
        trazadoReferencia: trazadoReferencia,
      );
    } on PlatformException catch (e) {
      return ResultadoBusquedaDestino.error(
        'Error del servicio de geocodificacion (${e.code}). Verifica internet y permisos.',
      );
    } catch (_) {
      return const ResultadoBusquedaDestino.error(
        'No se pudo resolver la ubicacion en este momento.',
      );
    }
  }

  List<LatLng> _trazadoReferenciaDesdeResultados({
    required List<geocoding.Location> resultados,
    required LatLng puntoSeleccionado,
  }) {
    final List<LatLng> candidatos = resultados
        .take(10)
        .map((geocoding.Location loc) => LatLng(loc.latitude, loc.longitude))
        .where((LatLng p) => _distanciaMetros(p, puntoSeleccionado) <= 450)
        .toList();

    final List<LatLng> puntos = _deduplicarPuntos(candidatos);
    if (puntos.length < 2) {
      return const <LatLng>[];
    }

    final double minLat = puntos.map((LatLng p) => p.latitude).reduce((double a, double b) => a < b ? a : b);
    final double maxLat = puntos.map((LatLng p) => p.latitude).reduce((double a, double b) => a > b ? a : b);
    final double minLng = puntos.map((LatLng p) => p.longitude).reduce((double a, double b) => a < b ? a : b);
    final double maxLng = puntos.map((LatLng p) => p.longitude).reduce((double a, double b) => a > b ? a : b);

    final bool ordenarPorLat = (maxLat - minLat).abs() >= (maxLng - minLng).abs();
    puntos.sort((LatLng a, LatLng b) {
      return ordenarPorLat
          ? a.latitude.compareTo(b.latitude)
          : a.longitude.compareTo(b.longitude);
    });

    return puntos;
  }

  List<LatLng> _deduplicarPuntos(List<LatLng> puntos) {
    final Set<String> keys = <String>{};
    final List<LatLng> deduplicados = <LatLng>[];

    for (final LatLng punto in puntos) {
      final String key =
          '${punto.latitude.toStringAsFixed(5)}|${punto.longitude.toStringAsFixed(5)}';
      if (keys.add(key)) {
        deduplicados.add(punto);
      }
    }

    return deduplicados;
  }

  double _distanciaMetros(LatLng a, LatLng b) {
    const double radioTierra = 6371000;
    final double lat1 = _degARad(a.latitude);
    final double lat2 = _degARad(b.latitude);
    final double dLat = _degARad(b.latitude - a.latitude);
    final double dLng = _degARad(b.longitude - a.longitude);

    final double hav =
        (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2));
    final double c = 2 * atan2(sqrt(hav), sqrt(1 - hav));
    return radioTierra * c;
  }

  double _degARad(double deg) => deg * (pi / 180.0);

  Future<_PlaceSearchMatch?> _buscarConGooglePlaces(String consulta) async {
    final String apiKey = googlePlacesApiKey.trim();
    if (apiKey.isEmpty) {
      return null;
    }

    final Uri uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', <String, String>{
      'query': consulta,
      'language': 'es',
      'region': 'ec',
      'key': apiKey,
    });

    try {
      final http.Response response = await http.get(uri).timeout(_kHttpTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final Map<String, dynamic> payload = jsonDecode(response.body) as Map<String, dynamic>;
      final String status = (payload['status'] as String? ?? '').trim();
      if (status == 'ZERO_RESULTS') {
        return null;
      }
      if (status != 'OK') {
        return null;
      }

      final List<Map<String, dynamic>> resultados = (payload['results'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (resultados.isEmpty) {
        return null;
      }

      final Map<String, dynamic>? primero = _seleccionarMejorResultadoGoogle(
        consulta: consulta,
        resultados: resultados,
      );
      if (primero == null) {
        return null;
      }

      final Map<String, dynamic> geometry = primero['geometry'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final Map<String, dynamic> location = geometry['location'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final double? lat = _asDouble(location['lat']);
      final double? lng = _asDouble(location['lng']);
      if (lat == null || lng == null) {
        return null;
      }

      final String direccion = (primero['formatted_address'] as String? ?? '').trim();
      final String nombre = (primero['name'] as String? ?? '').trim();
      final String direccionConsulta = direccion.isNotEmpty ? direccion : consulta;

      String? mensajeInfo;
      if (nombre.isNotEmpty && direccion.isNotEmpty) {
        mensajeInfo = 'Google Places: $nombre, $direccion';
      } else if (direccion.isNotEmpty) {
        mensajeInfo = 'Google Places: $direccion';
      }

      return _PlaceSearchMatch(
        posicion: LatLng(lat, lng),
        direccionConsulta: direccionConsulta,
        mensajeInfo: mensajeInfo,
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _seleccionarMejorResultadoGoogle({
    required String consulta,
    required List<Map<String, dynamic>> resultados,
  }) {
    final List<String> tokensConsulta = _tokensDireccion(consulta);
    Map<String, dynamic>? mejor;
    int mejorPuntaje = -1;

    for (final Map<String, dynamic> candidato in resultados.take(5)) {
      final String nombre = (candidato['name'] as String? ?? '').trim();
      final String direccion = (candidato['formatted_address'] as String? ?? '').trim();
      final String texto = '$nombre $direccion'.toLowerCase();
      final int puntaje = tokensConsulta.where((String token) => texto.contains(token)).length;
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = candidato;
      }
    }

    return mejor ?? (resultados.isNotEmpty ? resultados.first : null);
  }

  Future<List<SugerenciaDestino>> buscarSugerencias(String input, {int limite = 5}) async {
    final String apiKey = googlePlacesApiKey.trim();
    final String consulta = normalizarEntrada(input);
    if (consulta.length < 3) {
      return const <SugerenciaDestino>[];
    }

    if (apiKey.isEmpty) {
      return _buscarSugerenciasConNominatim(consulta, limite: limite);
    }

    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': consulta,
        'language': 'es',
        'components': 'country:ec',
        'key': apiKey,
      },
    );

    try {
      final http.Response response = await http.get(uri).timeout(_kHttpTimeout);
      if (response.statusCode != 200) {
        return const <SugerenciaDestino>[];
      }

      final Map<String, dynamic> payload = jsonDecode(response.body) as Map<String, dynamic>;
      final String status = (payload['status'] as String? ?? '').trim();
      if (status == 'ZERO_RESULTS') {
        return const <SugerenciaDestino>[];
      }
      if (status != 'OK') {
        return const <SugerenciaDestino>[];
      }

      final List<dynamic> predictions = payload['predictions'] as List<dynamic>? ?? <dynamic>[];
      if (predictions.isEmpty) {
        return const <SugerenciaDestino>[];
      }

      return predictions
          .whereType<Map<String, dynamic>>()
          .map(SugerenciaDestino.fromAutocompleteJson)
          .where((SugerenciaDestino s) => s.descripcion.trim().isNotEmpty)
          .take(limite)
          .toList(growable: false);
    } on TimeoutException {
      return const <SugerenciaDestino>[];
    } catch (_) {
      return const <SugerenciaDestino>[];
    }
  }

  Future<_PlaceSearchMatch?> _buscarConNominatim(String consulta) async {
    final List<String> tokensConsulta = _tokensDireccion(consulta);

    for (final String variante in _variantesConsulta(consulta)) {
      try {
        final List<Map<String, dynamic>> resultados = await _consultarNominatim(
          consulta: variante,
          limite: 3,
        );
        if (resultados.isEmpty) {
          continue;
        }

        final Map<String, dynamic> primero = _seleccionarMejorResultadoNominatim(
          resultados: resultados,
          tokensConsulta: tokensConsulta,
        );
        final double? lat = _asDouble(primero['lat']);
        final double? lng = _asDouble(primero['lon']);
        if (lat == null || lng == null) {
          continue;
        }

        final String nombre = (primero['display_name'] as String? ?? variante).trim();
        return _PlaceSearchMatch(
          posicion: LatLng(lat, lng),
          direccionConsulta: nombre,
          mensajeInfo: 'Nominatim: $nombre',
        );
      } on TimeoutException {
        // Probamos con la siguiente variante de consulta.
      } catch (_) {
        // Probamos con la siguiente variante de consulta.
      }
    }

    return null;
  }

  Future<List<SugerenciaDestino>> _buscarSugerenciasConNominatim(
    String consulta, {
    required int limite,
  }) async {
    try {
      final List<Map<String, dynamic>> payload = await _consultarNominatim(
        consulta: consulta,
        limite: limite,
      );
      return payload
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> item) {
            final String descripcion = (item['display_name'] as String? ?? '').trim();
            final String placeId = (item['place_id'] as Object?)?.toString() ?? descripcion;
            return SugerenciaDestino(
              placeId: placeId,
              descripcion: descripcion,
              textoPrincipal: descripcion.split(',').first.trim(),
              textoSecundario: descripcion,
            );
          })
          .where((SugerenciaDestino s) => s.descripcion.isNotEmpty)
          .take(limite)
          .toList(growable: false);
    } on TimeoutException {
      return const <SugerenciaDestino>[];
    } catch (_) {
      return const <SugerenciaDestino>[];
    }
  }

  Future<List<Map<String, dynamic>>> _consultarNominatim({
    required String consulta,
    required int limite,
  }) async {
    final String query = consulta.toLowerCase().contains('ecuador')
        ? consulta
        : '$consulta, Ecuador';
    final Uri uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      <String, String>{
        'q': query,
        'format': 'jsonv2',
        'limit': limite.toString(),
        'addressdetails': '1',
      },
    );

    final http.Response response =
        await http.get(uri, headers: _kNominatimHeaders).timeout(_kHttpTimeout);
    if (response.statusCode != 200) {
      return const <Map<String, dynamic>>[];
    }

    final List<dynamic> payload = jsonDecode(response.body) as List<dynamic>;
    return payload.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic> _seleccionarMejorResultadoNominatim({
    required List<Map<String, dynamic>> resultados,
    required List<String> tokensConsulta,
  }) {
    Map<String, dynamic> mejor = resultados.first;
    int mejorPuntaje = -1;

    for (final Map<String, dynamic> candidato in resultados.take(5)) {
      final String nombre = (candidato['display_name'] as String? ?? '').toLowerCase();
      final int puntaje = tokensConsulta.where((String token) => nombre.contains(token)).length;
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = candidato;
      }
    }

    return mejor;
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  Future<List<geocoding.Location>> _buscarUbicacionesTolerante(String consulta) async {
    final List<String> intentos = _variantesConsulta(consulta);
    for (final String intento in intentos) {
      try {
        final List<geocoding.Location> resultados = await geocoding.locationFromAddress(intento);
        if (resultados.isNotEmpty) {
          return resultados;
        }
      } catch (_) {
        // Intenta la siguiente variante de texto.
      }
    }
    return const <geocoding.Location>[];
  }

  List<String> _variantesConsulta(String consulta) {
    final String base = normalizarEntrada(consulta);
    final Set<String> variantes = <String>{base};

    variantes.add(base.replaceAll(RegExp(r'\s+y\s+', caseSensitive: false), ' & '));

    final String sinPuntuacion =
        base.replaceAll(RegExp(r'[^\p{L}0-9\s]', unicode: true), ' ');
    variantes.add(normalizarEntrada(sinPuntuacion));

    final String sinAcentos = _removerDiacriticos(base);
    variantes.add(normalizarEntrada(sinAcentos));

    final String compacta = normalizarEntrada(
      sinAcentos.replaceAll(RegExp(r'\b(de|del|la|las|los)\b', caseSensitive: false), ' '),
    );
    if (compacta.isNotEmpty) {
      variantes.add(compacta);
    }

    final List<String> tokens = _tokensDireccion(base);
    if (tokens.length >= 3) {
      variantes.add('${tokens.take(3).join(' ')}, Ecuador');
      variantes.add(tokens.take(4).join(' '));
    }

    variantes.add('$base, Ecuador');
    return variantes.where((String s) => s.trim().isNotEmpty).toList();
  }

  Future<geocoding.Location> _elegirMejorCoincidencia({
    required String consulta,
    required List<geocoding.Location> candidatos,
  }) async {
    final List<String> tokensConsulta = _tokensDireccion(consulta.toLowerCase());
    geocoding.Location mejor = candidatos.first;
    int mejorPuntaje = -1;

    for (final geocoding.Location candidato in candidatos.take(6)) {
      final geocoding.Placemark? placemark = await _placemarkSeguro(candidato);
      final String direccion = _direccionCompacta(placemark).toLowerCase();
      final int puntaje = tokensConsulta.where((String token) => direccion.contains(token)).length;
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = candidato;
      }
    }

    return mejor;
  }

  Future<geocoding.Placemark?> _placemarkSeguro(geocoding.Location location) async {
    try {
      final List<geocoding.Placemark> places = await geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (places.isEmpty) {
        return null;
      }
      return places.first;
    } catch (_) {
      return null;
    }
  }

  String _direccionCompacta(geocoding.Placemark? placemark) {
    if (placemark == null) {
      return '';
    }
    final List<String> partes = <String>[
      placemark.street ?? '',
      placemark.subLocality ?? '',
      placemark.locality ?? '',
      placemark.administrativeArea ?? '',
      placemark.country ?? '',
    ];
    return partes.map((String p) => p.trim()).where((String p) => p.isNotEmpty).join(' ');
  }

  List<String> _tokensDireccion(String consulta) {
    return _removerDiacriticos(consulta)
        .toLowerCase()
        .split(RegExp(r'[^\p{L}0-9]+', unicode: true))
        .where((String token) => token.length >= 3 || RegExp(r'^\d+$').hasMatch(token))
        .toList();
  }

  String _removerDiacriticos(String texto) {
    const Map<String, String> mapa = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
      'ñ': 'n',
      'Ñ': 'N',
    };

    final StringBuffer out = StringBuffer();
    for (int i = 0; i < texto.length; i++) {
      final String ch = texto[i];
      out.write(mapa[ch] ?? ch);
    }
    return out.toString();
  }
}

class _PlaceSearchMatch {
  const _PlaceSearchMatch({
    required this.posicion,
    required this.direccionConsulta,
    required this.mensajeInfo,
  });

  final LatLng posicion;
  final String direccionConsulta;
  final String? mensajeInfo;
}

