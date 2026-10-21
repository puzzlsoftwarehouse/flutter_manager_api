import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_api/upload/multipart/multipart_media_uploader.dart';

void main() {
  group('MultipartMediaUploader resilience', () {
    test(
      'Should abort multipart session when upload started, failed, and user cancelled',
      () {
        expect(
          MultipartMediaUploader.shouldAbortMultipartOnExit(
            sessionStarted: true,
            succeeded: false,
            userCancelled: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'Should not abort multipart session when upload failed without user cancel',
      () {
        expect(
          MultipartMediaUploader.shouldAbortMultipartOnExit(
            sessionStarted: true,
            succeeded: false,
            userCancelled: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'Should treat connection errors as transient when classifying upload failures',
      () {
        final DioException connectionError = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        );
        expect(
          MultipartMediaUploader.isTransientPartUploadError(connectionError),
          isTrue,
        );
      },
    );

    test(
      'Should not treat cancel errors as transient when classifying upload failures',
      () {
        final DioException cancelError = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.cancel,
        );
        expect(
          MultipartMediaUploader.isTransientPartUploadError(cancelError),
          isFalse,
        );
      },
    );

    test(
      'Should return success when transient failure is followed by a successful attempt',
      () async {
        int callCount = 0;
        final int result =
            await MultipartMediaUploader.runWithTransientRetry<int>(
          cancelToken: null,
          isTransientError: MultipartMediaUploader.isTransientPartUploadError,
          action: () async {
            callCount++;
            if (callCount == 1) {
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.connectionError,
              );
            }
            return 42;
          },
        );

        expect(result, 42);
        expect(callCount, 2);
      },
    );

    test(
      'Should rethrow when transient failures exceed the maximum attempt count',
      () async {
        int callCount = 0;
        await expectLater(
          () => MultipartMediaUploader.runWithTransientRetry<void>(
            cancelToken: null,
            isTransientError: MultipartMediaUploader.isTransientPartUploadError,
            action: () async {
              callCount++;
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.connectionError,
              );
            },
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
      'Should not retry when upload action throws a cancellation error',
      () async {
        int callCount = 0;
        await expectLater(
          () => MultipartMediaUploader.runWithTransientRetry<void>(
            cancelToken: null,
            isTransientError: MultipartMediaUploader.isTransientPartUploadError,
            action: () async {
              callCount++;
              throw DioException(
                requestOptions: RequestOptions(path: '/'),
                type: DioExceptionType.cancel,
              );
            },
          ),
          throwsA(isA<DioException>()),
        );
        expect(callCount, 1);
      },
    );
  });
}
