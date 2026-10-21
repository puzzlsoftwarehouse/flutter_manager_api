import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_api/upload/multipart/multipart_media_uploader.dart';

void main() {
  group('MultipartMediaUploader resilience', () {
    test('shouldAbortMultipartOnExit only when user cancelled', () {
      expect(
        MultipartMediaUploader.shouldAbortMultipartOnExit(
          sessionStarted: true,
          succeeded: false,
          userCancelled: true,
        ),
        isTrue,
      );
      expect(
        MultipartMediaUploader.shouldAbortMultipartOnExit(
          sessionStarted: true,
          succeeded: false,
          userCancelled: false,
        ),
        isFalse,
      );
    });

    test('isTransientPartUploadError detects connection failures', () {
      final DioException connectionError = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      );
      expect(
        MultipartMediaUploader.isTransientPartUploadError(connectionError),
        isTrue,
      );

      final DioException cancelError = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.cancel,
      );
      expect(
        MultipartMediaUploader.isTransientPartUploadError(cancelError),
        isFalse,
      );
    });
  });
}
