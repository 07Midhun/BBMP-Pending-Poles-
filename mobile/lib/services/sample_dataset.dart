import '../models/pole_model.dart';

List<Pole> getInitialBbmpPoles() {
  final List<Map<String, dynamic>> rawData = [
    // East Zone - Ward 45
    {
      'id': 1,
      'pole_number': 'P0001',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.98204,
      'longitude': 77.67365
    },
    {
      'id': 2,
      'pole_number': 'P0010',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.98210,
      'longitude': 77.67372
    },
    {
      'id': 3,
      'pole_number': 'P0100',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-FLED',
      'latitude': 12.98215,
      'longitude': 77.67380
    },
    {
      'id': 4,
      'pole_number': 'P0200',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-LED',
      'latitude': 12.98300,
      'longitude': 77.67500
    },
    {
      'id': 5,
      'pole_number': 'P0300',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.98400,
      'longitude': 77.67600
    },
    {
      'id': 6,
      'pole_number': 'P0045',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'CFL',
      'latitude': 12.98250,
      'longitude': 77.67400
    },
    {
      'id': 7,
      'pole_number': 'P0046',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Sodium',
      'latitude': 12.98260,
      'longitude': 77.67410
    },
    {
      'id': 8,
      'pole_number': 'P0047',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Halogen',
      'latitude': 12.98280,
      'longitude': 77.67430
    },
    {
      'id': 9,
      'pole_number': 'P0048',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Tube',
      'latitude': 12.98290,
      'longitude': 77.67440
    },
    {
      'id': 10,
      'pole_number': 'P0050',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Empty',
      'lamp_type': '-',
      'latitude': 12.98310,
      'longitude': 77.67460
    },
    {
      'id': 11,
      'pole_number': 'P0051',
      'zone': 'East',
      'ward': 'Ward 45',
      'pole_old_lamp': 'Empty',
      'lamp_type': 'Blank',
      'latitude': 12.98320,
      'longitude': 77.67470
    },

    // East Zone - Ward 46
    {
      'id': 12,
      'pole_number': 'P0461',
      'zone': 'East',
      'ward': 'Ward 46',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.98600,
      'longitude': 77.67700
    },
    {
      'id': 13,
      'pole_number': 'P0462',
      'zone': 'East',
      'ward': 'Ward 46',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.98620,
      'longitude': 77.67720
    },

    // West Zone - Ward 60
    {
      'id': 14,
      'pole_number': 'P0601',
      'zone': 'West',
      'ward': 'Ward 60',
      'pole_old_lamp': 'LED',
      'lamp_type': 'FLED',
      'latitude': 12.97500,
      'longitude': 77.56000
    },
    {
      'id': 15,
      'pole_number': 'P0602',
      'zone': 'West',
      'ward': 'Ward 60',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Halogen',
      'latitude': 12.97520,
      'longitude': 77.56030
    },

    // North Zone - Ward 10
    {
      'id': 16,
      'pole_number': 'P1001',
      'zone': 'North',
      'ward': 'Ward 10',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED-FLED',
      'latitude': 13.02000,
      'longitude': 77.59000
    },
    {
      'id': 17,
      'pole_number': 'P1002',
      'zone': 'North',
      'ward': 'Ward 10',
      'pole_old_lamp': 'Empty',
      'lamp_type': '-',
      'latitude': 13.02050,
      'longitude': 77.59050
    },

    // South Zone - Ward 150
    {
      'id': 18,
      'pole_number': 'P1501',
      'zone': 'South',
      'ward': 'Ward 150',
      'pole_old_lamp': 'LED',
      'lamp_type': 'LED',
      'latitude': 12.92000,
      'longitude': 77.58000
    },
    {
      'id': 19,
      'pole_number': 'P1502',
      'zone': 'South',
      'ward': 'Ward 150',
      'pole_old_lamp': 'Non-LED',
      'lamp_type': 'Sodium',
      'latitude': 12.92040,
      'longitude': 77.58040
    },
  ];

  return rawData.map((map) => Pole.fromJson(map)).toList();
}
