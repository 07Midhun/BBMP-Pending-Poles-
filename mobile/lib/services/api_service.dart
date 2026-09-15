import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pole_model.dart';

class ApiService {
  // Backend running on the PC.
  // This IP successfully responds from your PC.
  static String activeBaseUrl =
      'http://192.168.3.149:8000/api/v1';

  static List<String> get _candidateUrls {
    if (kIsWeb) {
      return [
        // Main PC Ethernet IP.
        'http://192.168.3.149:8000/api/v1',

        // PC Wi-Fi IP, kept as a fallback.
        'http://192.168.9.244:8000/api/v1',

        // Localhost fallbacks for Flutter Web.
        'http://localhost:8000/api/v1',
        'http://127.0.0.1:8000/api/v1',

        // Previous possible network address.
        'http://10.150.197.63:8000/api/v1',
      ];
    }

    // Android physical phone.
    return [
      // Main PC Ethernet IP.
      'http://192.168.3.149:8000/api/v1',

      // PC Wi-Fi IP.
      'http://192.168.9.244:8000/api/v1',

      // Android emulator address.
      'http://10.0.2.2:8000/api/v1',

      // Localhost fallbacks.
      'http://localhost:8000/api/v1',
      'http://127.0.0.1:8000/api/v1',
    ];
  }

  /// Checks whether the backend root endpoint is reachable.
  ///
  /// The FastAPI backend exposes:
  /// GET /
  static Future<bool> checkHealth() async {
    for (final url in _candidateUrls) {
      final rootUrl = url.replaceFirst('/api/v1', '');

      try {
        final response = await http
            .get(Uri.parse(rootUrl))
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          activeBaseUrl = url;
          return true;
        }
      } catch (_) {
        // Try the next candidate URL.
      }
    }

