import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/pole_model.dart';
import '../../app/theme.dart';
import '../../services/api_service.dart';
import '../images/image_upload_provider.dart';
import 'poles_providers.dart';

class PoleInfoSheet extends ConsumerWidget {
  final Pole pole;

  const PoleInfoSheet({Key? key, required this.pole}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadStates = ref.watch(uploadStateProvider)[pole.poleNumber] ?? [];
    final cloudImagesAsync = ref.watch(poleImagesProvider(pole.poleNumber));
    final driveStatusAsync = ref.watch(driveStatusProvider(pole.poleNumber));

    final cloudImages = cloudImagesAsync.value ?? {};
    int uploadedCount = 0;
    for (int slot = 1; slot <= 3; slot++) {
      final hasCloud = cloudImages.containsKey(slot);
      final hasLocal = uploadStates.any((s) => s.slot == slot && s.status == UploadStatus.success);
      if (hasCloud || hasLocal) uploadedCount++;
    }
    int driveCount = driveStatusAsync.value ?? 0;
    int totalCount = uploadedCount > driveCount ? uploadedCount : driveCount;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
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
                    _buildInfoRow(
                      'Status',
                      totalCount >= 3 ? 'Completed (3/3)' : (totalCount > 0 ? 'In Progress ($totalCount/3)' : 'Pending (0/3)'),
                      valueColor: totalCount >= 3 ? AppTheme.success : (totalCount > 0 ? AppTheme.warning : Colors.white70),
                    ),
                    _buildInfoRow('Pole with Old Lamp', pole.poleOldLamp),
                    _buildInfoRow('Lamp Type', pole.lampType),
                    const Divider(height: 32, color: Colors.white24),
                    
                    _buildSectionTitle('LOCATION'),
                    _buildInfoRow('Latitude', pole.latitude.toStringAsFixed(6)),
                    _buildInfoRow('Longitude', pole.longitude.toStringAsFixed(6)),
                    _buildInfoRow('GPS Accuracy', '4.8 m'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openMap(context, pole),
                      icon: Icon(Icons.directions, color: AppTheme.cyan, size: 18),
                      label: const Text('OPEN IN GOOGLE MAPS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.cyan,
                        side: BorderSide(color: AppTheme.cyan),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                    const Divider(height: 32, color: Colors.white24),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle('IMAGES ($totalCount/3)'),
                        if (cloudImagesAsync.isLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Upload all 3 required images. If an image is incorrect, you can delete it and take a new one.',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    for (int slot = 1; slot <= 3; slot++)
                      _buildImageSlotCard(context, ref, slot, uploadStates, cloudImages),
                    
                    const SizedBox(height: 32),
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
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
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
      padding: const EdgeInsets.only(bottom: 12),
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

  Widget _buildImageSlotCard(
    BuildContext context,
    WidgetRef ref,
    int slot,
    List<ImageUploadState> uploadStates,
    Map<int, Map<String, dynamic>> cloudImages,
  ) {
    ImageUploadState? localState;
    for (var s in uploadStates) {
      if (s.slot == slot) {
        localState = s;
        break;
      }
    }

    final cloudImage = cloudImages[slot];
    final bool hasCloud = cloudImage != null;
    final bool hasLocalFile = localState != null;
    final bool isUploading = localState != null &&
        (localState.status == UploadStatus.uploading || localState.status == UploadStatus.pending);
    final bool isFailed = localState != null && localState.status == UploadStatus.failed;
    final bool isUploaded = hasCloud || (localState != null && localState.status == UploadStatus.success);

    String? imageUrl;
    if (cloudImage != null) {
      final backendPath = cloudImage['image_url']?.toString();
      if (backendPath != null && backendPath.isNotEmpty) {
        imageUrl = backendPath.startsWith('http')
            ? backendPath
            : '${ApiService.activeBaseUrl.replaceFirst('/api/v1', '')}$backendPath';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUploaded
              ? AppTheme.success.withValues(alpha: 0.6)
              : (isFailed ? AppTheme.error.withValues(alpha: 0.6) : Colors.white12),
          width: isUploaded ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Thumbnail Preview
          GestureDetector(
            onTap: () {
              if (hasLocalFile && localState?.file != null) {
                _showFullScreenImage(context, file: localState?.file, slot: slot);
              } else if (imageUrl != null) {
                _showFullScreenImage(context, url: imageUrl, slot: slot);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: hasLocalFile && localState?.file != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(localState!.file, fit: BoxFit.cover),
                          if (isUploading)
                            Container(
                              color: Colors.black54,
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    value: localState.progress > 0 ? localState.progress : null,
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : (imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.broken_image,
                              color: Colors.white38,
                              size: 28,
                            ),
                          )
                        : const Icon(
                            Icons.add_a_photo_outlined,
                            color: Colors.white38,
                            size: 28,
                          )),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Details Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image $slot',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                if (isUploading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.warning),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        localState?.progress != null && localState!.progress > 0
                            ? 'Uploading ${(localState.progress * 100).toInt()}%'
                            : 'Uploading...',
                        style: const TextStyle(fontSize: 12, color: AppTheme.warning),
                      ),
                    ],
                  )
                else if (isFailed)
                  Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.error, size: 14),
                      const SizedBox(width: 4),
                      const Text(
                        'Upload failed',
                        style: TextStyle(fontSize: 12, color: AppTheme.error),
                      ),
                    ],
                  )
                else if (isUploaded)
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.success, size: 14),
                      const SizedBox(width: 4),
                      const Text(
                        'Uploaded to Drive & Sheets',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'No image uploaded',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
              ],
            ),
          ),

