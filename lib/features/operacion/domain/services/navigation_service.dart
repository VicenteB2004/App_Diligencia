import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationService {
  const NavigationService();

  Future<bool> abrirNavegacion({
    required LatLng destino,
    LatLng? origen,
  }) async {
    final String destinoCoords = '${destino.latitude},${destino.longitude}';

    final Map<String, String> params = <String, String>{
      'api': '1',
      'destination': destinoCoords,
      'travelmode': 'driving',
      'dir_action': 'navigate',
    };

    if (origen != null) {
      params['origin'] = '${origen.latitude},${origen.longitude}';
    }

    final List<Uri> candidatos = <Uri>[
      Uri.https('www.google.com', '/maps/dir/', params),
      Uri.parse('google.navigation:q=$destinoCoords&mode=d'),
      Uri.parse('geo:0,0?q=$destinoCoords'),
    ];

    for (final Uri uri in candidatos) {
      if (await _intentarAbrir(uri)) {
        return true;
      }
    }

    return false;
  }

  Future<bool> _intentarAbrir(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

