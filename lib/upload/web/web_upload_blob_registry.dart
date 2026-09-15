import 'package:web/web.dart' as web;

class WebUploadBlobRegistry {
  static Future<web.Blob?> Function(String blobUrl)? resolveBlobUrl;
}
