import '../models/pole_model.dart';
import '../utils/haversine.dart';
import 'sample_dataset.dart';

class PoleService {
  List<Pole> _masterPoles = getInitialMasterBbmpPoles();
  List<String> _installedReport = getInitialInstalledReport();

  List<Pole> get masterPoles => _masterPoles;

  List<String> get installedReport => _installedReport;

  // ---------------------------------------------------------------------------
  // FILTER OPTIONS
  // ---------------------------------------------------------------------------

  static const List<String> poleOldLampOptions = [
    'LED',
    'Non-LED',
    'Empty',
  ];

  static const List<String> ledLampTypes = [
    'LED',
    'FLED',
    'LED-FLED',
    'LED-LED',
  ];

  static const List<String> emptyLampTypes = [
    '-',
    'Blank',
  ];

  // ---------------------------------------------------------------------------
  // PENDING POLES
  // ---------------------------------------------------------------------------

  /// PENDING POLES = MASTER POLES - INSTALLED POLES
  ///
  /// The installation report can contain duplicate pole numbers.
  /// A Set is used so duplicates have no effect on matching.
  List<Pole> get pendingPoles {
    final installedSet = _installedReport
        .map(_normalizePoleNumber)
        .where((value) => value.isNotEmpty)
        .toSet();

    return _masterPoles
        .where(
          (pole) =>
              !installedSet.contains(
                _normalizePoleNumber(pole.poleNumber),
              ),
        )
        .map((pole) => pole.copyWith())
        .toList();
  }

  // ---------------------------------------------------------------------------
  // DATA UPDATE METHODS
  // ---------------------------------------------------------------------------

  void updateMasterPoles(List<Pole> newMaster) {
    _masterPoles = newMaster;
  }

  void updateInstalledReport(List<String> newInstalled) {
    _installedReport = newInstalled;
  }

  // ---------------------------------------------------------------------------
  // REGION
  // ---------------------------------------------------------------------------

