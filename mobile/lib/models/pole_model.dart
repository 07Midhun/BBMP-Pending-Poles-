import 'dart:math';

class Pole {
  final int id;
  final String poleNumber;
  final String zone;
  final String ward;
  final String poleOldLamp; // LED, Non-LED, Empty
  final String lampType; // LED, FLED, LED-FLED, LED-LED, CFL, Sodium, Halogen, Tube, -, Blank
  final double latitude;
  final double longitude;
  double? distanceMeters;
  int? order;

  Pole({
    required this.id,
    required this.poleNumber,
    required this.zone,
    required this.ward,
    required this.poleOldLamp,
    required this.lampType,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.order,
  });

  String get distanceFormatted {
    if (distanceMeters == null) return "-";
    if (distanceMeters! >= 1000.0) {
      return "${(distanceMeters! / 1000.0).toStringAsFixed(2)} km";
    }
    return "${distanceMeters!.round()} m";
  }

  String get googleMapsUrl {
    return "https://www.google.com/maps/search/?api=1&query=$latitude,$longitude";
  }

  factory Pole.fromJson(Map<String, dynamic> json) {
    return Pole(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      poleNumber: json['pole_number'] ?? json['poleNumber'] ?? '',
      zone: json['zone'] ?? '',
      ward: json['ward'] ?? '',
      poleOldLamp: json['pole_old_lamp'] ?? json['poleOldLamp'] ?? '',
      lampType: json['lamp_type'] ?? json['lampType'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceMeters: json['distance_meters'] != null ? (json['distance_meters'] as num).toDouble() : null,
      order: json['order'] != null ? (json['order'] as num).toInt() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pole_number': poleNumber,
      'zone': zone,
      'ward': ward,
      'pole_old_lamp': poleOldLamp,
      'lamp_type': lampType,
      'latitude': latitude,
      'longitude': longitude,
      'distance_meters': distanceMeters,
      'order': order,
    };
  }
}
