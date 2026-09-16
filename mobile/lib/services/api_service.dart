import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pole_model.dart';
import 'database_service.dart';

class ApiService {
  /// Currently active backend URL.
  ///
  /// For testing on your physical Android phone, the local computer IP
  /// is used first.
  ///
  /// Your phone successfully reached:
  /// http://10.18.72.47:8000/
  static String activeBaseUrl =
      'http://10.46.23.63:8000/api/v1';

  /// Backend URLs tried by the application.
  ///
  /// Order:
  /// 1. Local backend on your computer.
  /// 2. Render production backend.
  /// 3. Web local development URL when running Flutter Web.
  static List<String> get _candidateUrls {
    final urls = <String>[
      // Wi-Fi IP address
      'http://10.46.23.63:8000/api/v1',
      // Ethernet IP addresses
      'http://192.168.3.149:8000/api/v1',
      'http://10.18.72.179:8000/api/v1',
      // Android Emulator localhost alias
      'http://10.0.2.2:8000/api/v1',
      // ADB reverse tcp (USB connected physical device)
      'http://127.0.0.1:8000/api/v1',

      // Render production backend - Render 2.
      'https://bbmp-pending-poles-2.onrender.com/api/v1',

      // Production Render backend.
      'https://bbmp-pending-poles-6.onrender.com/api/v1',
    ];

    if (kIsWeb) {
      final webHost = Uri.base.host.trim();

      if (webHost.isNotEmpty &&
          webHost != 'localhost' &&
          webHost != '127.0.0.1') {
        urls.add('http://$webHost:8000/api/v1');
      }

      urls.add('http://localhost:8000/api/v1');
      urls.add('http://127.0.0.1:8000/api/v1');
    }

    return urls;
  }

  /// Removes the API path and trailing slash from a backend URL.
  ///
  /// Example:
  /// http://192.168.9.244:8000/api/v1
  /// becomes:
  /// http://10.18.72.47:8000
  static String _rootUrl(String url) {
    return url
        .replaceFirst(RegExp(r'/api/v1/?$'), '')
        .replaceFirst(RegExp(r'/$'), '');
  }

  /// Checks whether any backend URL is reachable.
  ///
  /// The FastAPI backend exposes:
  /// GET /
  static Future<bool> checkHealth() async {
    for (final url in _candidateUrls) {
      final rootUrl = _rootUrl(url);

      try {
        debugPrint('Checking backend: $rootUrl');

        final response = await http
            .get(Uri.parse(rootUrl))
            .timeout(const Duration(seconds: 10));

        debugPrint(
          'Backend response: '
          '${response.statusCode} ${response.body}',
        );

        if (response.statusCode == 200) {
          activeBaseUrl = url;

          debugPrint(
            'Backend connected successfully using: '
            '$activeBaseUrl',
          );

          return true;
        }
      } catch (error) {
        debugPrint(
          'Backend connection failed for '
          '$rootUrl: $error',
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
        'Regions response: '
        '${response.statusCode} ${response.body}',
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
        'Zones response: '
        '${response.statusCode} ${response.body}',
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
        'Wards response: '
        '${response.statusCode} ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          _serverError(
            response,
            'Unable to load wards',
          ),
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

      throw Exception(
        'Invalid wards response from backend',
      );
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

    debugPrint(
      'Fetching dynamic lamp types from: $uri',
    );

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 60));

      debugPrint(
        'Lamp types response: '
        '${response.statusCode} ${response.body}',
      );

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

      return (data['lamp_types'] as List)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
    } catch (error) {
      debugPrint(
        'Error fetching lamp types: $error',
      );
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
    final uri = Uri.parse(
      '$activeBaseUrl/poles/filter',
    );

    debugPrint(
      'Filtering pending poles using: $uri',
    );

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

      final poles = (data['poles'] as List)
          .whereType<Map>()
          .map(
            (item) => Pole.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
          
      // Cache poles for offline use
      await DatabaseService.instance.cachePoles(poles);
      return poles;
    } catch (error) {
      debugPrint(
        'Error filtering pending poles: $error. Falling back to local cache.',
      );
      
      try {
        final cached = await DatabaseService.instance.getCachedPoles(
          region: region,
          zone: zone,
          ward: ward,
          poleOldLamp: poleOldLamp,
          lampType: lampType,
        );
        if (cached.isNotEmpty) {
          debugPrint('Successfully loaded ${cached.length} poles from local cache.');
          return cached;
        }
      } catch (cacheError) {
        debugPrint('Cache fallback failed: $cacheError');
      }

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

    debugPrint(
      'Calculating distances using: $uri',
    );

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
      debugPrint(
        'Error calculating distances: $error',
      );
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

      debugPrint(
        'Fetching IoT pole from: $uri',
      );

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
      debugPrint(
        'Error fetching IoT pole: $error',
      );
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
      final uri = Uri.parse(
        '$activeBaseUrl/schnell-iot/poles',
      );

      debugPrint(
        'Fetching multiple IoT poles from: $uri',
      );

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

        results[poleNumber] = Map<String, dynamic>.from(
          item,
        );
      }

      return results;
    } catch (error) {
      debugPrint(
        'Error fetching multiple IoT poles: $error',
      );
      return {};
    }
  }
}