import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:manager_api/upload/common/upload_headers.dart';
import 'package:manager_api/upload/common/upload_map_reader.dart';
import 'package:manager_api/upload/common/upload_result.dart';
import 'package:manager_api/utils/failure_message_resolver.dart';
import 'package:rxdart/subjects.dart';

typedef MultipartPartPut = Future<String> Function({
  required String url,
  required int partNumber,
  required int offset,
  required int length,
  required CancelToken cancelToken,
  required void Function(int bytesSent) onBytesSent,
});

class MultipartMediaUploadRequest {
  final String mediaBaseUrl;
  final Map<String, String>? headers;
  final Map<String, dynamic> fields;
  final String filename;
  final int fileSize;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;
  final MultipartPartPut putPart;
  final int maxConcurrentParts;

  const MultipartMediaUploadRequest({
    required this.mediaBaseUrl,
    required this.headers,
    required this.fields,
    required this.filename,
    required this.fileSize,
    required this.streamProgress,
    required this.cancelToken,
    required this.putPart,
    this.maxConcurrentParts = 6,
  });
}

class MultipartMediaUploader {
  MultipartMediaUploader._();

  static const int webMaxConcurrentParts = 4;
  static const int nativeMaxConcurrentParts = 6;

  static const Set<String> _presignExcludedKeys = <String>{
    'blur_hash',
    'duration',
  };

  static const Set<String> _confirmExcludedKeys = <String>{
    'file_size',
  };

  static const Set<String> _abortExcludedKeys = <String>{
    'blur_hash',
    'duration',
    'file_size',
  };

  static int recommendedConcurrency({
    required int partCount,
    bool? isWeb,
  }) {
    final bool web = isWeb ?? kIsWeb;
    final int cap = web ? webMaxConcurrentParts : nativeMaxConcurrentParts;
    if (partCount <= 1) {
      return 1;
    }
    return math.min(cap, partCount);
  }

  static String normalizeMediaBaseUrl(String url) {
    String normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    const List<String> suffixes = <String>[
      '/presign-multipart',
      '/confirm-multipart',
      '/abort-multipart',
      '/upload',
    ];

    for (final String suffix in suffixes) {
      if (normalized.endsWith(suffix)) {
        normalized = normalized.substring(0, normalized.length - suffix.length);
        break;
      }
    }

    return normalized;
  }

