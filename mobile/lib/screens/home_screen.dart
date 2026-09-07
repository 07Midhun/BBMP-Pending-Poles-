import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pole_model.dart';
import '../services/pole_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PoleService _poleService = PoleService();

  // Selected Filter States
  String? _selectedZone;
  String? _selectedWard;
  String? _selectedPoleOldLamp;
  String? _selectedLampType;
  String? _selectedStartingPole;

  // Options Lists
  List<String> _zones = [];
  List<String> _wards = [];
  List<String> _lampTypes = [];
  List<String> _startingPoles = [];

  // Filtered & Distance Ordered Results
  List<Pole> _filteredPoles = [];
  List<Pole> _orderedPoles = [];

  bool _isOfflineMode = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    setState(() {
      _zones = _poleService.getZones();
      _wards = [];
      _lampTypes = [];
      _startingPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
    });
  }

  void _onZoneChanged(String? newZone) {
    setState(() {
      _selectedZone = newZone;
      _selectedWard = null;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _wards = _poleService.getWardsForZone(newZone);
      _lampTypes = [];
      _startingPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
    });
  }

  void _onWardChanged(String? newWard) {
    setState(() {
      _selectedWard = newWard;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _lampTypes = [];
      _startingPoles = [];
      _applyFilters();
    });
  }

  void _onPoleOldLampChanged(String? newOldLamp) {
    setState(() {
      _selectedPoleOldLamp = newOldLamp;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _lampTypes = _poleService.getLampTypesForOldLamp(newOldLamp);
      _startingPoles = [];
      _applyFilters();
    });
  }

  void _onLampTypeChanged(String? newLampType) {
    setState(() {
      _selectedLampType = newLampType;
      _selectedStartingPole = null;
      _applyFilters();
    });
  }

  void _onStartingPoleChanged(String? newStartingPole) {
    setState(() {
      _selectedStartingPole = newStartingPole;
      _calculateDistances();
    });
  }

  void _applyFilters() {
    final matches = _poleService.filterPoles(
      zone: _selectedZone,
      ward: _selectedWard,
      poleOldLamp: _selectedPoleOldLamp,
      lampType: _selectedLampType,
    );

    setState(() {
      _filteredPoles = matches;
      _startingPoles = matches.map((p) => p.poleNumber).toList();

      // If a starting pole was already selected and remains valid, keep it
      if (_selectedStartingPole != null && !_startingPoles.contains(_selectedStartingPole)) {
        _selectedStartingPole = null;
        _orderedPoles = [];
      } else if (_selectedStartingPole != null) {
        _calculateDistances();
      } else {
        _orderedPoles = [];
      }
    });
  }

  void _calculateDistances() {
    if (_selectedStartingPole == null || _filteredPoles.isEmpty) {
      setState(() {
        _orderedPoles = [];
      });
      return;
    }

    final sorted = _poleService.calculateDistancesAndSort(
      filteredPoles: _filteredPoles,
      startingPoleNumber: _selectedStartingPole!,
    );

    setState(() {
      _orderedPoles = sorted;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedZone = null;
      _selectedWard = null;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _wards = [];
      _lampTypes = [];
      _startingPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
    });
  }

  Future<void> _openGoogleMaps(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch Google Maps for $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate blue
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 4,
        title: Row(
          children: [
            const Icon(Icons.lightbulb_circle, color: Color(0xFF38BDF8), size: 28),
            const SizedBox(width: 10),
            const Text(
              'BBMP PENDING POLES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear All Filters',
            icon: const Icon(Icons.refresh, color: Color(0xFFF43F5E)),
            onPressed: _clearFilters,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Chip(
              backgroundColor: _isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981),
              avatar: Icon(
                _isOfflineMode ? Icons.wifi_off : Icons.wifi,
                color: Colors.white,
                size: 14,
              ),
              label: Text(
                _isOfflineMode ? 'OFFLINE' : 'ONLINE',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filter Card Section
              _buildFilterCard(),

              const SizedBox(height: 16),

              // Filtered Count & Results Section
              if (_filteredPoles.isNotEmpty) _buildResultsSummaryBar(),

              const SizedBox(height: 12),

              // Table View or Empty State
              _buildTableSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'FILTER CRITERIA',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all, size: 16, color: Color(0xFFF43F5E)),
                label: const Text(
                  'Clear Filters',
                  style: TextStyle(color: Color(0xFFF43F5E), fontSize: 13),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),

          // 1. Zone & Ward Row
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Zone',
                  value: _selectedZone,
                  hint: 'Select Zone',
                  items: _zones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                  onChanged: _onZoneChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Ward',
                  value: _selectedWard,
                  hint: _selectedZone == null ? 'Select Zone First' : 'Select Ward',
                  enabled: _selectedZone != null && _wards.isNotEmpty,
                  items: _wards.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                  onChanged: _onWardChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Pole With Old Lamp & Lamp Type Row
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Pole With Old Lamp',
                  value: _selectedPoleOldLamp,
                  hint: 'Select Classification',
                  items: const [
                    DropdownMenuItem(value: 'LED', child: Text('LED')),
                    DropdownMenuItem(value: 'Non-LED', child: Text('Non-LED')),
                    DropdownMenuItem(value: 'Empty', child: Text('Empty')),
                  ],
                  onChanged: _onPoleOldLampChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Lamp Type',
                  value: _selectedLampType,
                  hint: _selectedPoleOldLamp == null ? 'Select Old Lamp First' : 'Select Type',
                  enabled: _selectedPoleOldLamp != null && _lampTypes.isNotEmpty,
                  items: _lampTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: _onLampTypeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Starting Pole Dropdown (Core Proximity Trigger)
          _buildDropdownField<String>(
            label: 'Starting Pole (Geographical Proximity Reference)',
            value: _selectedStartingPole,
            hint: _filteredPoles.isEmpty
                ? 'No Filtered Poles Available'
                : 'Select Starting Pole to Calculate Distance',
            enabled: _filteredPoles.isNotEmpty,
            items: _startingPoles.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: _onStartingPoleChanged,
            accentColor: const Color(0xFF38BDF8),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
    Color? accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: enabled ? (accentColor ?? const Color(0xFFCBD5E1)) : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? (accentColor ?? const Color(0xFF475569)) : const Color(0xFF334155),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(
                hint,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: enabled ? items : [],
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSummaryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.pin_drop, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              Text(
                'Filtered Poles: ${_filteredPoles.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (_selectedStartingPole != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0369A1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Start: $_selectedStartingPole',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableSection() {
    if (_selectedZone == null) {
      return _buildInstructionState(
        icon: Icons.filter_alt_outlined,
        message: 'Please select a Zone to begin filtering BBMP poles.',
      );
    }

    if (_filteredPoles.isEmpty) {
      return _buildInstructionState(
        icon: Icons.search_off,
        message: 'No pending poles match your selected filtering criteria.',
      );
    }

    if (_selectedStartingPole == null) {
      return _buildInstructionState(
        icon: Icons.near_me,
        message: 'Select a Starting Pole above to calculate distance-based ordering.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF334155),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(width: 36, child: Text('#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 3, child: Text('POLE NO.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 3, child: Text('DISTANCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 3, child: AlignmentTextRight('LOCATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            ),
          ),

          // Scrollable Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _orderedPoles.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF334155)),
            itemBuilder: (context, index) {
              final pole = _orderedPoles[index];
              final isStartingPole = pole.poleNumber == _selectedStartingPole;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: isStartingPole ? const Color(0xFF0284C7).withOpacity(0.15) : null,
                child: Row(
                  children: [
                    // Order #
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${pole.order}',
                        style: TextStyle(
                          color: isStartingPole ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    // Pole Number
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Text(
                            pole.poleNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (isStartingPole) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.star, color: Color(0xFFF59E0B), size: 14),
                          ],
                        ],
                      ),
                    ),

                    // Distance
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          pole.distanceFormatted,
                          style: TextStyle(
                            color: pole.distanceMeters == 0 ? const Color(0xFF34D399) : const Color(0xFFE2E8F0),
                            fontWeight: pole.distanceMeters == 0 ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                    // Google Maps View Action
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => _openGoogleMaps(pole.googleMapsUrl),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('📍', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Text(
                                  'Map',
                                  style: TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFF64748B)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class AlignmentTextRight extends StatelessWidget {
  final String text;
  final TextStyle style;
  const AlignmentTextRight(this.text, {Key? key, required this.style}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(text, style: style),
    );
  }
}
