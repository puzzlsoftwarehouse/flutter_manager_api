import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/utils/failure_message_resolver.dart';
import 'package:manager_api/upload/send_media_desktop.dart'
    if (dart.library.html) 'package:manager_api/upload/send_media_web.dart';
import 'package:rxdart/rxdart.dart';

class RestHelper {
  static const Duration _defaultTimeout = Duration(minutes: 1);

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _defaultTimeout,
      receiveTimeout: _defaultTimeout,
      sendTimeout: _defaultTimeout,
    ),
  );

  Future<Map<String, dynamic>> getRequest({
    required String url,
    Map<String, String>? headers = const {},
    ResponseType? responseType,
    Duration? timeout,
  }) async {
    return await tryRequest(() async {
      final Duration effectiveTimeout = timeout ?? _defaultTimeout;
      final Response response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: headers,
          responseType: responseType ?? ResponseType.json,
          connectTimeout: effectiveTimeout,
          receiveTimeout: effectiveTimeout,
          sendTimeout: effectiveTimeout,
        ),
      );

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response);

      return _errorServer(
        code: response.statusCode.toString(),
        message: response.statusMessage,
      );
    });
  }

  Future<Map<String, dynamic>> postRequest({
    required String url,
    Map? body,
    Map<String, String>? headers = const {},
    Duration? timeout,
  }) async {
    return await tryRequest(() async {
      final Duration effectiveTimeout = timeout ?? _defaultTimeout;
      final Response response = await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          connectTimeout: effectiveTimeout,
          receiveTimeout: effectiveTimeout,
          sendTimeout: effectiveTimeout,
        ),
      );

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response);

      return _errorServer(
        code: response.statusCode.toString(),
        message: response.statusMessage,
      );
    });
  }

  Future<Map<String, dynamic>> getPlatformRequestSendMedia({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) {
      return await SendMedia.sendMedia(
        file: file,
        url: url,
        parameters: parameters,
        headers: headers,
        streamProgress: streamProgress,
        cancelToken: cancelToken,
      );
    }

    return await SendMedia.sendMedia(
      file: file,
      url: url,
      parameters: parameters,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Map<String, dynamic>> sendMedia({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    return await tryRequest(() async {
      Map<String, dynamic> result = await getPlatformRequestSendMedia(
        file: file,
        url: url,
        parameters: parameters,
        headers: headers,
        streamProgress: streamProgress,
        cancelToken: cancelToken,
      );
      return _mapUploadResult(result);
    });
  }

  Future<Map<String, dynamic>> getPlatformRequestSendMediaMultipart({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, dynamic> body = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    return await SendMedia.sendMediaMultipart(
      file: file,
      url: url,
      parameters: parameters,
      body: body,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Map<String, dynamic>> sendMediaMultipart({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, dynamic> body = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    return await tryRequest(() async {
      final Map<String, dynamic> result =
          await getPlatformRequestSendMediaMultipart(
        file: file,
        url: url,
        parameters: parameters,
        body: body,
        headers: headers,
        streamProgress: streamProgress,
        cancelToken: cancelToken,
      );
      return _mapUploadResult(result);
    });
  }

  Map<String, dynamic> _mapUploadResult(Map<String, dynamic> result) {
    if (result['data'] != null) {
      return result;
    }

    final String code = result['exception_code']?.toString() ?? '000';
    final String? errorMessage = (result['detail'] is String)
        ? result['detail'] as String
        : result['detail']?.toString();

    return _errorServer(
      code: code,
      message: errorMessage,
    );
  }

  Map<String, dynamic> _successData(Response response) {
    return {"data": response.data};
  }

  Map<String, dynamic> _errorServer(
      {required String code, required String? message}) {
    return {
      'error': {
        'type': 'server',
        'code': code,
        'message': message,
      }
    };
  }

  Future<Map<String, dynamic>> tryRequest(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout:
          return {
            'error': {
              'type': 'timeout',
              'message': 'The connection has timed out. Try again',
            }
          };
        case DioExceptionType.cancel:
          return {
            'error': {
              'type': 'cancel',
              'code': DefaultAPIFailures.cancelErrorCode,
              'message': 'Request canceled',
            }
          };
        case DioExceptionType.connectionError || DioExceptionType.unknown:
          return {
            'error': {
              'type': 'noConnection',
              'message': 'No internet connection',
            }
          };
        default:
          String? exceptionCode;
          String? errorMessage;

          debugPrint(e.response?.data.toString());

          if (e.response?.data.runtimeType == String) {
            exceptionCode = '000';
            errorMessage = e.response?.data?.toString();
          } else if (e.response?.data is Map) {
            final Map<String, dynamic> responseData =
                Map<String, dynamic>.from(e.response!.data as Map);
            exceptionCode = responseData['exception_code']?.toString();
            errorMessage = responseData['detail']?.toString() ??
                responseData['message']?.toString();
          }

          final String resolvedMessage =
              FailureMessageResolver.resolveUserMessage(
            fallback: e.response?.statusMessage ?? 'Server error',
            serverDetail: errorMessage,
            technicalLog: e.message,
          );

          return _errorServer(
            code: (exceptionCode?.toString() ??
                    (e.response?.statusCode ?? '000').toString())
                .toString(),
            message: resolvedMessage,
          );
      }
    }
  }
}
