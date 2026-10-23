import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:manager_api/upload/common/upload_headers.dart';
import 'package:manager_api/upload/common/upload_map_reader.dart';
import 'package:manager_api/upload/common/upload_resilience_log.dart';
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
  final Future<String?>? blurHashFuture;
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
    this.blurHashFuture,
    required this.streamProgress,
    required this.cancelToken,
    required this.putPart,
    this.maxConcurrentParts = 6,
  });
}

class MultipartMediaUploader {
  MultipartMediaUploader._();

  static const int webMaxConcurrentParts = 6;
  static const int nativeMaxConcurrentParts = 6;
  static const int defaultMaxPartAttempts = 3;
  static const List<Duration> defaultPartRetryBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  static const Duration _apiConnectTimeout = Duration(seconds: 30);
  static const Duration _apiReceiveTimeout = Duration(minutes: 2);
  static const Duration _apiSendTimeout = Duration(seconds: 60);

  static const Set<String> _presignKeys = <String>{
    'company_id',
    'directory',
    'content_descriptor_slug',
    'content_datum_type_slug',
    'filename',
    'file_size',
    'is_public',
    'mimetype',
  };

  static const Set<String> _confirmKeys = <String>{
    'object_key',
    'upload_id',
    'company_id',
    'content_descriptor_slug',
    'content_datum_type_slug',
    'filename',
    'parts',
    'adapter_slug',
    'blur_hash',
    'duration',
  };

