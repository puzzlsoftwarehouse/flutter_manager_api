import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/upload/common/blur_hash_encoder.dart';
import 'package:manager_api/upload/common/upload_fields.dart';
import 'package:manager_api/upload/common/upload_map_reader.dart';
import 'package:manager_api/upload/common/upload_result.dart';
import 'package:manager_api/upload/multipart/multipart_media_uploader.dart';
import 'package:manager_api/upload/web/web_upload_blob_loader.dart';
import 'package:manager_api/upload/web/web_upload_worker.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as web;

class WebMultipartUpload {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, dynamic> body;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  const WebMultipartUpload({
    required this.file,
    required this.url,
    required this.parameters,
    required this.body,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  Future<Map<String, dynamic>> start() async {
    const WebUploadBlobLoader blobLoader = WebUploadBlobLoader();
    final web.Blob fileBlob = await blobLoader.load(file);
    final WebUploadWorker uploadWorker = WebUploadWorker();
    final Set<void Function()> activeCancels = <void Function()>{};

    StreamSubscription<void>? cancelSubscription;
    cancelSubscription = cancelToken?.whenCancel.asStream().listen((_) {
      for (final void Function() cancel in List<void Function()>.from(
        activeCancels,
      )) {
        cancel();
      }
    });

    try {
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

      final int partEstimate =
          (fileBlob.size / (10 * 1024 * 1024)).ceil().clamp(1, 10000);
      final int concurrency = MultipartMediaUploader.recommendedConcurrency(
        partCount: partEstimate,
        isWeb: true,
      );

      return await MultipartMediaUploader.upload(
        MultipartMediaUploadRequest(
          mediaBaseUrl: url,
          headers: headers,
          fields: fields,
          filename: filename,
          fileSize: fileBlob.size,
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
            final web.Blob partBlob = fileBlob.slice(offset, offset + length);
            void Function()? cancelUpload;

            void registerCancel(void Function() onCancel) {
              cancelUpload = onCancel;
              activeCancels.add(onCancel);
            }

            if (cancelToken.isCancelled) {
              throw const MultipartPartCancelledException();
            }

            final StreamSubscription<void> partCancelSubscription =
                cancelToken.whenCancel.asStream().listen((_) {
              cancelUpload?.call();
            });

            try {
              final Map<String, dynamic> result = await uploadWorker.putRaw(
                uploadUrl: url,
                blob: partBlob,
                onBytes: (int loaded, int _) => onBytesSent(loaded),
                registerCancel: registerCancel,
              );

              if (cancelToken.isCancelled ||
                  result['exception_code']?.toString() == 'cancel') {
                throw const MultipartPartCancelledException();
              }

              final Object? data = result['data'];
              if (data is Map) {
                return UploadMapReader.asStringKeyedMap(data)['etag']
                        ?.toString() ??
                    '';
              }

              throw StateError(
                result['detail']?.toString() ??
                    'Failed to upload multipart part $partNumber',
              );
            } finally {
              await partCancelSubscription.cancel();
              if (cancelUpload != null) {
                activeCancels.remove(cancelUpload);
              }
            }
          },
        ),
      );
    } catch (error) {
      uploadWorker.abortAll();
      return UploadResult.fromCaughtError(error);
    } finally {
      await cancelSubscription?.cancel();
      for (final void Function() cancel in List<void Function()>.from(
        activeCancels,
      )) {
        cancel();
      }
      uploadWorker.dispose();
    }
  }
}
