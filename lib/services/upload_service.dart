import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

class UploadService {
  static UploadService? _instance;
  static UploadService get instance => _instance ??= UploadService._();
  UploadService._();

  Dio get _client => ApiService.instance.client;

  Future<String> uploadFile(XFile file, String type) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
    });
    final response = await _client.post('/api/v1/upload/$type', data: formData);
    return response.data['url'] as String;
  }

  Future<List<String>> uploadMultiple(List<XFile> files, String type) async {
    return Future.wait(files.map((f) => uploadFile(f, type)));
  }
}
