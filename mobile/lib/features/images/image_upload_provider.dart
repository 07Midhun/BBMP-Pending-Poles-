import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/upload_service.dart';
import '../../services/location_service.dart';

enum UploadStatus { pending, uploading, success, failed }

class ImageUploadState {
  final File file;
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

  Future<void> pickAndUploadImage(String poleNumber) async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    final location = await _locationService.getCurrentLocation();
    final file = File(pickedFile.path);
    final newState = ImageUploadState(
      file: file, 
      status: UploadStatus.pending,
      latitude: location?.latitude,
      longitude: location?.longitude,
      accuracy: location?.accuracy,
      capturedAt: DateTime.now(),
    );

    // Add to state
    state = {
      ...state,
      poleNumber: [...(state[poleNumber] ?? []), newState],
    };

    final int index = state[poleNumber]!.length - 1;
    await _startUpload(poleNumber, index, file);
  }

  Future<void> retryUpload(String poleNumber, int index) async {
    final imageState = state[poleNumber]![index];
    if (imageState.status != UploadStatus.failed) return;
    
    await _startUpload(poleNumber, index, imageState.file);
  }

  Future<void> _startUpload(String poleNumber, int index, File file) async {
    final oldState = state[poleNumber]![index];
    _updateImageState(poleNumber, index, oldState.copyWith(status: UploadStatus.uploading, progress: 0.0));

    try {
      await _uploadService.uploadImage(
        poleNumber: poleNumber,
        imageFile: file,
        imageSlot: index + 1, // Slots are 1, 2, 3
        onProgress: (progress) {
          _updateImageState(poleNumber, index, oldState.copyWith(
            status: UploadStatus.uploading,
            progress: progress,
          ));
        },
      );

      // Success
      _updateImageState(poleNumber, index, oldState.copyWith(status: UploadStatus.success, progress: 1.0));
    } catch (e) {
      // Failed
      _updateImageState(poleNumber, index, oldState.copyWith(status: UploadStatus.failed, progress: state[poleNumber]![index].progress, error: e.toString()));
    }
  }

  void _updateImageState(String poleNumber, int index, ImageUploadState newState) {
    final currentList = List<ImageUploadState>.from(state[poleNumber] ?? []);
    if (index >= 0 && index < currentList.length) {
      currentList[index] = newState;
      state = {
        ...state,
        poleNumber: currentList,
      };
    }
  }
}
