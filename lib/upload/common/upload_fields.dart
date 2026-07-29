import 'package:cross_file/cross_file.dart';
import 'package:manager_api/upload/common/upload_map_reader.dart';

class UploadFields {
  UploadFields._();

  static Map<String, dynamic> merge({
    required Map<String, dynamic> parameters,
    required Map<String, dynamic> body,
  }) {
    return <String, dynamic>{
      ...parameters,
      ...body,
    };
  }

  static String filename(Map<String, dynamic> fields, XFile file) {
    return UploadMapReader.readString(fields, 'filename') ?? file.name;
  }

  static String? mimetype(Map<String, dynamic> fields, XFile file) {
    return UploadMapReader.readString(fields, 'mimetype') ?? file.mimeType;
  }

  static String? blurHash(Map<String, dynamic> fields) {
    return UploadMapReader.readString(fields, 'blur_hash');
  }

  static String? contentDatumTypeSlug(Map<String, dynamic> fields) {
    return UploadMapReader.readString(fields, 'content_datum_type_slug');
  }
}