    return false;
  }

  static String _serverError(
    http.Response response,
    String fallback,
  ) {
    try {
      final decoded = json.decode(response.body);

      if (decoded is Map<String, dynamic> &&
          decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Ignore JSON parsing errors.
    }

    return '$fallback (HTTP ${response.statusCode})';
  }

  static Future<List<String>> fetchRegions() async {
    try {
      final response = await http
          .get(Uri.parse('$activeBaseUrl/regions'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return List<String>.from(
          data['regions'] ?? const [],
        );
      }
    } catch (_) {
      // Return an empty list if the request fails.
    }

    return [];
  }

  static Future<List<String>> fetchZones(String? region) async {
    try {
      final url = region != null && region.isNotEmpty
          ? '$activeBaseUrl/zones?region=${Uri.encodeComponent(region)}'
          : '$activeBaseUrl/zones';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return List<String>.from(
          data['zones'] ?? const [],
        );
      }
    } catch (_) {
      // Return an empty list if the request fails.
    }

    return [];
  }

  static Future<List<String>> fetchWards(
    String? region,
    String zone,
  ) async {
    try {
      final regionParam =
          region != null && region.isNotEmpty
              ? 'region=${Uri.encodeComponent(region)}&'
              : '';

      final url =
          '$activeBaseUrl/wards?${regionParam}zone=${Uri.encodeComponent(zone)}';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return List<String>.from(
          data['wards'] ?? const [],
        );
      }
    } catch (_) {
      // Return an empty list if the request fails.
    }

    return [];
  }

  /// Fetches lamp types available for the selected hierarchy.
  ///
  /// Backend filters:
  /// - region
  /// - zone
  /// - ward
  /// - pole_old_lamp
  static Future<List<String>> fetchLampTypes({
    String? region,
    String? zone,
    String? ward,
    required String poleOldLamp,
  }) async {
    final queryParameters = <String, String>{
      'pole_old_lamp': poleOldLamp,
    };

    if (region != null && region.trim().isNotEmpty) {
      queryParameters['region'] = region.trim();
    }

    if (zone != null && zone.trim().isNotEmpty) {
      queryParameters['zone'] = zone.trim();
    }

    if (ward != null && ward.trim().isNotEmpty) {
      queryParameters['ward'] = ward.trim();
    }

    final uri = Uri.parse(
      '$activeBaseUrl/lamp-types',
    ).replace(
      queryParameters: queryParameters,
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        _serverError(
          response,
          'Unable to load lamp types',
        ),
      );
    }

    final data = json.decode(response.body);

    if (data is! Map<String, dynamic> ||
        data['lamp_types'] is! List) {
      throw Exception(
        'Invalid lamp type response from backend',
      );
    }

    return List<String>.from(data['lamp_types']);
  }

  static Future<List<Pole>> filterPendingPoles({
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
  }) async {
    final response = await http
        .post(
          Uri.parse('$activeBaseUrl/poles/filter'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'region': region,
            'zone': zone,
            'ward': ward,
            'pole_old_lamp': poleOldLamp,
            'lamp_type': lampType,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
        _serverError(
          response,
          'Unable to filter pending poles',
        ),
      );
    }

    final data = json.decode(response.body);

    if (data is! Map<String, dynamic> ||
        data['poles'] is! List) {
      throw Exception(
        'Invalid pending-pole response from backend',
      );
    }

    return (data['poles'] as List)
        .whereType<Map>()
        .map(
          (item) => Pole.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<List<Pole>> calculateDistance({
    required String startingPoleNumber,
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
  }) async {
    final response = await http
        .post(
          Uri.parse(
            '$activeBaseUrl/poles/calculate-distance',
          ),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'starting_pole_number': startingPoleNumber,
            'region': region,
            'zone': zone,
            'ward': ward,
            'pole_old_lamp': poleOldLamp,
            'lamp_type': lampType,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
        _serverError(
          response,
          'Unable to calculate pole distances',
        ),
      );
    }

    final data = json.decode(response.body);

    if (data is! Map<String, dynamic> ||
        data['poles'] is! List) {
      throw Exception(
        'Invalid distance response from backend',
      );
    }

    return (data['poles'] as List)
        .whereType<Map>()
        .map(
          (item) => Pole.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  /// Looks up one pole directly in Schnell IoT / ThingsBoard.
  ///
  /// Returns the raw IoT pole information when found.
  /// Returns null when the pole is not found or the request fails.
  static Future<Map<String, dynamic>?> fetchSchnellIoTPole(
    String poleNumber,
  ) async {
    try {
      final encodedPoleNumber =
          Uri.encodeComponent(poleNumber);

      final response = await http
          .get(
            Uri.parse(
              '$activeBaseUrl/schnell-iot/pole/$encodedPoleNumber',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map<String, dynamic> &&
            data['matched'] == true &&
            data['pole'] is Map) {
          return Map<String, dynamic>.from(
            data['pole'] as Map,
          );
        }
      }
    } catch (_) {
      // Return null if the request fails.
    }

    return null;
  }

  /// Looks up multiple poles in Schnell IoT / ThingsBoard.
  ///
  /// The returned map is keyed by pole number.
  static Future<Map<String, Map<String, dynamic>>>
      fetchSchnellIoTPoles(
    List<String> poleNumbers,
  ) async {
    if (poleNumbers.isEmpty) {
      return {};
    }

    try {
      final response = await http
          .post(
            Uri.parse(
              '$activeBaseUrl/schnell-iot/poles',
            ),
            headers: {
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'pole_numbers': poleNumbers,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        return {};
      }

      final data = json.decode(response.body);

      if (data is! Map<String, dynamic> ||
          data['poles'] is! List) {
        return {};
      }

      final Map<String, Map<String, dynamic>> results = {};

      for (final item in data['poles']) {
        if (item is! Map) {
          continue;
        }

        final poleNumber = item['pole_number'];

        if (poleNumber is! String ||
            poleNumber.isEmpty) {
          continue;
        }

        results[poleNumber] =
            Map<String, dynamic>.from(item);
      }

      return results;
    } catch (_) {
      return {};
    }
  }
}