import 'dart:math';

class Haversine {
  /// Calculates the great-circle distance between two points 
  /// on the Earth using their latitude and longitude in decimal degrees.
  /// Returns distance in meters.
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0; // Earth radius in meters

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180.0;
  }
}
