import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

final uploadServiceProvider = Provider((ref) => UploadService());

class UploadService {
  final Dio _dio = Dio();

  Future<void> uploadImage({
    required String poleNumber,
    required File imageFile,
    required int imageSlot,
    required Function(double) onProgress,
  }) async {
    final String url = '${ApiService.activeBaseUrl}/poles/${Uri.encodeComponent(poleNumber)}/images/$imageSlot';

    final fileName = imageFile.path.split('/').last;

    FormData formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
      'pole_number': poleNumber,
      // Metadata fields will go here in Phase 4
    });

    try {
      await _dio.post(
        url,
        data: formData,
        onSendProgress: (int sent, int total) {
          if (total != -1) {
            double progress = sent / total;
            onProgress(progress);
          }
        },
        options: Options(
          validateStatus: (status) {
            return status != null && status < 500;
          },
        ),
      );
    } catch (e) {
      throw Exception('Upload interrupted: $e');
    }
  }
}
