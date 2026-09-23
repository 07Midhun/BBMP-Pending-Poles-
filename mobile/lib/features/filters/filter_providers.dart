import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';

final backendOnlineProvider = FutureProvider<bool>((ref) async {
  return await ApiService.checkHealth();
});

final regionsProvider = FutureProvider<List<String>>((ref) async {
  // Always allow selecting regions, removing offline criteria constraint
  return const ['BOMMANAHALLI', 'EAST'];
});

final selectedRegionProvider = StateProvider<String?>((ref) => null);
final selectedZoneProvider = StateProvider<String?>((ref) => null);
final selectedWardProvider = StateProvider<String?>((ref) => null);
final selectedPoleOldLampProvider = StateProvider<String?>((ref) => null);
final selectedLampTypeProvider = StateProvider<String?>((ref) => null);

final zonesProvider = FutureProvider<List<String>>((ref) async {
  final region = ref.watch(selectedRegionProvider);
  if (region == null) return [];
  try {
    return await ApiService.fetchZones(region);
  } catch (e) {
    return [];
  }
});

final wardsProvider = FutureProvider<List<String>>((ref) async {
  final region = ref.watch(selectedRegionProvider);
  final zone = ref.watch(selectedZoneProvider);
  if (zone == null) return [];
  try {
    return await ApiService.fetchWards(region, zone);
  } catch (e) {
    return [];
  }
});

final poleOldLampOptionsProvider = Provider<List<String>>((ref) {
  return const ['LED', 'Non-LED', 'Empty'];
});

final lampTypesProvider = FutureProvider<List<String>>((ref) async {
  final region = ref.watch(selectedRegionProvider);
  final zone = ref.watch(selectedZoneProvider);
  final ward = ref.watch(selectedWardProvider);
  final oldLamp = ref.watch(selectedPoleOldLampProvider);
  
  if (oldLamp == null) return [];
  
  try {
    return await ApiService.fetchLampTypes(
      region: region,
      zone: zone,
      ward: ward,
      poleOldLamp: oldLamp,
    );
  } catch (e) {
    // Fallback based on old logic if API fails
    if (oldLamp == 'LED') return ['LED', 'FLED', 'LED-FLED', 'LED-LED'];
    if (oldLamp == 'Empty') return ['-', ''];
    return [];
  }
});
