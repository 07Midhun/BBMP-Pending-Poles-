class Pole {
  final String id;
  final String poleNumber;
  final String region;
  final String zone;
  final String ward;
  final String poleOldLamp;
  final String lampType;
  final double latitude;
  final double longitude;

  double? distanceMeters;
  int? order;

  Pole({
    required this.id,
    required this.poleNumber,
    required this.region,
    required this.zone,
    required this.ward,
    required this.poleOldLamp,
    required this.lampType,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.order,
  });

  /// Creates a copy of the pole while allowing calculated
  /// values such as distance and order to be changed.
  Pole copyWith({
    String? id,
    String? poleNumber,
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
    double? latitude,
    double? longitude,
    double? distanceMeters,
    int? order,
  }) {
    return Pole(
      id: id ?? this.id,
      poleNumber: poleNumber ?? this.poleNumber,
      region: region ?? this.region,
      zone: zone ?? this.zone,
      ward: ward ?? this.ward,
      poleOldLamp: poleOldLamp ?? this.poleOldLamp,
      lampType: lampType ?? this.lampType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pole_number': poleNumber,
      'region': region,
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

  factory Pole.fromJson(Map<String, dynamic> json) {
    return Pole(
      id: json['id']?.toString() ?? '',
      poleNumber: json['pole_number']?.toString() ??
          json['poleNumber']?.toString() ??
          '',
      region: json['region']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      ward: json['ward']?.toString() ?? '',
      poleOldLamp: json['pole_old_lamp']?.toString() ??
          json['poleOldLamp']?.toString() ??
          '',
      lampType: json['lamp_type']?.toString() ??
          json['lampType']?.toString() ??
          '',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      distanceMeters: json['distance_meters'] != null
          ? _toDouble(json['distance_meters'])
          : null,
      order: json['order'] != null
          ? int.tryParse(json['order'].toString())
          : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Distance displayed in the result table.
  String get distanceFormatted {
    if (distanceMeters == null) {
      return '-';
    }

    final distance = distanceMeters!;

    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    }

    return '${(distance / 1000).toStringAsFixed(2)} km';
  }

  /// Google Maps URL for this pole.
  String get googleMapsUrl {
    return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
  }
}
