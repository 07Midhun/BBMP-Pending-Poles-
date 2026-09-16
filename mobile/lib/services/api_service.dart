import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pole_model.dart';

class ApiService {
  /// Live backend deployed on Render.
  ///
  /// This URL is used by the Android mobile app and Flutter Web app.
  static String activeBaseUrl =
      'https://bbmp-pending-poles-6.onrender.com/';

  /// Backend URLs tried by the application.
  ///
  /// The live Render backend is always tried first.
  /// Local URLs are kept only for local development.
  static List<String> get _candidateUrls {
    return [
      // Production backend.
      'https://bbmp-pending-poles-2.onrender.com/api/v1',

      // Local development fallbacks.
      if (kIsWeb) ...[
        if (Uri.base.host.isNotEmpty)
          'http://${Uri.base.host}:8000/api/v1',
        'http://localhost:8000/api/v1',
        'http://127.0.0.1:8000/api/v1',
      ] else ...[
        // Android emulator.
        'http://10.0.2.2:8000/api/v1',

        // Local computer IP address.
        'http://10.150.197.63:8000/api/v1',

        // Android physical-device fallback.
        'http://localhost:8000/api/v1',
      ],
    ];
  }

  /// Checks whether the backend root endpoint is reachable.
  ///
  /// The FastAPI backend exposes GET /.
  /// Therefore, /api/v1 is removed before checking the root endpoint.
  static Future<bool> checkHealth() async {
    for (final url in _candidateUrls) {
      final rootUrl = url.replaceFirst('/api/v1', '');

      try {
        debugPrint('Checking backend: $rootUrl');

        final response = await http
            .get(Uri.parse(rootUrl))
            .timeout(const Duration(seconds: 10));

        debugPrint(
          'Backend response: ${response.statusCode} ${response.body}',
        );

        if (response.statusCode == 200) {
          activeBaseUrl = url;

          debugPrint(
            'Backend connected successfully using: $activeBaseUrl',
          );

          return true;
        }
      } catch (error) {
        debugPrint(
          'Backend connection failed for $rootUrl: $error',
        );
      }
    }

    debugPrint('Unable to connect to any backend URL.');
    return false;
  }

