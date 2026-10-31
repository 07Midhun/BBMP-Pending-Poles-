import 'dart:math' show cos, sqrt, asin, pi;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pole_model.dart';
import '../../services/api_service.dart';
import '../../core/storage/database_service.dart';
import '../filters/filter_providers.dart';

final startingPoleProvider = StateProvider<Pole?>((ref) => null);

double _calculateLocalDistance(double lat1, double lon1, double lat2, double lon2) {
  var p = pi / 180;
  var c = cos;
  var a = 0.5 - c((lat2 - lat1) * p) / 2 +
          c(lat1 * p) * c(lat2 * p) *
          (1 - c((lon2 - lon1) * p)) / 2;
  return 12742000 * asin(sqrt(a));
}

final driveStatusProvider = FutureProvider.family<int, String>((ref, poleNumber) async {
  return ApiService.fetchDriveStatus(poleNumber);
});

final poleImagesProvider = FutureProvider.family<Map<int, Map<String, dynamic>>, String>((ref, poleNumber) async {
  final data = await ApiService.fetchPoleImages(poleNumber);
  final Map<int, Map<String, dynamic>> result = {};
  if (data != null && data['images'] is Map) {
    final images = data['images'] as Map;
    for (int slot = 1; slot <= 3; slot++) {
      final val = images[slot.toString()];
      if (val is Map) {
        result[slot] = Map<String, dynamic>.from(val);
      }
    }
  }
  return result;
});

final polesProvider = FutureProvider<List<Pole>>((ref) async {
  final region = ref.watch(selectedRegionProvider);
  final zone = ref.watch(selectedZoneProvider);
  final ward = ref.watch(selectedWardProvider);
  final oldLamp = ref.watch(selectedPoleOldLampProvider);
  final lampType = ref.watch(selectedLampTypeProvider);
  
  // Starting pole triggers a distance calculation recalculation.
  final startingPole = ref.watch(startingPoleProvider);

  if (region == null || zone == null || ward == null || oldLamp == null || lampType == null) {
    return [];
  }

  final dbService = ref.read(databaseServiceProvider);

  try {
    List<Pole> poles = await ApiService.filterPendingPoles(
      region: region,
      zone: zone,
      ward: ward,
      poleOldLamp: oldLamp,
      lampType: lampType,
    );

    // Intelligent fallback: if selected ward has no pending poles (e.g. data mapped at zone level),
    // fetch poles in this zone matching the lamp filters so the technician can work immediately.
    if (poles.isEmpty) {
      try {
        final zonePoles = await ApiService.filterPendingPoles(
          region: region,
          zone: zone,
          poleOldLamp: oldLamp,
          lampType: lampType,
        );
        if (zonePoles.isNotEmpty) {
          poles = zonePoles;
        } else {
          // If still empty (e.g. lamp type too restrictive), load all poles for the zone
          final allZonePoles = await ApiService.filterPendingPoles(
            region: region,
            zone: zone,
          );
          if (allZonePoles.isNotEmpty) {
            poles = allZonePoles;
          }
        }
      } catch (_) {
        // Keep initial poles result if fallback throws
      }
    }
    
    // If starting pole is selected, calculate distances locally instantly
    if (startingPole != null) {
      poles = poles.map((p) {
        final dist = _calculateLocalDistance(
          startingPole.latitude, startingPole.longitude,
          p.latitude, p.longitude,
        );
        return p.copyWith(distanceMeters: dist);
      }).toList();

      // Sort by distance
      poles.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
      
      // Assign order
      for (int i = 0; i < poles.length; i++) {
        poles[i] = poles[i].copyWith(order: i + 1);
      }
    }
    
    // Cache the poles for offline use
    if (poles.isNotEmpty) {
      await dbService.cachePoles(poles.map((p) => p.toJson()).toList());
    }
    
    return poles;
  } catch (e) {
    // If online fetch fails, try loading from cache
    try {
      final cached = await dbService.getCachedPoles();
      if (cached.isNotEmpty) {
        return cached.map((c) => Pole.fromJson(c)).toList();
      }
    } catch (_) {}
    
    throw Exception('Failed to fetch poles and no offline cache available: $e');
  }
});
