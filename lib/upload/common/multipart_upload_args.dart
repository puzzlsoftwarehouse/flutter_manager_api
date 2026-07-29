import 'package:cross_file/cross_file.dart';
import 'package:manager_api/upload/common/upload_map_reader.dart';

class MultipartUploadArgs {
  final int companyId;
  final String directory;
  final String contentDescriptorSlug;
  final String contentDatumTypeSlug;
  final String filename;
  final bool isPublic;
  final String? mimetype;
  final String? blurHash;
  final int? duration;

  const MultipartUploadArgs({
    required this.companyId,
    required this.directory,
    required this.contentDescriptorSlug,
    required this.contentDatumTypeSlug,
    required this.filename,
    required this.isPublic,
    required this.mimetype,
    required this.blurHash,
    required this.duration,
  });

  factory MultipartUploadArgs.resolve({
    required XFile file,
    required Map<String, dynamic> parameters,
    required Map<String, dynamic> body,
  }) {
    return MultipartUploadArgs(
      companyId: UploadMapReader.readRequiredInt(parameters, 'company_id'),
      directory: UploadMapReader.readRequiredString(parameters, 'directory'),
      contentDescriptorSlug: UploadMapReader.readRequiredString(
        parameters,
        'content_descriptor_slug',
      ),
      contentDatumTypeSlug: UploadMapReader.readRequiredString(
        parameters,
        'content_datum_type_slug',
      ),
      filename: UploadMapReader.readString(parameters, 'filename') ??
          UploadMapReader.readString(body, 'filename') ??
          file.name,
      isPublic: UploadMapReader.readBool(
        parameters,
        'is_public',
        fallback: true,
      ),
      mimetype: UploadMapReader.readString(parameters, 'mimetype') ??
          UploadMapReader.readString(body, 'mimetype') ??
          file.mimeType,
      blurHash: UploadMapReader.readString(body, 'blur_hash') ??
          UploadMapReader.readString(parameters, 'blur_hash'),
      duration: UploadMapReader.readInt(body, 'duration') ??
          UploadMapReader.readInt(parameters, 'duration'),
    );
  }
}
