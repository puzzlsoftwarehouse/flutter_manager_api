import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_api/upload/multipart/multipart_media_uploader.dart';

void main() {
  group('MultipartMediaUploader.runWithTransientRetry', () {
    test(
      'Should return result when request succeeds on first attempt',
      () async {
        final String result =
            await MultipartMediaUploader.runWithTransientRetry<String>(
          cancelToken: null,
          request: () async => 'ok',
          isTransientError: (_) => true,
        );
        expect(result, 'ok');
      },
    );

    test(
      'Should return result when request succeeds after a transient failure',
      () async {
        int callCount = 0;
        final String result =
            await MultipartMediaUploader.runWithTransientRetry<String>(
          cancelToken: null,
          request: () async {
            callCount++;
            if (callCount == 1) {
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.connectionError,
              );
            }
            return 'ok';
          },
          isTransientError: MultipartMediaUploader.isTransientPartUploadError,
        );
        expect(result, 'ok');
        expect(callCount, 2);
      },
    );

    test(
      'Should rethrow when transient failures exceed max attempts',
      () async {
        int callCount = 0;
        await expectLater(
          () => MultipartMediaUploader.runWithTransientRetry<void>(
            cancelToken: null,
            request: () async {
              callCount++;
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.connectionError,
              );
            },
            isTransientError: MultipartMediaUploader.isTransientPartUploadError,
          ),
          throwsA(isA<DioException>()),
        );
        expect(
          callCount,
          MultipartMediaUploader.defaultMaxPartAttempts,
        );
      },
    );

    test(
      'Should not retry when request fails with a non-transient error',
      () async {
        int callCount = 0;
        await expectLater(
          () => MultipartMediaUploader.runWithTransientRetry<void>(
            cancelToken: null,
            request: () async {
              callCount++;
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: RequestOptions(path: '/'),
                  statusCode: 400,
                ),
              );
            },
            isTransientError: MultipartMediaUploader.isTransientPartUploadError,
          ),
          throwsA(isA<DioException>()),
        );
        expect(callCount, 1);
      },
    );

    test(
      'Should not retry when request fails with a cancellation error',
      () async {
        int callCount = 0;
        await expectLater(
          () => MultipartMediaUploader.runWithTransientRetry<void>(
            cancelToken: null,
            request: () async {
              callCount++;
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.cancel,
              );
            },
            isTransientError: MultipartMediaUploader.isTransientPartUploadError,
          ),
          throwsA(isA<DioException>()),
        );
        expect(callCount, 1);
      },
    );
  });

  group('MultipartMediaUploader.backoffAfterFailedAttempt', () {
    test(
      'Should clamp backoff index to the last configured delay',
      () {
        final Duration backoff =
            MultipartMediaUploader.backoffAfterFailedAttempt(99);
        expect(
          backoff,
          MultipartMediaUploader.defaultPartRetryBackoff.last,
        );
      },
    );
  });
}
