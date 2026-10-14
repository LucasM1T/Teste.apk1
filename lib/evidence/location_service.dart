import 'package:geolocator/geolocator.dart';

class LocationService {
  /// GPS puro funciona sem internet (só o A-GPS demora mais no primeiro fix).
  static Future<Position> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('GPS desligado');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('Permissão de localização negada');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        forceLocationManager: true, // LocationManager/GPS direto, sem depender do Google Play Services
        timeLimit: const Duration(seconds: 25),
      ),
    );
    // position.latitude, .longitude, .accuracy (m), .altitude (m)
  }
}
