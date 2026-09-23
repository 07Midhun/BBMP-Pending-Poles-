import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../images/image_upload_provider.dart';

class ImageDetailScreen extends StatelessWidget {
  final String poleNumber;
  final ImageUploadState imageState;

  const ImageDetailScreen({
    Key? key,
    required this.poleNumber,
    required this.imageState,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IMAGE'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: FileImage(imageState.file),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoRow('Pole Number', poleNumber),
            _buildInfoRow('Image Type', 'Pole'), // Placeholder until types are added
            _buildInfoRow('Latitude', imageState.latitude?.toStringAsFixed(6) ?? 'Unknown'),
            _buildInfoRow('Longitude', imageState.longitude?.toStringAsFixed(6) ?? 'Unknown'),
            _buildInfoRow('GPS Accuracy', imageState.accuracy != null ? '${imageState.accuracy!.toStringAsFixed(1)} m' : 'Unknown'),
            const Divider(height: 32, color: Colors.white24),
            _buildInfoRow('Captured', _formatDateTime(imageState.capturedAt)),
            _buildInfoRow('Uploaded', imageState.status == UploadStatus.success ? _formatDateTime(imageState.capturedAt.add(const Duration(seconds: 5))) : '-'),
            _buildInfoRow('File Size', '${(imageState.file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB'),
            _buildInfoRow(
              'Upload Status',
              imageState.status == UploadStatus.success ? '✓ Uploaded' : (imageState.status == UploadStatus.failed ? '⚠ Failed' : 'Pending'),
              valueColor: imageState.status == UploadStatus.success ? AppTheme.success : (imageState.status == UploadStatus.failed ? AppTheme.error : AppTheme.warning),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () {
                // View on map action
              },
              icon: const Icon(Icons.map),
              label: const Text('VIEW ON MAP'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor ?? Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day} ${_monthStr(dt.month)} ${dt.year} • ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _monthStr(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
