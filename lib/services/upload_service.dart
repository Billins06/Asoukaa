import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

class UploadService {
  static UploadService? _instance;
  static UploadService get instance => _instance ??= UploadService._();
  UploadService._();

  Dio get _client => ApiService.instance.client;

  /// Type de fichier (mime) à annoncer au serveur d'après le nom / l'extension.
  /// Le serveur refuse un fichier sans type ou avec un type non admis.
  /// Valeur par défaut : image JPEG (comme avant pour les photos).
  static String mimeDepuisNom(String nom) {
    final lower = nom.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'image/jpeg';
  }

  Future<String> uploadFile(XFile file, String type) async {
    // ⚠️ fromFile(file.path, ...) lit un vrai chemin disque : ça ne
    // fonctionne pas sur le web (XFile.path y est une URL blob, pas un
    // chemin de fichier). readAsBytes() + fromBytes fonctionne sur web
    // ET mobile — c'est déjà la méthode utilisée pour l'upload des
    // photos produit, on l'aligne ici.
    final bytes = await file.readAsBytes();
    // Type annoncé d'après l'extension : le serveur refuse un fichier dont
    // le type n'est pas JPG / PNG / WEBP (ou PDF pour les documents).
    final String mime = mimeDepuisNom(file.name);
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: file.name,
        contentType: DioMediaType.parse(mime),
      ),
    });
    final response = await _client.post('/api/v1/upload/$type', data: formData);
    return response.data['url'] as String;
  }

  Future<List<String>> uploadMultiple(List<XFile> files, String type) async {
    return Future.wait(files.map((f) => uploadFile(f, type)));
  }
}
