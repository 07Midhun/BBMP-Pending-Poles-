import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/pole_model.dart';
import '../filters/filter_providers.dart';
import 'poles_providers.dart';
import 'pole_info_sheet.dart'; 
import '../images/image_upload_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: AppTheme.error),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to connect to live poles: $err',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.error, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.refresh(polesProvider),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('RETRY CONNECTING'),
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
              final poles = ref.read(polesProvider).value ?? [];
              _showStartingPoleDialog(context, ref, poles);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off_outlined, size: 48, color: Colors.white38),
              const SizedBox(height: 12),
              const Text(
                'No pending poles found for this exact filter combination.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Try selecting a different ward or lamp type, or tap Refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => ref.refresh(polesProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('REFRESH POLES'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppTheme.surface),
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
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _openMap(context, pole),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions, color: AppTheme.cyan, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Map',
                            style: TextStyle(
                              color: AppTheme.cyan,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _openMap(BuildContext context, Pole pole) async {
    // 1. Primary: Native geo intent for direct Google Maps navigation
    final geoUri = Uri.parse(
      'geo:${pole.latitude},${pole.longitude}?q=${pole.latitude},${pole.longitude}(${Uri.encodeComponent(pole.poleNumber)})',
    );

    // 2. Fallback: Universal Google Maps web link
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${pole.latitude},${pole.longitude}',
    );

    try {
      final launched = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {}

    try {
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {}

    try {
      await launchUrl(webUri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open map: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
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

  void _showStartingPoleDialog(BuildContext context, WidgetRef ref, List<Pole> poles) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.background,
          title: const Text('Select Starting Pole', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: poles.length,
              itemBuilder: (context, index) {
                final pole = poles[index];
                return ListTile(
                  title: Text(pole.poleNumber, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    ref.read(startingPoleProvider.notifier).state = pole;
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildUploadStatusCell(WidgetRef ref, String poleNumber) {
    // This watch makes the row update when this specific pole's upload state changes.
    // In a large table, Consumer widgets per row are better for performance, but this is fine.
    final uploadStates = ref.watch(uploadStateProvider)[poleNumber] ?? [];
    final driveStatusAsync = ref.watch(driveStatusProvider(poleNumber));

    int completed = 0;
    int failed = 0;
    int uploading = 0;

    for (var state in uploadStates) {
      if (state.status == UploadStatus.success) completed++;
      if (state.status == UploadStatus.failed) failed++;
      if (state.status == UploadStatus.uploading) uploading++;
    }

    if (failed > 0) {
      return Text('⚠ $completed/3', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold));
    } else if (uploading > 0) {
      return Text('📤 $completed/3', style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold));
    }

    final int driveCount = driveStatusAsync.value ?? 0;
    final int finalCount = completed > driveCount ? completed : driveCount;

    if (driveStatusAsync.isLoading && finalCount == 0) {
      return const SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      );
    }

    if (finalCount >= 3) {
      return Text('✓ 3/3', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold));
    } else if (finalCount > 0) {
      return Text('$finalCount/3', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));
    }

    return const Text('0/3', style: TextStyle(color: Colors.white70));
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
