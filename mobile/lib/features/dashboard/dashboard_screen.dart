import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../images/image_upload_provider.dart';
import '../images/image_detail_screen.dart';
import '../filters/filter_providers.dart';
import '../../services/api_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    await ApiService.refreshUserStats();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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

    final region = ref.watch(selectedRegionProvider) ?? 'Any';
    final zone = ref.watch(selectedZoneProvider) ?? 'Any';
    final ward = ref.watch(selectedWardProvider) ?? 'Any';
    final username = ApiService.loggedInUser ?? 'Technician';

    return Scaffold(
      appBar: AppBar(
        title: const Text('TECHNICIAN DASHBOARD'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Technician Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.cyan.withValues(alpha: 0.2), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.cyan,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username.toUpperCase(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              'Field Technician',
                              style: TextStyle(fontSize: 12, color: AppTheme.cyan),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCol('Region', region),
                      _buildInfoCol('Zone', zone),
                      _buildInfoCol('Ward', ward),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Lifetime Uploads', style: TextStyle(color: Colors.white70)),
                        Text('${ApiService.uploadCount}', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success, fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'SESSION STATS',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.2),
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

  Widget _buildInfoCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
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
    // ignore: unused_local_variable
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
