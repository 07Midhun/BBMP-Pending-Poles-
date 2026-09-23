import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'filter_providers.dart';
import '../poles/poles_screen.dart'; // I will create this later

class FilterScreen extends ConsumerWidget {
  const FilterScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hardcode to online as requested by user
    final isOnline = true;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('POLETRACE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              'BBMP FIELD OPERATIONS',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(backendOnlineProvider);
              ref.invalidate(regionsProvider);
              ref.invalidate(zonesProvider);
              ref.invalidate(wardsProvider);
              ref.invalidate(lampTypesProvider);
            },
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: const _StatusIndicator(isOnline: true),
            ),
          )
        ],
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: _FilterForm(),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isOnline;

  const _StatusIndicator({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline ? AppTheme.success.withOpacity(0.5) : AppTheme.error.withOpacity(0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: isOnline ? AppTheme.success : AppTheme.error,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'LIVE • IoT SYNCED' : 'OFFLINE • CACHED DATA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isOnline ? AppTheme.success : AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterForm extends ConsumerWidget {
  const _FilterForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regionsAsync = ref.watch(regionsProvider);
    final zonesAsync = ref.watch(zonesProvider);
    final wardsAsync = ref.watch(wardsProvider);
    final oldLamps = ref.watch(poleOldLampOptionsProvider);
    final lampTypesAsync = ref.watch(lampTypesProvider);

    final selectedRegion = ref.watch(selectedRegionProvider);
    final selectedZone = ref.watch(selectedZoneProvider);
    final selectedWard = ref.watch(selectedWardProvider);
    final selectedOldLamp = ref.watch(selectedPoleOldLampProvider);
    final selectedLampType = ref.watch(selectedLampTypeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDropdown<String>(
          label: 'REGION',
          hint: 'Select Region',
          value: selectedRegion,
          items: regionsAsync.value ?? [],
          onChanged: (val) {
            ref.read(selectedRegionProvider.notifier).state = val;
            ref.read(selectedZoneProvider.notifier).state = null;
            ref.read(selectedWardProvider.notifier).state = null;
          },
          isLoading: regionsAsync.isLoading,
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          label: 'ZONE',
          hint: 'Select Zone',
          value: selectedZone,
          items: zonesAsync.value ?? [],
          onChanged: (val) {
            ref.read(selectedZoneProvider.notifier).state = val;
            ref.read(selectedWardProvider.notifier).state = null;
          },
          isLoading: zonesAsync.isLoading,
          enabled: selectedRegion != null,
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          label: 'WARD',
          hint: 'Select Ward',
          value: selectedWard,
          items: wardsAsync.value ?? [],
          onChanged: (val) {
            ref.read(selectedWardProvider.notifier).state = val;
          },
          isLoading: wardsAsync.isLoading,
          enabled: selectedZone != null,
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          label: 'POLE WITH OLD LAMP',
          hint: 'Select Type',
          value: selectedOldLamp,
          items: oldLamps,
          onChanged: (val) {
            ref.read(selectedPoleOldLampProvider.notifier).state = val;
            ref.read(selectedLampTypeProvider.notifier).state = null;
          },
          enabled: true,
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          label: 'LAMP TYPE',
          hint: 'Select Lamp Type',
          value: selectedLampType,
          items: lampTypesAsync.value ?? [],
          onChanged: (val) {
            ref.read(selectedLampTypeProvider.notifier).state = val;
          },
          isLoading: lampTypesAsync.isLoading,
          enabled: selectedOldLamp != null,
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            if (selectedRegion == null) {
              _showError(context, 'Please select a region');
              return;
            }
            if (selectedZone == null) {
              _showError(context, 'Please select a zone');
              return;
            }
            if (selectedWard == null) {
              _showError(context, 'Please select a ward');
              return;
            }
            if (selectedOldLamp == null) {
              _showError(context, 'Please select Pole with Old Lamp');
              return;
            }
            if (selectedLampType == null) {
              _showError(context, 'Please select a Lamp Type');
              return;
            }

            // Navigate to PolesScreen with the selected filters
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PolesScreen(),
              ),
            );
          },
          child: const Text('APPLY FILTERS'),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () {
            ref.read(selectedRegionProvider.notifier).state = null;
            ref.read(selectedZoneProvider.notifier).state = null;
            ref.read(selectedWardProvider.notifier).state = null;
            ref.read(selectedPoleOldLampProvider.notifier).state = null;
            ref.read(selectedLampTypeProvider.notifier).state = null;
          },
          child: const Text('RESET FILTERS'),
        ),
      ],
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    bool isLoading = false,
    bool enabled = true,
  }) {
    // If the value is not in the list, set it to null to avoid errors.
    if (value != null && items.isNotEmpty && !items.contains(value)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(null);
      });
    }

    final effectiveValue = items.contains(value) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: enabled ? Colors.white70 : Colors.white30,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: effectiveValue,
          hint: Text(hint),
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: AppTheme.surface,
          items: items.map((T item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(item.toString()),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_drop_down),
        ),
      ],
    );
  }
}