  /// Converts backend error responses into readable messages.
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
      // Ignore invalid JSON responses.
    }

    return '$fallback (HTTP ${response.statusCode})';
  }

  /// Fetches all available regions.
  static Future<List<String>> fetchRegions() async {
    try {
      final response = await http
          .get(Uri.parse('$activeBaseUrl/regions'))
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Regions response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          return List<String>.from(
            data['regions'] ?? const [],
          );
        }

        if (data is List) {
          return data
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList();
        }
      }
    } catch (error) {
      debugPrint('Error fetching regions: $error');
    }

    return [];
  }

  /// Fetches zones for the selected region.
  static Future<List<String>> fetchZones(String? region) async {
    try {
      final url = region != null && region.trim().isNotEmpty
          ? '$activeBaseUrl/zones?region=${Uri.encodeComponent(region.trim())}'
          : '$activeBaseUrl/zones';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Zones response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          return List<String>.from(
            data['zones'] ?? const [],
          );
        }

        if (data is List) {
          return data
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList();
        }
      }
    } catch (error) {
      debugPrint('Error fetching zones: $error');
    }

    return [];
  }

  /// Fetches wards for the selected region and zone.
  static Future<List<String>> fetchWards(
    String? region,
    String zone,
  ) async {
    final queryParameters = <String, String>{
      'zone': zone.trim(),
    };

    if (region != null && region.trim().isNotEmpty) {
      queryParameters['region'] = region.trim().toUpperCase();
    }

    final uri = Uri.parse('$activeBaseUrl/wards').replace(
      queryParameters: queryParameters,
    );

    debugPrint('Fetching wards from: $uri');

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 45));

      debugPrint(
        'Wards response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          _serverError(response, 'Unable to load wards'),
        );
      }

      final decoded = json.decode(response.body);

      if (decoded is Map<String, dynamic> &&
          decoded['wards'] is List) {
        return (decoded['wards'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
      }

      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
      }

      throw Exception('Invalid wards response from backend');
    } catch (error) {
      debugPrint('Error fetching wards: $error');
      rethrow;
    }
  }

  /// Fetches lamp types dynamically based on pole old-lamp type.
  static Future<List<String>> fetchLampTypes(
    String poleOldLamp, {
    String? region,
    String? zone,
    String? ward,
  }) async {
    final query = <String, String>{
      'pole_old_lamp': poleOldLamp.trim(),
    };

    if (region != null && region.trim().isNotEmpty) {
      query['region'] = region.trim();
    }

    if (zone != null && zone.trim().isNotEmpty) {
      query['zone'] = zone.trim();
    }

    if (ward != null && ward.trim().isNotEmpty) {
      query['ward'] = ward.trim();
    }

    final uri = Uri.parse('$activeBaseUrl/lamp-types').replace(
      queryParameters: query,
    );

    debugPrint('Fetching dynamic lamp types from: $uri');

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 60));

      debugPrint(
        'Lamp types response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          _serverError(response, 'Unable to load lamp types'),
        );
      }

      final data = json.decode(response.body);

      if (data is! Map<String, dynamic> ||
          data['lamp_types'] is! List) {
        throw Exception(
          'Invalid lamp type response from backend',
        );
      }

      return (data['lamp_types'] as List)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
    } catch (error) {
      debugPrint('Error fetching lamp types: $error');
      rethrow;
    }
  }

  /// Fetches pending poles based on the selected filters.
  static Future<List<Pole>> filterPendingPoles({
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
  }) async {
    final uri = Uri.parse('$activeBaseUrl/poles/filter');

    debugPrint('Filtering pending poles using: $uri');

    try {
      final response = await http
          .post(
            uri,
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

      debugPrint(
        'Pending poles response: '
        '${response.statusCode} ${response.body}',
      );

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
    } catch (error) {
      debugPrint('Error filtering pending poles: $error');
      rethrow;
    }
  }

  /// Calculates geographical distances from the selected starting pole.
  static Future<List<Pole>> calculateDistance({
    required String startingPoleNumber,
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
  }) async {
    final uri = Uri.parse(
      '$activeBaseUrl/poles/calculate-distance',
    );

    debugPrint('Calculating distances using: $uri');

    try {
      final response = await http
          .post(
            uri,
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

      debugPrint(
        'Distance response: '
        '${response.statusCode} ${response.body}',
      );

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
    } catch (error) {
      debugPrint('Error calculating distances: $error');
      rethrow;
    }
  }

  /// Looks up one pole directly in Schnell IoT / ThingsBoard.
  ///
  /// Returns the raw IoT pole information when the pole is found.
  /// Returns null when the pole is not found or the request fails.
  static Future<Map<String, dynamic>?> fetchSchnellIoTPole(
    String poleNumber,
  ) async {
    try {
      final encodedPoleNumber = Uri.encodeComponent(
        poleNumber,
      );

      final uri = Uri.parse(
        '$activeBaseUrl/schnell-iot/pole/$encodedPoleNumber',
      );

      debugPrint('Fetching IoT pole from: $uri');

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));

      debugPrint(
        'IoT pole response: '
        '${response.statusCode} ${response.body}',
      );

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
    } catch (error) {
      debugPrint('Error fetching IoT pole: $error');
    }

    return null;
  }

  /// Looks up multiple poles in Schnell IoT / ThingsBoard.
  ///
  /// The returned map is keyed by pole number.
  /// Each value contains the backend's live IoT result.
  static Future<Map<String, Map<String, dynamic>>>
      fetchSchnellIoTPoles(
    List<String> poleNumbers,
  ) async {
    if (poleNumbers.isEmpty) {
      return {};
    }

    try {
      final uri = Uri.parse(
        '$activeBaseUrl/schnell-iot/poles',
      );

      debugPrint('Fetching multiple IoT poles from: $uri');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'pole_numbers': poleNumbers,
            }),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint(
        'Multiple IoT poles response: '
        '${response.statusCode} ${response.body}',
      );

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
            poleNumber.trim().isEmpty) {
          continue;
        }

        results[poleNumber] = Map<String, dynamic>.from(item);
      }

      return results;
    } catch (error) {
      debugPrint('Error fetching multiple IoT poles: $error');
      return {};
    }
  }
}