          // Actions Row (Delete button if image exists; Camera/Gallery if empty)
          if (isUploaded || hasLocalFile) ...[
            if (isFailed)
              IconButton(
                tooltip: 'Retry Upload',
                icon: Icon(Icons.refresh, color: AppTheme.warning, size: 22),
                onPressed: () {
                  ref.read(uploadStateProvider.notifier).retrySlotUpload(pole.poleNumber, slot);
                },
              ),
            IconButton(
              tooltip: 'Delete Image $slot',
              icon: const Icon(
                Icons.delete_outline,
                color: Color(0xFFF43F5E),
                size: 24,
              ),
              onPressed: () => _confirmAndDeleteImage(context, ref, pole.poleNumber, slot),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Camera',
              icon: Icon(Icons.camera_alt, color: AppTheme.cyan, size: 22),
              onPressed: () {
                ref.read(uploadStateProvider.notifier).pickAndUploadSlotImage(
                      pole.poleNumber,
                      slot,
                      ImageSource.camera,
                    );
              },
            ),
            IconButton(
              tooltip: 'Gallery',
              icon: const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 22),
              onPressed: () {
                ref.read(uploadStateProvider.notifier).pickAndUploadSlotImage(
                      pole.poleNumber,
                      slot,
                      ImageSource.gallery,
                    );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _confirmAndDeleteImage(
    BuildContext context,
    WidgetRef ref,
    String poleNumber,
    int slot,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF43F5E), size: 26),
            SizedBox(width: 10),
            Text('Delete Image?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete Image $slot for pole $poleNumber?\n\nThis will remove the file from Google Drive and clear the link in Google Sheets.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF43F5E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Text('Deleting Image $slot...'),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  backgroundColor: AppTheme.surface,
                ),
              );

              final success = await ApiService.deletePoleImage(poleNumber, slot);
              await ref.read(uploadStateProvider.notifier).deleteSlotImage(poleNumber, slot);
              ref.refresh(poleImagesProvider(poleNumber));
              ref.refresh(driveStatusProvider(poleNumber));
              ref.refresh(polesProvider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Image $slot deleted successfully from Drive and Sheets!'
                          : 'Image $slot removed.',
                    ),
                    backgroundColor: success ? AppTheme.success : AppTheme.warning,
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, {File? file, String? url, required int slot}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: file != null
                    ? Image.file(file, fit: BoxFit.contain)
                    : (url != null
                        ? Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('Unable to load full preview', style: TextStyle(color: Colors.white70)),
                            ),
                          )
                        : const SizedBox.shrink()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
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

  Future<void> _openMap(BuildContext context, Pole pole) async {
    final geoUri = Uri.parse(
      'geo:${pole.latitude},${pole.longitude}?q=${pole.latitude},${pole.longitude}(${Uri.encodeComponent(pole.poleNumber)})',
    );
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
}
