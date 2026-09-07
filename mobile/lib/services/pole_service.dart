import '../models/pole_model.dart';
import '../utils/haversine.dart';
import 'sample_dataset.dart';

class PoleService {
  List<Pole> _allPoles = getInitialBbmpPoles();

  List<Pole> get allPoles => _allPoles;

  void updatePoles(List<Pole> newPoles) {
    _allPoles = newPoles;
  }

  /// Get distinct zones from available data
  List<String> getZones() {
    final set = _allPoles.map((p) => p.zone).where((z) => z.isNotEmpty).toSet();
    final list = set.toList()..sort();
    return list;
  }

  /// Get dependent wards for selected zone
  List<String> getWardsForZone(String? zone) {
    if (zone == null || zone.isEmpty) return [];
    final set = _allPoles
        .where((p) => p.zone.toLowerCase() == zone.toLowerCase())
        .map((p) => p.ward)
        .where((w) => w.isNotEmpty)
        .toSet();
    final list = set.toList()..sort();
    return list;
  }

  /// Get Lamp Types for classification
  /// LED -> LED, FLED, LED-FLED, LED-LED
  /// Empty -> -, Blank
  /// Non-LED -> all valid types excluding LED group & Empty group
  List<String> getLampTypesForOldLamp(String? poleOldLamp) {
    if (poleOldLamp == null || poleOldLamp.isEmpty) return [];

    final cls = poleOldLamp.trim();
    if (cls == 'LED') {
      return ['LED', 'FLED', 'LED-FLED', 'LED-LED'];
    } else if (cls == 'Empty') {
      return ['-', 'Blank'];
    } else if (cls == 'Non-LED') {
      const ledGroup = {'LED', 'FLED', 'LED-FLED', 'LED-LED'};
      const emptyGroup = {'-', 'BLANK', '', 'NONE', 'NULL', 'NAN'};

      final allTypes = _allPoles.map((p) => p.lampType).toSet();
      final nonLedTypes = allTypes.where((t) {
        final upper = t.toUpperCase().trim();
        return !ledGroup.contains(upper) && !emptyGroup.contains(upper);
      }).toList();

      if (nonLedTypes.isEmpty) {
        return ['CFL', 'Sodium', 'Halogen', 'Tube'];
      }
      nonLedTypes.sort();
      return nonLedTypes;
    }
    return [];
  }

  /// Filters dataset matching all selected criteria
  List<Pole> filterPoles({
    required String? zone,
    required String? ward,
    required String? poleOldLamp,
    required String? lampType,
  }) {
    return _allPoles.where((p) {
      if (zone != null && zone.isNotEmpty && p.zone.toLowerCase() != zone.toLowerCase()) {
        return false;
      }
      if (ward != null && ward.isNotEmpty && p.ward.toLowerCase() != ward.toLowerCase()) {
        return false;
      }
      if (poleOldLamp != null && poleOldLamp.isNotEmpty) {
        if (p.poleOldLamp.toLowerCase() != poleOldLamp.toLowerCase()) {
          return false;
        }
      }
      if (lampType != null && lampType.isNotEmpty) {
        if (p.lampType.toLowerCase() != lampType.toLowerCase()) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Calculates distance from starting pole to all filtered poles and orders nearest -> farthest
  List<Pole> calculateDistancesAndSort({
    required List<Pole> filteredPoles,
    required String startingPoleNumber,
  }) {
    final startPole = filteredPoles.firstWhere(
      (p) => p.poleNumber.toLowerCase() == startingPoleNumber.toLowerCase(),
      orElse: () => _allPoles.firstWhere(
        (p) => p.poleNumber.toLowerCase() == startingPoleNumber.toLowerCase(),
        orElse: () => filteredPoles.first,
      ),
    );

    final double startLat = startPole.latitude;
    final double startLon = startPole.longitude;

    final result = filteredPoles.map((pole) {
      final distM = Haversine.calculateDistance(
        startLat,
        startLon,
        pole.latitude,
        pole.longitude,
      );
      pole.distanceMeters = distM;
      return pole;
    }).toList();

    // Sort ascending by distance
    result.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));

    // Assign sequence order 1..N
    for (int i = 0; i < result.length; i++) {
      result[i].order = i + 1;
    }

    return result;
  }
}
