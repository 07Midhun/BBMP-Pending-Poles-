import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/pole_model.dart';
import '../filters/filter_providers.dart';
import 'poles_providers.dart';
import 'pole_info_sheet.dart'; 
import '../images/image_upload_provider.dart';

class PolesScreen extends ConsumerWidget {
  const PolesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polesAsync = ref.watch(polesProvider);
    final startingPole = ref.watch(startingPoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtered Pending Poles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              ref.invalidate(polesProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterSummary(ref),
          _buildStartingPoleSection(context, ref, startingPole),
          Expanded(
            child: polesAsync.when(
              data: (poles) => _buildPolesTable(context, ref, poles),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: AppTheme.error))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSummary(WidgetRef ref) {
    final region = ref.read(selectedRegionProvider);
    final zone = ref.read(selectedZoneProvider);
    final ward = ref.read(selectedWardProvider);
    final oldLamp = ref.read(selectedPoleOldLampProvider);
    final lampType = ref.read(selectedLampTypeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (region != null) _Chip(region),
          if (zone != null) _Chip(zone),
          if (ward != null) _Chip(ward),
          if (oldLamp != null && lampType != null) _Chip('$oldLamp • $lampType'),
        ],
      ),
    );
  }

  Widget _buildStartingPoleSection(BuildContext context, WidgetRef ref, Pole? startingPole) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STARTING POLE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          const Text(
            'Geographical Proximity Reference',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              // TODO: Implement starting pole search/selection
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    startingPole != null ? startingPole.poleNumber : 'Select starting pole...',
                    style: TextStyle(
                      color: startingPole != null ? Colors.white : Colors.white54,
                      fontWeight: startingPole != null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Icon(Icons.search, color: Colors.white54),
                ],
              ),
            ),
          ),
          if (startingPole != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star, color: AppTheme.warning, size: 16),
                const SizedBox(width: 4),
                Text(
                  'STARTING POLE: ${startingPole.poleNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            )
          ]
        ],
      ),
    );
  }

  Widget _buildPolesTable(BuildContext context, WidgetRef ref, List<Pole> poles) {
    if (poles.isEmpty) {
      return const Center(child: Text('No poles found for these filters.'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(AppTheme.surface),
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('POLE NO.', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('DIST', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('PICS', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('MAP', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: List.generate(poles.length, (index) {
            final pole = poles[index];
            return DataRow(
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(
                  InkWell(
                    onTap: () {
                      _showPoleInfo(context, pole);
                    },
                    child: Text(
                      _shortenPoleNumber(pole.poleNumber),
                      style: TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                DataCell(Text(pole.distanceFormatted)),
                DataCell(
                  _buildUploadStatusCell(ref, pole.poleNumber),
                ),
                DataCell(
                  InkWell(
                    onTap: () {
                      // Map action
                    },
                    child: const Text('Map', style: TextStyle(color: Colors.blueAccent)),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  String _shortenPoleNumber(String poleNumber) {
    // Keep it readable but not unnecessarily truncated.
    final parts = poleNumber.split('-');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}-${parts[parts.length - 1]}';
    }
    return poleNumber;
  }

  void _showPoleInfo(BuildContext context, Pole pole) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PoleInfoSheet(pole: pole),
    );
  }
  Widget _buildUploadStatusCell(WidgetRef ref, String poleNumber) {
    // This watch makes the row update when this specific pole's upload state changes.
    // In a large table, Consumer widgets per row are better for performance, but this is fine.
    final uploadStates = ref.watch(uploadStateProvider)[poleNumber] ?? [];

    if (uploadStates.isEmpty) {
      return const Text('0/3', style: TextStyle(color: Colors.white70));
    }

    int completed = 0;
    int failed = 0;
    int uploading = 0;

    for (var state in uploadStates) {
      if (state.status == UploadStatus.success) completed++;
      if (state.status == UploadStatus.failed) failed++;
      if (state.status == UploadStatus.uploading) uploading++;
    }

    final total = uploadStates.length;

    if (failed > 0) {
      return Text('⚠ $completed/$total', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold));
    } else if (uploading > 0) {
      return Text('📤 $completed/$total', style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold));
    } else if (completed == total && total > 0) {
      return Text('✓ $completed/$total', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold));
    }

    return Text('$completed/$total', style: const TextStyle(color: Colors.white70));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }
}
