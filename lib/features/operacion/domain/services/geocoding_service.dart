import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeocodingService {
  const GeocodingService();

  Future<String?> direccionDesdeCoordenadas(LatLng posicion) async {
    try {
      final List<geocoding.Placemark> places = await geocoding.placemarkFromCoordinates(
        posicion.latitude,
        posicion.longitude,
      );
      if (places.isEmpty) {
        return null;
      }

      final geocoding.Placemark p = places.first;
      final List<String> partes = <String>[
        if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.country ?? '').trim().isNotEmpty) p.country!.trim(),
      ];
      if (partes.isEmpty) {
        return null;
      }
      return partes.join(', ');
    } catch (_) {
      return null;
    }
  }
}

