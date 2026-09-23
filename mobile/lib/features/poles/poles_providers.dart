import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pole_model.dart';
import '../../services/api_service.dart';
import '../../core/storage/database_service.dart';
import '../filters/filter_providers.dart';

final startingPoleProvider = StateProvider<Pole?>((ref) => null);

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
    List<Pole> poles;
    if (startingPole != null) {
      poles = await ApiService.calculateDistance(
        startingPoleNumber: startingPole.poleNumber,
        region: region,
        zone: zone,
        ward: ward,
        poleOldLamp: oldLamp,
        lampType: lampType,
      );
    } else {
      poles = await ApiService.filterPendingPoles(
        region: region,
        zone: zone,
        ward: ward,
        poleOldLamp: oldLamp,
        lampType: lampType,
      );
    }
    
    // Cache the poles for offline use
    await dbService.cachePoles(poles.map((p) => p.toJson()).toList());
    
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
