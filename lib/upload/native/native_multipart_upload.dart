import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/upload/common/blur_hash_encoder.dart';
import 'package:manager_api/upload/common/upload_fields.dart';
import 'package:manager_api/upload/common/upload_result.dart';
import 'package:manager_api/upload/multipart/multipart_media_uploader.dart';
import 'package:manager_api/upload/native/native_file_source.dart';
import 'package:rxdart/subjects.dart';

class NativeMultipartUpload {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, dynamic> body;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  const NativeMultipartUpload({
    required this.file,
    required this.url,
    required this.parameters,
    required this.body,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  Future<Map<String, dynamic>> start() async {
    try {
      final int fileSize = await file.length();
      final Map<String, dynamic> fields = UploadFields.merge(
        parameters: parameters,
        body: body,
      );
      final String filename = UploadFields.filename(fields, file);
      final String? mimetype = UploadFields.mimetype(fields, file);
      final String? blurHash = await BlurHashEncoder.resolve(
        file: file,
        existingBlurHash: UploadFields.blurHash(fields),
        mimetype: mimetype,
        filename: filename,
        contentDatumTypeSlug: UploadFields.contentDatumTypeSlug(fields),
      );
      if (blurHash != null) {
        fields['blur_hash'] = blurHash;
      }
      if (mimetype != null && mimetype.isNotEmpty) {
        fields['mimetype'] = mimetype;
      }

      final NativeFileSource fileSource = NativeFileSource(file);
      final Dio spacesClient = Dio(
        BaseOptions(
          connectTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(hours: 2),
        ),
      );
      spacesClient.interceptors.removeImplyContentTypeInterceptor();

      try {
        final int partEstimate =
            (fileSize / (10 * 1024 * 1024)).ceil().clamp(1, 10000);
        final int concurrency = MultipartMediaUploader.recommendedConcurrency(
          partCount: partEstimate,
          isWeb: false,
        );

        return await MultipartMediaUploader.upload(
          MultipartMediaUploadRequest(
            mediaBaseUrl: url,
            headers: headers,
            fields: fields,
            filename: filename,
            fileSize: fileSize,
            streamProgress: streamProgress,
            cancelToken: cancelToken,
            maxConcurrentParts: concurrency,
            putPart: ({
              required String url,
              required int partNumber,
              required int offset,
              required int length,
              required CancelToken cancelToken,
              required void Function(int bytesSent) onBytesSent,
            }) async {
              final Stream<List<int>> chunkStream =
                  await fileSource.openChunkStream(
                offset: offset,
                length: length,
              );

              final Response<dynamic> response = await spacesClient.put<dynamic>(
                url,
                data: chunkStream,
                options: Options(
                  headers: <String, dynamic>{
                    Headers.contentLengthHeader: length,
                  },
                  validateStatus: UploadResult.isSuccessStatus,
                ),
                cancelToken: cancelToken,
                onSendProgress: (int sent, int total) {
                  onBytesSent(sent);
                },
              );

              return response.headers.value('etag') ?? '';
            },
          ),
        );
      } finally {
        spacesClient.close(force: true);
      }
    } catch (error) {
      return UploadResult.fromCaughtError(error);
    }
  }
}
