import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/helper/send_media_desktop.dart';
import 'package:manager_api/helper/send_media_web/send_media_web.dart';
import 'package:rxdart/rxdart.dart';

class RestHelper {
  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> getRequest({
    required String url,
    Map<String, String>? headers = const {},
    ResponseType? responseType,
  }) async {
    return await tryRequest(() async {
      Response response = await Dio()
          .get(
            url,
            options: Options(
              headers: headers,
              responseType: responseType ?? ResponseType.json,
            ),
          )
          .timeout(_defaultTimeout);

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
  }) async {
    return await tryRequest(() async {
      Response response = await Dio()
          .post(
            url,
            options: Options(
              headers: headers,
            ),
            data: body,
          )
          .timeout(_defaultTimeout);

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
      return await SendMediaWeb.sendMedia(
        file: file,
        url: url,
        parameters: parameters,
        headers: headers,
        streamProgress: streamProgress,
        cancelToken: cancelToken,
      );
    }
    return await SendMediaDesktop.sendMedia(
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
      if (result['data'] != null) {
        return result;
      }

      int? exceptionCode = result['exception_code'];

      String? errorMessage = (result['detail'] is String)
          ? result['detail']
          : result['detail'].toString();

      return _errorServer(
        code: (exceptionCode ?? "000").toString(),
        message: errorMessage,
      );
    });
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

  Future<Map<String, dynamic>> tryRequest(Function() request) async {
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
              'message': 'tempo excedido',
            }
          };
        case DioExceptionType.cancel:
          return {
            'error': {
              'code': DefaultAPIFailures.cancelErrorCode,
              'message': 'canceled by user',
            }
          };
        case DioExceptionType.connectionError || DioExceptionType.unknown:
          return {
            'error': {
              'message': 'no Internet connection',
            }
          };
        default:
          int? exceptionCode = e.response?.data['exception_code'];
          String? errorMessage = e.response?.data['detail'];

          return _errorServer(
            code:
                (exceptionCode ?? (e.response?.statusCode ?? "000")).toString(),
            message: errorMessage ?? e.response?.statusMessage,
          );
      }
    }
  }
}
//
// class MultipartRequestFile extends MultipartRequest {
//   final void Function(int bytes, int totalBytes)? onProgress;
//
//   MultipartRequestFile(
//     String method,
//     Uri url, {
//     this.onProgress,
//   }) : super(method, url);
//
//   @override
//   ByteStream finalize() {
//     final byteStream = super.finalize();
//     if (onProgress == null) return byteStream;
//
//     final total = contentLength;
//     var bytes = 0;
//
//     final t = StreamTransformer.fromHandlers(
//       handleData: (List<int> data, EventSink<List<int>> sink) {
//         bytes += data.length;
//         onProgress?.call(bytes, total);
//         sink.add(data);
//       },
//     );
//     final stream = byteStream.transform(t);
//     return ByteStream(stream);
//   }
// }
