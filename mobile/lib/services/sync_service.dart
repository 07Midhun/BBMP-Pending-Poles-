import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  bool _isSyncing = false;

  SyncService._init() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // If any of the results indicate we are connected to mobile or wifi
      if (results.any((r) => r == ConnectivityResult.mobile || r == ConnectivityResult.wifi)) {
        syncPendingUploads();
      }
    });
  }

  Future<void> syncPendingUploads() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final hasInternet = await ApiService.checkHealth();
      if (!hasInternet) {
        _isSyncing = false;
        return;
      }

      final pending = await DatabaseService.instance.getPendingUploads();
      
      for (var item in pending) {
        final id = item['id'] as int;
        final poleNumber = item['pole_number'] as String;
        final imagePath = item['image_path'] as String;
        final imageSlot = item['image_slot'] as int;

        final file = File(imagePath);
        if (!await file.exists()) {
          // File deleted locally, remove from queue
          await DatabaseService.instance.markUploadComplete(id);
          continue;
        }

        try {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('${ApiService.activeBaseUrl}/poles/$poleNumber/upload-image'),
          );
          request.fields['image_slot'] = imageSlot.toString();
          request.files.add(
            await http.MultipartFile.fromPath('file', file.path),
          );

          final response = await request.send();
          if (response.statusCode == 200) {
            // Upload successful, clear from queue
            await DatabaseService.instance.markUploadComplete(id);
            // Optionally delete the local file after upload
            await file.delete();
            debugPrint('Synced offline image $imageSlot for pole $poleNumber');
          }
        } catch (e) {
          debugPrint('Failed to sync $poleNumber: $e');
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<String> saveImageLocally(String originalPath, String poleNumber, int slot) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'offline_${poleNumber}_slot$slot.jpg';
    final savedImage = File(originalPath).copySync('${appDir.path}/$fileName');
    
    // Add to DB queue
    await DatabaseService.instance.addPendingUpload(poleNumber, savedImage.path, slot);
    
    // Attempt sync immediately in case we are online
    syncPendingUploads();
    
    return savedImage.path;
  }
}
