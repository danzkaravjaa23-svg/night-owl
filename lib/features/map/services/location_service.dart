import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  final String message;
  const LocationFailure(this.message);
}

/// Location is requested only after the user taps the location button.
class LocationService {
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('Төхөөрөмжийн байршлын үйлчилгээг асаана уу.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('Тохиргооноос Night Owl-ийн байршлын зөвшөөрлийг нээнэ үү.');
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('Байршлын зөвшөөрөл олгоогүй байна. Газруудыг хайж болно.');
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 15));
    } catch (_) {
      throw const LocationFailure('Байршил авч чадсангүй. Сүлжээ болон зөвшөөрлөө шалгана уу.');
    }
  }
}