  static const Set<String> _abortKeys = <String>{
    'object_key',
    'upload_id',
    'company_id',
    'adapter_slug',
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
        connectTimeout: _apiConnectTimeout,
        receiveTimeout: _apiReceiveTimeout,
        sendTimeout: kIsWeb ? null : _apiSendTimeout,
        headers: UploadHeaders.forMediaApi(request.headers),
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

    final CancelToken dioSessionCancelToken = CancelToken();
    final CancelToken? uploadCancelToken = request.cancelToken;
    StreamSubscription<void>? uploadCancelSubscription;
    uploadCancelSubscription =
        uploadCancelToken?.whenCancel.asStream().listen((_) {
      if (!dioSessionCancelToken.isCancelled) {
        dioSessionCancelToken.cancel('user cancel');
      }
    });

    try {
      _throwIfCancelled(uploadCancelToken);
      _setProgress(request, 1);

      final Response<dynamic> presignResponse = await _postWithTransientRetry(
        cancelToken: dioSessionCancelToken,
        request: () => apiClient.post<dynamic>(
          '$mediaBaseUrl/presign-multipart',
          data: _payload(
            request.fields,
            allowKeys: _presignKeys,
            extra: <String, dynamic>{
              'filename': request.filename,
              'file_size': request.fileSize,
            },
          ),
          cancelToken: dioSessionCancelToken,
        ),
      );

      if (!UploadResult.isSuccessStatus(presignResponse.statusCode)) {
        result = UploadResult.fromResponse(presignResponse);
        return result;
      }

      final Map<String, dynamic> presignData =
          UploadMapReader.asStringKeyedMap(presignResponse.data);
      objectKey = presignData['object_key'] as String?;
      uploadId = presignData['upload_id'] as String?;
      adapterSlug =
          presignData['adapter_slug'] as String? ?? 'digital_ocean_s3';
      final int partSize = (presignData['part_size'] as num?)?.toInt() ?? 0;
      final List<Map<String, dynamic>> parts =
          UploadMapReader.asMapList(presignData['parts']);

      if (objectKey != null && uploadId != null) {
        sessionStarted = true;
        UploadResilienceLog.logEvent(
          'multipart_session_started',
          details: <String, Object?>{
            'uploadId': uploadId,
            'partCount': parts.length,
            'filename': request.filename,
            'fileSize': request.fileSize,
          },
        );
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

      _throwIfCancelled(uploadCancelToken);
      _setProgress(request, 3);

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

      _throwIfCancelled(uploadCancelToken);
      _setProgress(request, 98);

      final String? blurHash = await _resolveBlurHash(request);
      if (blurHash != null && blurHash.isNotEmpty) {
        request.fields['blur_hash'] = blurHash;
      }

      _throwIfCancelled(uploadCancelToken);

      final Response<dynamic> confirmResponse = await _postWithTransientRetry(
        cancelToken: dioSessionCancelToken,
        request: () => apiClient.post<dynamic>(
          '$mediaBaseUrl/confirm-multipart',
          data: _payload(
            request.fields,
            allowKeys: _confirmKeys,
            extra: <String, dynamic>{
              'object_key': objectKey,
              'upload_id': uploadId,
              'adapter_slug': adapterSlug,
              'filename': request.filename,
              'parts': completedParts,
            },
          ),
          cancelToken: dioSessionCancelToken,
          options: Options(
            sendTimeout: kIsWeb ? null : _apiSendTimeout,
            receiveTimeout: _apiReceiveTimeout,
          ),
        ),
      );

      if (!UploadResult.isSuccessStatus(confirmResponse.statusCode)) {
        result = UploadResult.fromResponse(confirmResponse);
        return result;
      }

      _setProgress(request, 100);
      succeeded = true;
      result = UploadResult.success(confirmResponse.data);
      return result;
    } on DioException catch (exception) {
      UploadResilienceLog.logEvent(
        'multipart_upload_dio_failure',
        details: <String, Object?>{
          'uploadId': uploadId,
          'type': exception.type.name,
          'message': exception.message,
          'userCancelToken': uploadCancelToken?.isCancelled,
          'sessionCancelToken': dioSessionCancelToken.isCancelled,
        },
      );
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
      await uploadCancelSubscription?.cancel();
      final bool userCancelled = uploadCancelToken?.isCancelled == true;
      final bool shouldAbort = shouldAbortMultipartOnExit(
        sessionStarted: sessionStarted,
        succeeded: succeeded,
        userCancelled: userCancelled,
      );
      UploadResilienceLog.logEvent(
        'multipart_session_finished',
        details: <String, Object?>{
          'uploadId': uploadId,
          'succeeded': succeeded,
          'userCancelled': userCancelled,
          'shouldAbort': shouldAbort,
          'failureCode': result?['exception_code'],
        },
      );
      if (shouldAbort) {
        await abortSession();
      }
      apiClient.close(force: true);
    }
  }

  @visibleForTesting
  static bool shouldAbortMultipartOnExit({
    required bool sessionStarted,
    required bool succeeded,
    required bool userCancelled,
  }) {
    return sessionStarted && !succeeded && userCancelled;
  }

  @visibleForTesting
  static Duration backoffAfterFailedAttempt(int failedAttemptIndex) {
    return defaultPartRetryBackoff[math.min(
      failedAttemptIndex,
      defaultPartRetryBackoff.length - 1,
    )];
  }

  @visibleForTesting
  static bool isUploadCancelledException(Object error) {
    return error is _UploadCancelledException ||
        error is MultipartPartCancelledException ||
        (error is DioException && error.type == DioExceptionType.cancel);
  }

  @visibleForTesting
  static bool isMultipartPartCancellation(Object error) {
    return error is MultipartPartCancelledException ||
        (error is DioException && error.type == DioExceptionType.cancel);
  }

  @visibleForTesting
  static Future<T> runWithTransientRetry<T>({
    required CancelToken? cancelToken,
    required Future<T> Function() request,
    required bool Function(Object error) isTransientError,
    void Function(int attempt, Object error, Duration backoff)?
        onRetryScheduled,
  }) async {
    int attempt = 0;
    while (attempt < defaultMaxPartAttempts) {
      _throwIfCancelled(cancelToken);
      try {
        return await request();
      } on Object catch (error) {
        if (isUploadCancelledException(error)) {
          rethrow;
        }
        if (!isTransientError(error)) {
          rethrow;
        }
        attempt++;
        if (attempt >= defaultMaxPartAttempts) {
          rethrow;
        }
        final Duration backoff = backoffAfterFailedAttempt(attempt - 1);
        onRetryScheduled?.call(attempt, error, backoff);
        await Future<void>.delayed(backoff);
      }
    }
    throw StateError('multipart transient retry exited without result');
  }

  static Future<Response<dynamic>> _postWithTransientRetry({
    required CancelToken? cancelToken,
    required Future<Response<dynamic>> Function() request,
  }) {
    return runWithTransientRetry<Response<dynamic>>(
      cancelToken: cancelToken,
      request: request,
      isTransientError: isTransientPartUploadError,
      onRetryScheduled: (int attempt, Object error, Duration backoff) {
        final DioException dioError = error as DioException;
        UploadResilienceLog.logEvent(
          'multipart_api_post_retry',
          details: <String, Object?>{
            'attempt': attempt + 1,
            'maxAttempts': defaultMaxPartAttempts,
            'dioType': dioError.type.name,
            'backoffMs': backoff.inMilliseconds,
          },
        );
      },
    );
  }

  @visibleForTesting
  static bool isTransientPartUploadError(Object error) {
    if (isUploadCancelledException(error)) {
      return false;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown) {
        return true;
      }
      final int? statusCode = error.response?.statusCode;
      if (statusCode != null && statusCode >= 500) {
        return true;
      }
      return false;
    }
    return false;
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
      final bool userCancelled = request.cancelToken?.isCancelled == true;
      final bool cooperativePartCancel = !userCancelled &&
          reason != 'user cancel' &&
          isMultipartPartCancellation(error);
      UploadResilienceLog.logEvent(
        'multipart_part_fail_and_stop',
        details: <String, Object?>{
          'reason': reason,
          'error': error.runtimeType.toString(),
          'userCancelled': userCancelled,
          'cooperativePartCancel': cooperativePartCancel,
          'recordsFirstError': !cooperativePartCancel,
        },
      );
      if (!cooperativePartCancel) {
        firstError ??= error;
      }
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
      final int progress = (3 + ((sent / total) * 95)).floor().clamp(3, 97);
      _setProgress(request, progress);
    }