  List<String> getRegions() {
    final regions = pendingPoles
        .map((pole) => pole.region.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    regions.sort(_naturalCompare);

    return regions;
  }

  // ---------------------------------------------------------------------------
  // ZONE
  // ---------------------------------------------------------------------------

  List<String> getZonesForRegion(String? region) {
    if (region == null || region.trim().isEmpty) {
      return [];
    }

    final zones = pendingPoles
        .where(
          (pole) => _sameValue(pole.region, region),
        )
        .map((pole) => pole.zone.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    zones.sort(_naturalCompare);

    return zones;
  }

  // ---------------------------------------------------------------------------
  // WARD
  // ---------------------------------------------------------------------------

  List<String> getWardsForZone(
    String? region,
    String? zone,
  ) {
    if (zone == null || zone.trim().isEmpty) {
      return [];
    }

    Iterable<Pole> filtered = pendingPoles;

    if (region != null && region.trim().isNotEmpty) {
      filtered = filtered.where(
        (pole) => _sameValue(pole.region, region),
      );
    }

    final wards = filtered
        .where(
          (pole) => _sameValue(pole.zone, zone),
        )
        .map((pole) => pole.ward.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    wards.sort(_naturalCompare);

    return wards;
  }

  // ---------------------------------------------------------------------------
  // LAMP TYPE OPTIONS
  // ---------------------------------------------------------------------------

  /// Returns Lamp Type options based on Pole With Old Lamp.
  ///
  /// LED:
  ///   LED
  ///   FLED
  ///   LED-FLED
  ///   LED-LED
  ///
  /// Empty:
  ///   -
  ///   Blank
  ///
  /// Non-LED:
  ///   All valid lamp types except LED and Empty groups.
  List<String> getLampTypesForOldLamp(String? poleOldLamp) {
    if (poleOldLamp == null || poleOldLamp.trim().isEmpty) {
      return [];
    }

    switch (poleOldLamp.trim()) {
      case 'LED':
        return List<String>.from(ledLampTypes);

      case 'Empty':
        return List<String>.from(emptyLampTypes);

      case 'Non-LED':
        final ledGroup = ledLampTypes
            .map(_normalizeLampType)
            .toSet();

        final emptyGroup = emptyLampTypes
            .map(_normalizeLampType)
            .toSet();

        final allTypes = pendingPoles
            .map((pole) => _normalizeLampType(pole.lampType))
            .where((value) => value.isNotEmpty)
            .toSet();

        final nonLedTypes = allTypes.where(
          (type) =>
              !ledGroup.contains(type) &&
              !emptyGroup.contains(type),
        ).toList();

        nonLedTypes.sort(_naturalCompare);

        return nonLedTypes;

      default:
        return [];
    }
  }

  // ---------------------------------------------------------------------------
  // LAMP CLASSIFICATION
  // ---------------------------------------------------------------------------

  /// Classifies a Lamp Type into:
  ///
  /// LED
  /// Non-LED
  /// Empty
  String classifyLampType(String? lampType) {
    final normalized = _normalizeLampType(lampType);

    if (ledLampTypes
        .map(_normalizeLampType)
        .contains(normalized)) {
      return 'LED';
    }

    if (emptyLampTypes
        .map(_normalizeLampType)
        .contains(normalized)) {
      return 'Empty';
    }

    return 'Non-LED';
  }

  // ---------------------------------------------------------------------------
  // FILTER PENDING POLES
  // ---------------------------------------------------------------------------

  List<Pole> filterPendingPoles({
    required String? region,
    required String? zone,
    required String? ward,
    required String? poleOldLamp,
    required String? lampType,
  }) {
    Iterable<Pole> result = pendingPoles;

    // Region
    if (region != null && region.trim().isNotEmpty) {
      result = result.where(
        (pole) => _sameValue(pole.region, region),
      );
    }

    // Zone
    if (zone != null && zone.trim().isNotEmpty) {
      result = result.where(
        (pole) => _sameValue(pole.zone, zone),
      );
    }

    // Ward
    if (ward != null && ward.trim().isNotEmpty) {
      result = result.where(
        (pole) => _sameValue(pole.ward, ward),
      );
    }

    // Pole With Old Lamp
    if (poleOldLamp != null && poleOldLamp.trim().isNotEmpty) {
      result = result.where(
        (pole) =>
            classifyLampType(pole.lampType) ==
            poleOldLamp.trim(),
      );
    }

    // Lamp Type
    if (lampType != null && lampType.trim().isNotEmpty) {
      final selectedLampType = _normalizeLampType(lampType);

      result = result.where(
        (pole) =>
            _normalizeLampType(pole.lampType) ==
            selectedLampType,
      );
    }

    return result
        .map((pole) => pole.copyWith())
        .toList();
  }

  // ---------------------------------------------------------------------------
  // STARTING POLE + DISTANCE
  // ---------------------------------------------------------------------------

  /// Calculates geographical distance from the selected starting pole.
  ///
  /// The starting pole MUST exist in the currently filtered pending-pole list.
  ///
  /// Results are sorted:
  ///
  /// nearest → farthest
  List<Pole> calculateDistancesAndSort({
    required List<Pole> filteredPoles,
    required String startingPoleNumber,
  }) {
    if (filteredPoles.isEmpty) {
      return [];
    }

    final normalizedStartingPole =
        _normalizePoleNumber(startingPoleNumber);

    if (normalizedStartingPole.isEmpty) {
      return [];
    }

    // IMPORTANT:
    // Starting pole must belong to the current filtered result.
    final startIndex = filteredPoles.indexWhere(
      (pole) =>
          _normalizePoleNumber(pole.poleNumber) ==
          normalizedStartingPole,
    );

    if (startIndex == -1) {
      return [];
    }

    final startPole = filteredPoles[startIndex];

    final result = filteredPoles.map((pole) {
      final distance = Haversine.calculateDistance(
        startPole.latitude,
        startPole.longitude,
        pole.latitude,
        pole.longitude,
      );

      return pole.copyWith(
        distanceMeters: distance,
      );
    }).toList();

    // Nearest → farthest
    result.sort((a, b) {
      final distanceA =
          a.distanceMeters ?? double.infinity;

      final distanceB =
          b.distanceMeters ?? double.infinity;

      final distanceComparison =
          distanceA.compareTo(distanceB);

      if (distanceComparison != 0) {
        return distanceComparison;
      }

      // If two poles have exactly the same distance,
      // use pole number only as a tie-breaker.
      return _naturalCompare(
        a.poleNumber,
        b.poleNumber,
      );
    });

    // Assign display order after sorting.
    for (int i = 0; i < result.length; i++) {
      result[i] = result[i].copyWith(
        order: i + 1,
      );
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _normalizePoleNumber(String? value) {
    if (value == null) {
      return '';
    }

    return value.trim().toUpperCase();
  }

  String _normalizeLampType(String? value) {
    if (value == null) {
      return '';
    }

    var normalized = value.trim().toUpperCase();

    // Normalize common variations.
    normalized = normalized.replaceAll('_', '-');
    normalized = normalized.replaceAll(' ', '');

    // Support old source value:
    // LED,FLED
    //
    // Internal canonical value:
    // LED-FLED
    normalized = normalized.replaceAll(',', '-');

    return normalized;
  }

  bool _sameValue(
    String? first,
    String? second,
  ) {
    return first?.trim().toUpperCase() ==
        second?.trim().toUpperCase();
  }

  int _naturalCompare(
    String a,
    String b,
  ) {
    final regex = RegExp(r'(\d+|\D+)');

    final aParts = regex
        .allMatches(a.toUpperCase())
        .map((match) => match.group(0)!)
        .toList();

    final bParts = regex
        .allMatches(b.toUpperCase())
        .map((match) => match.group(0)!)
        .toList();

    final length = aParts.length < bParts.length
        ? aParts.length
        : bParts.length;

    for (int i = 0; i < length; i++) {
      final aPart = aParts[i];
      final bPart = bParts[i];

      final aNumber = int.tryParse(aPart);
      final bNumber = int.tryParse(bPart);

      if (aNumber != null && bNumber != null) {
        final comparison = aNumber.compareTo(bNumber);

        if (comparison != 0) {
          return comparison;
        }
      } else {
        final comparison = aPart.compareTo(bPart);

        if (comparison != 0) {
          return comparison;
        }
      }
    }

    return aParts.length.compareTo(bParts.length);
  }
}