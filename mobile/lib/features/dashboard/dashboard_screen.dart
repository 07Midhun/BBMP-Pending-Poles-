import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../images/image_upload_provider.dart';
import '../images/image_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // For Phase 4, we aggregate stats from the uploadStateProvider in memory.
    // In Phase 5, this will be powered by SQLite.
    final uploadStatesMap = ref.watch(uploadStateProvider);
    
    int completedPoles = 0;
    int uploadedImages = 0;
    int failedUploads = 0;
    int totalPolesWorkedOn = uploadStatesMap.keys.length;

    final List<MapEntry<String, List<ImageUploadState>>> recentUploads = [];

    uploadStatesMap.forEach((poleNumber, states) {
      bool poleCompleted = true;
      for (var state in states) {
        if (state.status == UploadStatus.success) uploadedImages++;
        else if (state.status == UploadStatus.failed) failedUploads++;
        else poleCompleted = false;
      }
      if (states.isNotEmpty && poleCompleted) completedPoles++;
      
      if (states.isNotEmpty) {
        recentUploads.add(MapEntry(poleNumber, states));
      }
    });

    // Sort by latest captured
    recentUploads.sort((a, b) {
      final aLatest = a.value.map((e) => e.capturedAt).reduce((value, element) => value.isAfter(element) ? value : element);
      final bLatest = b.value.map((e) => e.capturedAt).reduce((value, element) => value.isAfter(element) ? value : element);
      return bLatest.compareTo(aLatest);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY WORK'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _buildStatsGrid(totalPolesWorkedOn, completedPoles, uploadedImages, failedUploads),
            const SizedBox(height: 32),
            const Text(
              'RECENT UPLOADS',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.2),
            ),
            const SizedBox(height: 16),
            ...recentUploads.map((entry) => _buildRecentUploadCard(context, entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(int poles, int completed, int images, int failed) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(poles.toString(), 'POLES', AppTheme.cyan),
        _buildStatCard(completed.toString(), 'COMPLETED', AppTheme.success),
        _buildStatCard(images.toString(), 'IMAGES', AppTheme.cyanLight),
        _buildStatCard(failed.toString(), 'FAILED', failed > 0 ? AppTheme.error : Colors.white70),
      ],
    );
  }

  Widget _buildStatCard(String value, String label, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: valueColor),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.0),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentUploadCard(BuildContext context, String poleNumber, List<ImageUploadState> states) {
    int successCount = states.where((s) => s.status == UploadStatus.success).length;
    int failedCount = states.where((s) => s.status == UploadStatus.failed).length;
    
    bool isFailed = failedCount > 0;
    bool isPending = states.any((s) => s.status == UploadStatus.pending || s.status == UploadStatus.uploading);
    bool isSuccess = !isFailed && !isPending && successCount > 0;

    IconData statusIcon = Icons.check_circle;
    Color statusColor = AppTheme.success;

    if (isFailed) {
      statusIcon = Icons.error;
      statusColor = AppTheme.error;
    } else if (isPending) {
      statusIcon = Icons.hourglass_empty;
      statusColor = AppTheme.warning;
    }

    final latestTime = states.map((e) => e.capturedAt).reduce((v, e) => v.isAfter(e) ? v : e);
    final timeFormatted = '${latestTime.hour}:${latestTime.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(poleNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          isFailed ? 'Upload interrupted' : '${states.length} images',
          style: TextStyle(color: isFailed ? AppTheme.error : Colors.white70),
        ),
        trailing: Text(timeFormatted, style: const TextStyle(color: Colors.white54)),
        onTap: () {
          if (states.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageDetailScreen(
                  poleNumber: poleNumber,
                  imageState: states.first, // Assuming viewing latest/first for now
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
