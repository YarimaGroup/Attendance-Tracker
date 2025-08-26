import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class GeolocationService {
  Future<Position> getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw PermissionDeniedException('Location services are disabled.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw PermissionDeniedException('Please allow location to punch.');
    }

    try {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) return lastPosition;
    } catch (_) {}

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 25),
    );
  }

  Future<String> addressFromPosition(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[];
        if (place.name?.isNotEmpty == true && place.name != place.street) {
          parts.add(place.name!);
        }
        if (place.street?.isNotEmpty == true) parts.add(place.street!);
        if (place.subLocality?.isNotEmpty == true) {
          parts.add(place.subLocality!);
        }
        if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
        if (place.administrativeArea?.isNotEmpty == true) {
          parts.add(place.administrativeArea!);
        }
        if (place.postalCode?.isNotEmpty == true) parts.add(place.postalCode!);
        if (parts.isNotEmpty) return parts.take(3).join(', ');
      }
    } catch (_) {}
    return 'Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }
}
