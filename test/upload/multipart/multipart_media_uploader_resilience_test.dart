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
      'Should treat connection errors as transient when classifying part failures',
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
      'Should not treat cancel errors as transient when classifying part failures',
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
  });
}
