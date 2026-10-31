import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/upload_service.dart';
import '../../services/location_service.dart';

enum UploadStatus { pending, uploading, success, failed }

class ImageUploadState {
  final File file;
  final int slot;
  final UploadStatus status;
  final double progress;
  final String? error;
  
  // Metadata
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime capturedAt;

  ImageUploadState({
    required this.file,
    this.slot = 1,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.error,
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.capturedAt,
  });

  ImageUploadState copyWith({
    File? file,
    int? slot,
    UploadStatus? status,
    double? progress,
    String? error,
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? capturedAt,
  }) {
    return ImageUploadState(
      file: file ?? this.file,
      slot: slot ?? this.slot,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

// Map from PoleNumber -> List of ImageUploadState
final uploadStateProvider = StateNotifierProvider<UploadStateNotifier, Map<String, List<ImageUploadState>>>((ref) {
  return UploadStateNotifier(
    ref.watch(uploadServiceProvider),
    ref.watch(locationServiceProvider),
  );
});

class UploadStateNotifier extends StateNotifier<Map<String, List<ImageUploadState>>> {
  final UploadService _uploadService;
  final LocationService _locationService;
  final ImagePicker _picker = ImagePicker();

  UploadStateNotifier(this._uploadService, this._locationService) : super({});

  Future<void> pickAndUploadSlotImage(String poleNumber, int slot, ImageSource source) async {
    final dynamic pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (pickedFile == null) return;

    final location = await _locationService.getCurrentLocation();
    final file = File(pickedFile.path);
    final newState = ImageUploadState(
      file: file,
      slot: slot,
      status: UploadStatus.pending,
      latitude: location?.latitude,
      longitude: location?.longitude,
      accuracy: location?.accuracy,
      capturedAt: DateTime.now(),
    );

    // Update state for this specific slot
    final currentList = List<ImageUploadState>.from(state[poleNumber] ?? []);
    final existingIndex = currentList.indexWhere((s) => s.slot == slot);
    if (existingIndex >= 0) {
      currentList[existingIndex] = newState;
    } else {
      currentList.add(newState);
    }

    state = {
      ...state,
      poleNumber: currentList,
    };

    await _startSlotUpload(poleNumber, slot, file);
  }

  Future<void> pickAndUploadImage(String poleNumber, ImageSource source) async {
    // Find first available slot (1, 2, or 3)
    final existingSlots = (state[poleNumber] ?? []).map((s) => s.slot).toSet();
    int targetSlot = 1;
    for (int s = 1; s <= 3; s++) {
      if (!existingSlots.contains(s)) {
        targetSlot = s;
        break;
      }
    }
    await pickAndUploadSlotImage(poleNumber, targetSlot, source);
  }

  Future<void> retryUpload(String poleNumber, int index) async {
    final list = state[poleNumber] ?? [];
    if (index < 0 || index >= list.length) return;
    final imageState = list[index];
    if (imageState.status != UploadStatus.failed) return;
    
    await _startSlotUpload(poleNumber, imageState.slot, imageState.file);
  }

  Future<void> retrySlotUpload(String poleNumber, int slot) async {
    final list = state[poleNumber] ?? [];
    final idx = list.indexWhere((s) => s.slot == slot);
    if (idx >= 0) {
      await retryUpload(poleNumber, idx);
    }
  }

  Future<void> deleteSlotImage(String poleNumber, int slot) async {
    // Remove from local in-memory upload state
    final currentList = List<ImageUploadState>.from(state[poleNumber] ?? []);
    currentList.removeWhere((s) => s.slot == slot);
    state = {
      ...state,
      poleNumber: currentList,
    };

    // Call backend deletion
    await _uploadService.deleteImage(poleNumber: poleNumber, imageSlot: slot);
  }

  Future<void> _startSlotUpload(String poleNumber, int slot, File file) async {
    _updateSlotState(poleNumber, slot, UploadStatus.uploading, progress: 0.0);

    try {
      await _uploadService.uploadImage(
        poleNumber: poleNumber,
        imageFile: file,
        imageSlot: slot,
        onProgress: (progress) {
          _updateSlotState(poleNumber, slot, UploadStatus.uploading, progress: progress);
        },
      );

      // Success
      _updateSlotState(poleNumber, slot, UploadStatus.success, progress: 1.0);
    } catch (e) {
      // Failed
      _updateSlotState(poleNumber, slot, UploadStatus.failed, error: e.toString());
    }
  }

  void _updateSlotState(String poleNumber, int slot, UploadStatus status, {double? progress, String? error}) {
    final currentList = List<ImageUploadState>.from(state[poleNumber] ?? []);
    final idx = currentList.indexWhere((s) => s.slot == slot);
    if (idx >= 0) {
      final old = currentList[idx];
      currentList[idx] = old.copyWith(
        status: status,
        progress: progress ?? old.progress,
        error: error,
      );
      state = {
        ...state,
        poleNumber: currentList,
      };
    }
  }
}
