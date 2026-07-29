import 'package:dio/dio.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/utils/failure_message_resolver.dart';

class UploadResult {
  UploadResult._();

  static Map<String, dynamic> success(Object? data) {
    if (data is Map) {
      return <String, dynamic>{
        'data': Map<String, dynamic>.from(data),
      };
    }
    return <String, dynamic>{'data': data};
  }

  static Map<String, dynamic> failure({
    required String code,
    required String message,
  }) {
    return <String, dynamic>{
      'exception_code': code,
      'detail': message,
    };
  }

  static Map<String, dynamic> fromCaughtError(Object error) {
    return failure(
      code: '000',
      message: error.toString(),
    );
  }

  static Map<String, dynamic> canceled() {
    return failure(
      code: DefaultAPIFailures.cancelErrorCode,
      message: 'Request canceled',
    );
  }

  static Map<String, dynamic> fromResponse(Response<dynamic> response) {
    final int statusCode = response.statusCode ?? 0;
    final Object? responseData = response.data;

    if (responseData is Map) {
      final Map<String, dynamic> errorMap =
          Map<String, dynamic>.from(responseData);
      final Object? detail = errorMap['detail'] ?? errorMap['message'];
      return failure(
        code: errorMap['exception_code']?.toString() ?? statusCode.toString(),
        message: _messageFromDetail(
          detail,
          statusCode: statusCode,
          fallback: response.statusMessage ?? 'Unexpected server error',
        ),
      );
    }

    final String raw = responseData?.toString() ?? '';
    return failure(
      code: statusCode.toString(),
      message: _friendlyMessage(
        statusCode: statusCode,
        fallback: raw.isNotEmpty
            ? raw
            : (response.statusMessage ?? 'Unexpected server error'),
      ),
    );
  }

  static String _messageFromDetail(
    Object? detail, {
    required int statusCode,
    required String fallback,
  }) {
    if (detail == null) {
      return _friendlyMessage(statusCode: statusCode, fallback: fallback);
    }
    if (detail is String && detail.trim().isNotEmpty) {
      return detail;
    }
    if (detail is List || detail is Map) {
      final String text = detail.toString();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return _friendlyMessage(statusCode: statusCode, fallback: fallback);
  }

  static Map<String, dynamic> fromDioException(DioException exception) {
    if (exception.type == DioExceptionType.cancel) {
      return canceled();
    }

    if (exception.type == DioExceptionType.connectionTimeout ||
        exception.type == DioExceptionType.receiveTimeout ||
        exception.type == DioExceptionType.sendTimeout) {
      return failure(
        code: 'timeout',
        message: 'The connection has timed out. Try again',
      );
    }

    if (exception.type == DioExceptionType.connectionError ||
        exception.type == DioExceptionType.unknown) {
      return failure(
        code: 'noConnection',
        message: 'No internet connection',
      );
    }

    final Response<dynamic>? errorResponse = exception.response;
    if (errorResponse != null) {
      return fromResponse(errorResponse);
    }

    return failure(
      code: '000',
      message: FailureMessageResolver.resolveUserMessage(
        fallback: 'Unexpected upload error',
        technicalLog: exception.message,
      ),
    );
  }

  static bool isSuccessStatus(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  static String _friendlyMessage({
    required int statusCode,
    required String fallback,
  }) {
    if (statusCode == 404) {
      return 'Upload endpoint not found (404). Check API host/route.';
    }
    if (statusCode == 413) {
      return 'This file is larger than the server upload limit';
    }

    final String resolvedFallback =
        fallback.trim().isEmpty ? 'Unexpected server error' : fallback;

    return FailureMessageResolver.resolveUserMessage(
      fallback: resolvedFallback,
      serverDetail: resolvedFallback,
    );
  }
}
