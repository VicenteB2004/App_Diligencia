import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class MapSnapshotService {
  MapSnapshotService({
    http.Client? httpClient,
    String? staticMapsApiKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _staticMapsApiKey = staticMapsApiKey ?? '';

  final http.Client _httpClient;
  final String _staticMapsApiKey;

  Future<Uint8List?> obtenerMapaEstatico({
    required double lat,
    required double lng,
    int width = 800,
    int height = 450,
    int zoom = 17,
  }) async {
    final Uint8List? googleConKey = await _descargarGoogleStaticMap(
      lat: lat,
      lng: lng,
      width: width,
      height: height,
      zoom: zoom,
      includeKey: true,
    );
    if (googleConKey != null) {
      return googleConKey;
    }

    final Uint8List? googleSinKey = await _descargarGoogleStaticMap(
      lat: lat,
      lng: lng,
      width: width,
      height: height,
      zoom: zoom,
      includeKey: false,
    );
    if (googleSinKey != null) {
      return googleSinKey;
    }

    final Uint8List? osmStatic = await _descargarOsmStaticMap(
      lat: lat,
      lng: lng,
      width: width,
      height: height,
      zoom: zoom,
    );
    if (osmStatic != null) {
      return osmStatic;
    }

    return _construirMapaLocalConTeselas(
      lat: lat,
      lng: lng,
      width: width,
      height: height,
      zoom: zoom,
    );
  }

  Future<Uint8List?> _descargarGoogleStaticMap({
    required double lat,
    required double lng,
    required int width,
    required int height,
    required int zoom,
    required bool includeKey,
  }) async {
    final String key = _staticMapsApiKey.trim();
    if (includeKey && key.isEmpty) {
      return null;
    }

    final String marker = 'color:red|$lat,$lng';
    final Map<String, String> query = <String, String>{
      'center': '$lat,$lng',
      'zoom': '$zoom',
      'size': '${width}x$height',
      'maptype': 'roadmap',
      'markers': marker,
      'format': 'png',
      if (includeKey) 'key': key,
    };

    final Uri uri = Uri.https('maps.googleapis.com', '/maps/api/staticmap', query);
    return _descargarImagen(uri);
  }

  Future<Uint8List?> _descargarOsmStaticMap({
    required double lat,
    required double lng,
    required int width,
    required int height,
    required int zoom,
  }) async {
    final int safeWidth = width.clamp(100, 1200);
    final int safeHeight = height.clamp(100, 1200);
    final Map<String, String> query = <String, String>{
      'center': '$lat,$lng',
      'zoom': '$zoom',
      'size': '${safeWidth}x$safeHeight',
      'maptype': 'mapnik',
      'markers': '$lat,$lng,red-pushpin',
    };

    final Uri uri = Uri.https('staticmap.openstreetmap.de', '/staticmap.php', query);
    return _descargarImagen(uri);
  }

  Future<Uint8List?> _descargarImagen(Uri uri) async {
    try {
      const int maxIntentos = 2;
      for (int intento = 1; intento <= maxIntentos; intento++) {
        try {
          final http.Response response = await _httpClient.get(uri).timeout(
                const Duration(seconds: 15),
              );
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final String contentType = response.headers['content-type']?.toLowerCase() ?? '';
            final bool esImagenPorHeader = contentType.startsWith('image/');
            final bool esImagenPorFirma = _looksLikeImage(response.bodyBytes);
            if (esImagenPorHeader || esImagenPorFirma) {
              return response.bodyBytes;
            }
          }
        } catch (_) {
          if (intento < maxIntentos) {
            await Future<void>.delayed(Duration(milliseconds: 500 * intento));
            continue;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _construirMapaLocalConTeselas({
    required double lat,
    required double lng,
    required int width,
    required int height,
    required int zoom,
  }) async {
    final int safeWidth = width.clamp(100, 1200);
    final int safeHeight = height.clamp(100, 1200);
    const int tileSize = 256;
    const String tileHost = 'tile.openstreetmap.org';

    final _TileCoordinate centro = _latLngToTileCoordinate(lat: lat, lng: lng, zoom: zoom);

    final int tilesX = (safeWidth / tileSize).ceil() + 2;
    final int tilesY = (safeHeight / tileSize).ceil() + 2;
    final int startX = centro.x.floor() - (tilesX ~/ 2);
    final int startY = centro.y.floor() - (tilesY ~/ 2);

    final img.Image canvas = img.Image(
      width: tilesX * tileSize,
      height: tilesY * tileSize,
      numChannels: 4,
    );

    for (int row = 0; row < tilesY; row++) {
      for (int col = 0; col < tilesX; col++) {
        final int tileX = startX + col;
        final int tileY = startY + row;
        if (tileY < 0 || tileY >= (1 << zoom)) {
          continue;
        }

        final int wrappedTileX = _wrapTileX(tileX, zoom);
        final Uri tileUri = Uri.https(tileHost, '/$zoom/$wrappedTileX/$tileY.png');
        final Uint8List? tileBytes = await _descargarImagen(tileUri);
        final img.Image? tileImage = tileBytes == null ? null : img.decodeImage(tileBytes);
        if (tileImage == null) {
          continue;
        }

        img.compositeImage(
          canvas,
          tileImage,
          dstX: col * tileSize,
          dstY: row * tileSize,
        );
      }
    }

    final int centerPxX = ((centro.x - startX) * tileSize).round();
    final int centerPxY = ((centro.y - startY) * tileSize).round();
    final int cropLeft = (centerPxX - (safeWidth / 2).round()).clamp(0, canvas.width - safeWidth);
    final int cropTop = (centerPxY - (safeHeight / 2).round()).clamp(0, canvas.height - safeHeight);

    final img.Image recorte = img.copyCrop(
      canvas,
      x: cropLeft,
      y: cropTop,
      width: safeWidth,
      height: safeHeight,
    );

    final int puntoX = (safeWidth / 2).round();
    final int puntoY = (safeHeight / 2).round();
    final img.Color rojo = img.ColorRgba8(229, 57, 53, 255);
    final img.Color blanco = img.ColorRgba8(255, 255, 255, 255);

    img.fillCircle(recorte, x: puntoX, y: puntoY, radius: 8, color: rojo);
    img.drawCircle(recorte, x: puntoX, y: puntoY, radius: 11, color: blanco);
    img.fillCircle(recorte, x: puntoX, y: puntoY, radius: 3, color: blanco);

    return Uint8List.fromList(img.encodePng(recorte));
  }

  _TileCoordinate _latLngToTileCoordinate({
    required double lat,
    required double lng,
    required int zoom,
  }) {
    final double latRad = lat * (math.pi / 180.0);
    final double n = (1 << zoom).toDouble();
    final double x = (lng + 180.0) / 360.0 * n;
    final double y = (1.0 - (math.log(math.tan(latRad) + (1 / math.cos(latRad))) / math.pi)) / 2.0 * n;
    return _TileCoordinate(x: x, y: y);
  }

  int _wrapTileX(int tileX, int zoom) {
    final int max = 1 << zoom;
    return ((tileX % max) + max) % max;
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) {
      return false;
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }

    return false;
  }
}

class _TileCoordinate {
  const _TileCoordinate({required this.x, required this.y});

  final double x;
  final double y;
}
