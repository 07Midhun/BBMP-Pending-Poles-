import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';

const Map<String, List<String>> kFallbackZones = {
  'EAST': [
    'CVRamanNagar',
    'Hebbal',
    'PulakeshiNagar',
    'SarvagnaNagar',
    'ShanthiNagar',
    'ShivajiNagar',
  ],
  'BOMMANAHALLI': [
    'Bommanahali-Z1',
  ],
};

const Map<String, List<String>> kFallbackWards = {
  'CVRamanNagar': [
    'CVR-W50',
    'CVR-W51',
    'CVR-W52',
    'CVRN-W108',
    'CVRN-W109',
    'CVRN-W110',
    'CVRN-W111',
    'CVRN-W112',
    'CVRN-W113',
    'CVRN-W114',
    'CVRN-W115',
  ],
  'Hebbal': [
    'HEB-W59',
    'HEB-W60',
    'HEB-W61',
    'HEB-W62',
    'HEB-W63',
    'HEB-W64',
    'HEB-W65',
    'HEB-W66',
    'HEB-W67',
    'HEB-W68',
  ],
  'PulakeshiNagar': [
    'PN-W69',
    'PN-W70',
    'PN-W71',
    'PN-W72',
    'PN-W73',
    'PN-W74',
    'PN-W75',
  ],
  'SarvagnaNagar': [
    'SAR-W80',
    'SAR-W81',
    'SAR-W82',
    'SN-W76',
    'SN-W77',
    'SN-W78',
    'SN-W79',
    'SN-W80',
    'SN-W81',
    'SN-W82',
    'SN-W83',
    'SN-W84',
    'SN-W85',
  ],
  'ShanthiNagar': [
    'SHA-W110',
    'SHA-W111',
    'SNTR-W166',
    'SNTR-W167',
    'SNTR-W168',
    'SNTR-W169',
    'SNTR-W170',
    'SNTR-W171',
    'SNTR-W172',
  ],
  'ShivajiNagar': [
    'SHI-W90',
    'SHI-W91',
    'SVJR-W116',
    'SVJR-W117',
    'SVJR-W118',
    'SVJR-W119',
    'SVJR-W120',
    'SVJR-W121',
  ],
  'Bommanahali-Z1': [
    'BOM-W174',
    'BOM-W175',
    'BOM-W176',
    'BMH-W202',
    'BMH-W203',
    'BMH-W204',
    'BMH-W205',
    'BMH-W206',
    'BMH-W207',
    'BMH-W208',
    'BMH-W209',
    'BMH-W210',
    'BMH-W211',
    'BMH-W212',
  ],
};

final backendOnlineProvider = FutureProvider<bool>((ref) async {
  return await ApiService.checkHealth();
});

final regionsProvider = FutureProvider<List<String>>((ref) async {
  try {
    final regions = await ApiService.fetchRegions();
    if (regions.isNotEmpty) return regions;
  } catch (_) {
    // Fallback if backend offline
  }
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
    final zones = await ApiService.fetchZones(region);
    if (zones.isNotEmpty) return zones;
  } catch (_) {
    // Fallback if backend offline handled below
  }

  final key = region.trim().toUpperCase();
  return kFallbackZones[key] ?? [];
});

final wardsProvider = FutureProvider<List<String>>((ref) async {
  final region = ref.watch(selectedRegionProvider);
  final zone = ref.watch(selectedZoneProvider);
  if (zone == null) return [];
  try {
    final wards = await ApiService.fetchWards(region, zone);
    if (wards.isNotEmpty) return wards;
  } catch (_) {
    // Fallback if backend offline handled below
  }

  return kFallbackWards[zone] ?? [];
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
    final lampTypes = await ApiService.fetchLampTypes(
      region: region,
      zone: zone,
      ward: ward,
      poleOldLamp: oldLamp,
    );
    if (lampTypes.isNotEmpty) return lampTypes;
  } catch (_) {
    // Fallback based on old logic if API fails
  }

  if (oldLamp == 'LED') return ['LED', 'FLED', 'LED-FLED', 'LED-LED'];
  if (oldLamp == 'Non-LED') {
    return ['1x36W FTL', '1x70W SV', '1x150W SV', '1x250W SV', '1x400W SV'];
  }
  if (oldLamp == 'Empty') return ['-', ''];
  return [];
});