  static Future<Map<String, dynamic>> upload(
    MultipartMediaUploadRequest request,
  ) async {
    final String mediaBaseUrl = normalizeMediaBaseUrl(request.mediaBaseUrl);
    final Dio apiClient = Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(hours: 2),
        sendTimeout: kIsWeb ? null : const Duration(hours: 2),
        headers: UploadHeaders.withoutContentType(request.headers),
      ),
    );

    String? objectKey;
    String? uploadId;
    String? adapterSlug;
    bool sessionStarted = false;
    bool succeeded = false;
    Map<String, dynamic>? result;

    Future<void> abortSession() async {
      final String? currentObjectKey = objectKey;
      final String? currentUploadId = uploadId;
      if (currentObjectKey == null || currentUploadId == null) {
        return;
      }
      await _safeAbort(
        apiClient: apiClient,
        mediaBaseUrl: mediaBaseUrl,
        fields: request.fields,
        objectKey: currentObjectKey,
        uploadId: currentUploadId,
        adapterSlug: adapterSlug ?? 'digital_ocean_s3',
      );
    }

    try {
      _throwIfCancelled(request.cancelToken);

      final Response<dynamic> presignResponse = await apiClient.post<dynamic>(
        '$mediaBaseUrl/presign-multipart',
        data: _payload(
          request.fields,
          exclude: _presignExcludedKeys,
          extra: <String, dynamic>{
            'filename': request.filename,
            'file_size': request.fileSize,
          },
        ),
        cancelToken: request.cancelToken,
      );

      if (!UploadResult.isSuccessStatus(presignResponse.statusCode)) {
        result = UploadResult.fromResponse(presignResponse);
        return result;
      }

      final Map<String, dynamic> presignData =
          UploadMapReader.asStringKeyedMap(presignResponse.data);
      objectKey = presignData['object_key'] as String?;
      uploadId = presignData['upload_id'] as String?;
      adapterSlug = presignData['adapter_slug'] as String? ?? 'digital_ocean_s3';
      final int partSize = (presignData['part_size'] as num?)?.toInt() ?? 0;
      final List<Map<String, dynamic>> parts =
          UploadMapReader.asMapList(presignData['parts']);

      if (objectKey != null && uploadId != null) {
        sessionStarted = true;
      }

      if (objectKey == null ||
          uploadId == null ||
          partSize <= 0 ||
          parts.isEmpty) {
        result = UploadResult.failure(
          code: '000',
          message: 'Invalid presign-multipart response',
        );
        return result;
      }

      _throwIfCancelled(request.cancelToken);

      final List<Map<String, dynamic>> completedParts =
          await _uploadPartsInParallel(
        request: request,
        parts: parts,
        partSize: partSize,
      );

      completedParts.sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            (a['part_number'] as int).compareTo(b['part_number'] as int),
      );

      _throwIfCancelled(request.cancelToken);

      final Response<dynamic> confirmResponse = await apiClient.post<dynamic>(
        '$mediaBaseUrl/confirm-multipart',
        data: _payload(
          request.fields,
          exclude: _confirmExcludedKeys,
          extra: <String, dynamic>{
            'object_key': objectKey,
            'upload_id': uploadId,
            'adapter_slug': adapterSlug,
            'filename': request.filename,
            'parts': completedParts,
          },
        ),
        cancelToken: request.cancelToken,
      );

      if (!UploadResult.isSuccessStatus(confirmResponse.statusCode)) {
        result = UploadResult.fromResponse(confirmResponse);
        return result;
      }

      request.streamProgress?.add(100);
      succeeded = true;
      result = UploadResult.success(confirmResponse.data);
      return result;
    } on DioException catch (exception) {
      result = UploadResult.fromDioException(exception);
      return result;
    } on _UploadCancelledException {
      result = UploadResult.canceled();
      return result;
    } catch (exception) {
      result = UploadResult.failure(
        code: '000',
        message: FailureMessageResolver.summarize(exception.toString()),
      );
      return result;
    } finally {
      if (sessionStarted && !succeeded) {
        await abortSession();
      }
      apiClient.close(force: true);
    }
  }

  static Future<List<Map<String, dynamic>>> _uploadPartsInParallel({
    required MultipartMediaUploadRequest request,
    required List<Map<String, dynamic>> parts,
    required int partSize,
  }) async {
    final CancelToken partCancelToken = CancelToken();
    final List<Map<String, dynamic>> queue =
        List<Map<String, dynamic>>.from(parts);
    final List<Map<String, dynamic>> completedParts = <Map<String, dynamic>>[];
    final Map<int, int> bytesSentByPart = <int, int>{};
    Object? firstError;
    bool stopped = false;

    void failAndStop(Object error, {required String reason}) {
      firstError ??= error;
      if (stopped) {
        return;
      }
      stopped = true;
      queue.clear();
      if (!partCancelToken.isCancelled) {
        partCancelToken.cancel(reason);
      }
    }

    StreamSubscription<void>? cancelSubscription;
    cancelSubscription = request.cancelToken?.whenCancel.asStream().listen((_) {
      failAndStop(
        _UploadCancelledException(),
        reason: 'user cancel',
      );
    });

    void reportProgress() {
      if (stopped || partCancelToken.isCancelled) {
        return;
      }
      final int sent = bytesSentByPart.values.fold<int>(
        0,
        (int total, int value) => total + value,
      );
      final int total = request.fileSize <= 0 ? 1 : request.fileSize;
      final int progress = ((sent / total) * 100).floor().clamp(0, 99);
      request.streamProgress?.add(progress);
    }

    Future<void> worker() async {
      while (true) {
        if (stopped ||
            firstError != null ||
            partCancelToken.isCancelled ||
            request.cancelToken?.isCancelled == true) {
          return;
        }

        if (queue.isEmpty) {
          return;
        }

        final Map<String, dynamic> part = queue.removeAt(0);
        final int partNumber = (part['part_number'] as num).toInt();
        final String partUrl = part['url'] as String;
        final int offset = (partNumber - 1) * partSize;
        final int length = math.min(partSize, request.fileSize - offset);

        if (length <= 0) {
          failAndStop(
            StateError('Invalid part length for part $partNumber'),
            reason: 'invalid length',
          );
          return;
        }

        try {
          final String etag = await request.putPart(
            url: partUrl,
            partNumber: partNumber,
            offset: offset,
            length: length,
            cancelToken: partCancelToken,
            onBytesSent: (int bytesSent) {
              if (stopped || partCancelToken.isCancelled) {
                return;
              }
              bytesSentByPart[partNumber] = bytesSent.clamp(0, length);
              reportProgress();
            },
          );

          if (stopped || partCancelToken.isCancelled) {
            return;
          }

          if (etag.isEmpty) {
            throw StateError(
              'Missing ETag for part $partNumber. Check Spaces CORS ExposeHeaders.',
            );
          }

          completedParts.add(<String, dynamic>{
            'part_number': partNumber,
            'etag': etag,
          });
          bytesSentByPart[partNumber] = length;
          reportProgress();
        } catch (error) {
          failAndStop(error, reason: 'part#$partNumber failed');
          return;
        }
      }
    }

    try {
      final int workerCount = math.min(
        request.maxConcurrentParts,
        parts.length,
      );
      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      );

      if (request.cancelToken?.isCancelled == true ||
          (partCancelToken.isCancelled && firstError == null)) {
        throw _UploadCancelledException();
      }

      if (firstError != null) {
        final Object error = firstError!;
        if (error is MultipartPartCancelledException ||
            (error is DioException &&
                error.type == DioExceptionType.cancel)) {
          throw _UploadCancelledException();
        }
        throw error;
      }

      if (completedParts.length != parts.length) {
        throw StateError('Not all multipart parts were uploaded');
      }

      return completedParts;
    } finally {
      await cancelSubscription?.cancel();
    }
  }

  static Future<void> _safeAbort({
    required Dio apiClient,
    required String mediaBaseUrl,
    required Map<String, dynamic> fields,
    required String objectKey,
    required String uploadId,
    required String adapterSlug,
  }) async {
    try {
      await apiClient.post<dynamic>(
        '$mediaBaseUrl/abort-multipart',
        data: _payload(
          fields,
          exclude: _abortExcludedKeys,
          extra: <String, dynamic>{
            'object_key': objectKey,
            'upload_id': uploadId,
            'adapter_slug': adapterSlug,
          },
        ),
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _payload(
    Map<String, dynamic> fields, {
    required Set<String> exclude,
    required Map<String, dynamic> extra,
  }) {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(fields);
    for (final String key in exclude) {
      payload.remove(key);
    }
    payload.addAll(extra);
    payload.removeWhere((_, Object? value) => value == null);
    return payload;
  }

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw _UploadCancelledException();
    }
  }
}

class MultipartPartCancelledException implements Exception {
  const MultipartPartCancelledException();
}

class _UploadCancelledException implements Exception {}