    Future<void> worker() async {
      while (true) {
        final bool uploadCancelled = request.cancelToken?.isCancelled == true;
        if (stopped ||
            firstError != null ||
            partCancelToken.isCancelled ||
            uploadCancelled) {
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

        int partAttempt = 0;
        while (partAttempt < defaultMaxPartAttempts) {
          final bool uploadCancelled = request.cancelToken?.isCancelled == true;
          if (stopped || partCancelToken.isCancelled || uploadCancelled) {
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
            break;
          } catch (error) {
            final bool uploadCancelled =
                request.cancelToken?.isCancelled == true;
            if (stopped &&
                !uploadCancelled &&
                isMultipartPartCancellation(error)) {
              return;
            }
            if (error is _UploadCancelledException || uploadCancelled) {
              failAndStop(error, reason: 'part#$partNumber cancelled');
              return;
            }
            if (isMultipartPartCancellation(error)) {
              failAndStop(error, reason: 'part#$partNumber cancelled');
              return;
            }
            partAttempt++;
            if (!isTransientPartUploadError(error) ||
                partAttempt >= defaultMaxPartAttempts) {
              failAndStop(error, reason: 'part#$partNumber failed');
              return;
            }
            final Duration backoff = backoffAfterFailedAttempt(partAttempt - 1);
            UploadResilienceLog.logEvent(
              'multipart_part_transient_retry',
              details: <String, Object?>{
                'partNumber': partNumber,
                'partAttempt': partAttempt,
                'maxPartAttempts': defaultMaxPartAttempts,
                'backoffMs': backoff.inMilliseconds,
                'error': error.runtimeType.toString(),
              },
            );
            await Future<void>.delayed(backoff);
          }
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

      if (firstError != null) {
        final Object error = firstError!;
        final bool userCancelled = request.cancelToken?.isCancelled == true;
        UploadResilienceLog.logEvent(
          'multipart_parts_first_error',
          details: <String, Object?>{
            'error': error.runtimeType.toString(),
            'userCancelled': userCancelled,
            'completedParts': completedParts.length,
            'expectedParts': parts.length,
          },
        );
        if (!userCancelled &&
            isUploadCancelledException(error) &&
            completedParts.length != parts.length) {
          throw StateError('Not all multipart parts were uploaded');
        }
        if (isUploadCancelledException(error)) {
          throw _UploadCancelledException();
        }
        throw error;
      }

      if (request.cancelToken?.isCancelled == true) {
        throw _UploadCancelledException();
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
          allowKeys: _abortKeys,
          extra: <String, dynamic>{
            'object_key': objectKey,
            'upload_id': uploadId,
            'adapter_slug': adapterSlug,
          },
        ),
        options: Options(
          sendTimeout: kIsWeb ? null : _apiSendTimeout,
          receiveTimeout: _apiReceiveTimeout,
        ),
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _payload(
    Map<String, dynamic> fields, {
    required Set<String> allowKeys,
    required Map<String, dynamic> extra,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in fields.entries) {
      if (allowKeys.contains(entry.key)) {
        payload[entry.key] = entry.value;
      }
    }
    payload.addAll(extra);
    payload.removeWhere((_, Object? value) => value == null);
    return payload;
  }

  static Future<String?> _resolveBlurHash(
    MultipartMediaUploadRequest request,
  ) async {
    final Object? existing = request.fields['blur_hash'];
    if (existing is String && existing.isNotEmpty) {
      return existing;
    }

    final Future<String?>? blurHashFuture = request.blurHashFuture;
    if (blurHashFuture == null) {
      return null;
    }

    try {
      return await blurHashFuture;
    } catch (_) {
      return null;
    }
  }

  static void _setProgress(MultipartMediaUploadRequest request, int progress) {
    request.streamProgress?.add(progress.clamp(0, 100));
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
