import '../models/pole_model.dart';

List<Pole> getInitialMasterBbmpPoles() {
  final List<Map<String, dynamic>> rawData = [
    // East Region - East Zone - Ward 45
    {
      'id': 1,
      'pole_number': 'P0001',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.98204,
      'longitude': 77.67365
    },
    {
      'id': 2,
      'pole_number': 'P0010',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.98210,
      'longitude': 77.67372
    },
    {
      'id': 3,
      'pole_number': 'P0100',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-FLED',
      'latitude': 12.98215,
      'longitude': 77.67380
    },
    {
      'id': 4,
      'pole_number': 'P0200',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-LED',
      'latitude': 12.98300,
      'longitude': 77.67500
    },
    {
      'id': 5,
      'pole_number': 'P0300',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.98400,
      'longitude': 77.67600
    },
    {
      'id': 6,
      'pole_number': 'P0045',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'CFL',
      'latitude': 12.98250,
      'longitude': 77.67400
    },
    {
      'id': 7,
      'pole_number': 'P0046',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Sodium',
      'latitude': 12.98260,
      'longitude': 77.67410
    },
    {
      'id': 8,
      'pole_number': 'P0047',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Empty',
      'lamp_type': '-',
      'latitude': 12.98280,
      'longitude': 77.67430
    },
    {
      'id': 9,
      'pole_number': 'P0048',
      'region': 'East',
      'zone': 'East Zone',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Empty',
      'lamp_type': 'Blank',
      'latitude': 12.98290,
      'longitude': 77.67440
    },

    // Bommanahalli Region - Bommanahalli Zone - Ward 174
    {
      'id': 10,
      'pole_number': 'P1741',
      'region': 'Bommanahalli',
      'zone': 'Bommanahalli Zone',
      'ward': 'Ward 174',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.90800,
      'longitude': 77.62400
    },
    {
      'id': 11,
      'pole_number': 'P1742',
      'region': 'Bommanahalli',
      'zone': 'Bommanahalli Zone',
      'ward': 'Ward 174',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.90820,
      'longitude': 77.62420
    },
    {
      'id': 12,
      'pole_number': 'P1743',
      'region': 'Bommanahalli',
      'zone': 'Bommanahalli Zone',
      'ward': 'Ward 174',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-FLED',
      'latitude': 12.90850,
      'longitude': 77.62450
    },
    {
      'id': 13,
      'pole_number': 'P1744',
      'region': 'Bommanahalli',
      'zone': 'Bommanahalli Zone',
      'ward': 'Ward 174',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Halogen',
      'latitude': 12.90880,
      'longitude': 77.62480
    },

    // West Region - West Zone - Ward 60
    {
      'id': 14,
      'pole_number': 'P0601',
      'region': 'West',
      'zone': 'West Zone',
      'ward': 'Ward 60',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.97500,
      'longitude': 77.56000
    },
    {
      'id': 15,
      'pole_number': 'P0602',
      'region': 'West',
      'zone': 'West Zone',
      'ward': 'Ward 60',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Tube',
      'latitude': 12.97520,
      'longitude': 77.56030
    },

    // South Region - South Zone - Ward 150
    {
      'id': 16,
      'pole_number': 'P1501',
      'region': 'South',
      'zone': 'South Zone',
      'ward': 'Ward 150',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.92000,
      'longitude': 77.58000
    },
    {
      'id': 17,
      'pole_number': 'P1502',
      'region': 'South',
      'zone': 'South Zone',
      'ward': 'Ward 150',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Sodium',
      'latitude': 12.92040,
      'longitude': 77.58040
    },
  ];

  return rawData.map((map) => Pole.fromJson(map)).toList();
}

/// Simulated Lamp Installation Report containing installed pole numbers (including duplicates)
/// P0001 (installed twice), P0100 (installed twice), P0200 (installed once)
List<String> getInitialInstalledReport() {
  return ['P0001', 'P0001', 'P0100', 'P0100', 'P0200'];
}

