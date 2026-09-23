import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pole_model.dart';
import '../../app/theme.dart';
import '../images/image_upload_provider.dart';

class PoleInfoSheet extends ConsumerWidget {
  final Pole pole;

  const PoleInfoSheet({Key? key, required this.pole}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadStates = ref.watch(uploadStateProvider)[pole.poleNumber] ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSectionTitle('POLE INFORMATION'),
                    _buildInfoRow('Region', pole.region),
                    _buildInfoRow('Zone', pole.zone),
                    _buildInfoRow('Ward', pole.ward),
                    _buildInfoRow('Distance', pole.distanceFormatted),
                    _buildInfoRow('Status', 'Pending', valueColor: AppTheme.warning),
                    _buildInfoRow('Pole with Old Lamp', pole.poleOldLamp),
                    _buildInfoRow('Lamp Type', pole.lampType),
                    const Divider(height: 32, color: Colors.white24),
                    
                    _buildSectionTitle('LOCATION'),
                    _buildInfoRow('Latitude', pole.latitude.toStringAsFixed(6)),
                    _buildInfoRow('Longitude', pole.longitude.toStringAsFixed(6)),
                    _buildInfoRow('GPS Accuracy', '4.8 m'), // Mocked until Geolocator is added
                    const Divider(height: 32, color: Colors.white24),
                    
                    _buildSectionTitle('IMAGES'),
                    _buildImagesSection(context, ref, uploadStates),
                    
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        ref.read(uploadStateProvider.notifier).pickAndUploadImage(pole.poleNumber);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('UPLOAD IMAGE'),
                    ),
                    const SizedBox(height: 32), // padding for bottom
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortenPoleNumber(pole.poleNumber),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  pole.poleNumber,
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white54,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesSection(BuildContext context, WidgetRef ref, List<ImageUploadState> uploadStates) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...uploadStates.asMap().entries.map((entry) {
              return _buildImageItem(context, ref, entry.key, entry.value);
            }),
            _buildAddImageButton(ref),
          ],
        ),
      ],
    );
  }

  Widget _buildImageItem(BuildContext context, WidgetRef ref, int index, ImageUploadState state) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state.status == UploadStatus.success
              ? AppTheme.success
              : (state.status == UploadStatus.failed ? AppTheme.error : Colors.white24),
        ),
        image: DecorationImage(
          image: FileImage(state.file),
          fit: BoxFit.cover,
          colorFilter: state.status != UploadStatus.success 
            ? ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken) 
            : null,
        ),
      ),
      alignment: Alignment.center,
      child: _buildUploadOverlay(ref, index, state),
    );
  }

  Widget _buildUploadOverlay(WidgetRef ref, int index, ImageUploadState state) {
    if (state.status == UploadStatus.uploading || state.status == UploadStatus.pending) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(state.progress * 100).toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      );
    } else if (state.status == UploadStatus.failed) {
      return IconButton(
        icon: Icon(Icons.refresh, color: AppTheme.error),
        onPressed: () {
          ref.read(uploadStateProvider.notifier).retryUpload(pole.poleNumber, index);
        },
      );
    } else {
      return const SizedBox.shrink(); // Success has no overlay
    }
  }

  Widget _buildAddImageButton(WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(uploadStateProvider.notifier).pickAndUploadImage(pole.poleNumber);
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan, style: BorderStyle.solid),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppTheme.cyan),
            const SizedBox(height: 4),
            Text('Upload', style: TextStyle(fontSize: 10, color: AppTheme.cyan)),
          ],
        ),
      ),
    );
  }

  String _shortenPoleNumber(String poleNumber) {
    final parts = poleNumber.split('-');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}-${parts[parts.length - 1]}';
    }
    return poleNumber;
  }
}
